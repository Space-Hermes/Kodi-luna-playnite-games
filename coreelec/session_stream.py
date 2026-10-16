"""Long session supervisor; caller must release Kodi audio and resume it in finally.

Run in a new session (start_new_session=True), alongside display.py.
The independent watchdog watches pipe EOF, not elapsed session time.
"""
import argparse
import configparser
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET

import display


def client_command(args):
    config = configparser.ConfigParser(interpolation=None)
    with open(args.config) as source:
        text = source.read()
    try:
        config.read_string(text)
    except configparser.MissingSectionHeaderError:
        config.read_string('[Moonlight]\n' + text)
    if config.get('Moonlight', 'address', fallback='').strip() != args.host:
        raise RuntimeError('Moonlight config address must match --host')
    if not args.quit_app_after and config.getboolean('Moonlight', 'quitappafter', fallback=False):
        raise RuntimeError('Disable quitappafter in config or explicitly use --quit-app-after')
    command = [args.bin, 'stream', '-config', args.config, '-app', args.app,
               '-audio', args.audio, '-surround', '7.1', '-viewonly']
    if args.quit_app_after:
        command.append('-quitappafter')
    if args.hdr4k:
        command.extend(['-4k', '-fps', '60', '-codec', 'h265', '-hdr', '-bitrate', '40000'])
    return command


def cleanup(saved, kodi_pid):
    errors = []
    try:
        display.remove_route()
    except Exception as error:
        errors.append(str(error))
    errors.extend(display.restore_display(saved, kodi_pid))
    return errors


def watchdog(state, pipe):
    # Only the supervisor owns the pipe writer; Moonlight cannot keep it alive.
    if pipe.readline() == b'done\n':
        return
    errors = []
    try:
        os.killpg(state['supervisor_pid'], signal.SIGKILL)
    except ProcessLookupError:
        pass
    except OSError as error:
        errors.append(str(error))
    errors.extend(cleanup(state['saved'], state['kodi_pid']))
    Path(state['root'], 'session-watchdog.json').write_text(
        json.dumps({'cleanup_errors': errors}))


def wait_client(proc, stop_file, stopping, guard):
    while proc.poll() is None:
        if guard.poll() is not None:
            raise RuntimeError('Recovery watchdog exited during session')
        if stopping.is_set() or stop_file.exists():
            proc.send_signal(signal.SIGINT)
            return display.bounded_wait(proc, 5)[0], 'stopped'
        stopping.wait(0.2)
    return proc.returncode, 'client_exit'


def run(args):
    import fcntl

    if os.getpgrp() != os.getpid():
        raise RuntimeError('Supervisor must run in its own process group')
    root = Path(args.root)
    root.mkdir(parents=True, exist_ok=True)
    # Keep concurrent sessions from sharing a route, stop file or recovery state.
    lock = (root / 'session.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    stopping = threading.Event()
    previous = {sig: signal.signal(sig, lambda *_: stopping.set())
                for sig in (signal.SIGTERM, signal.SIGINT)}
    proc = guard = None
    pid = None
    saved = {}
    result = {}
    stop_file = root / 'session.stop'
    try:
        command = client_command(args)
        if stop_file.exists():
            raise RuntimeError('Remove existing session.stop before starting')
        with urllib.request.urlopen('http://' + args.host + ':47989/serverinfo', timeout=4) as response:
            host = ET.fromstring(response.read())
        if host.findtext('currentgame') != '0':
            raise RuntimeError('Sunshine session already active')
        pids = subprocess.check_output(['pidof', 'kodi.bin'], text=True, timeout=3).split()
        if len(pids) != 1:
            raise RuntimeError('Expected one Kodi process')
        if display.ROUTE + ' {' in display.VFM.read_text():
            raise RuntimeError('Session video route already exists; inspect before continuing')
        saved = display.snapshot_display()
        if args.hdr4k:
            for name in ('/sys/class/display/mode', '/sys/class/video/axis'):
                saved[name] = Path(name).read_text().strip()
        pid = int(pids[0])
        state = {'supervisor_pid': os.getpid(), 'kodi_pid': pid,
                 'saved': saved, 'root': str(root)}
        guard = subprocess.Popen([sys.executable, __file__, '--watchdog', json.dumps(state)],
                                 stdin=subprocess.PIPE, start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 close_fds=True)
        if stopping.wait(0.2) or guard.poll() is not None:
            raise RuntimeError('Session cancelled or recovery watchdog failed to start')
        os.kill(pid, signal.SIGSTOP)
        display.wait_stopped(pid)
        display.VFM.write_text('add ' + display.ROUTE + ' decoder amvideo\n')
        if display.ROUTE + ' {' not in display.VFM.read_text():
            raise RuntimeError('Temporary video route was not created')
        for name, value in zip(display.SYSFS, ['1', '1', '0', '0', '0']):
            Path(name).write_text(value)
        if args.hdr4k:
            Path('/sys/class/display/mode').write_text('2160p60hz')
            if Path('/sys/class/display/mode').read_text().strip() != '2160p60hz':
                raise RuntimeError('4K60 display mode did not activate')
            Path('/sys/class/video/axis').write_text('0 0 3839 2159')
            # Allow HDMI's delayed SDR cleanup to settle before decoder HDR signalling.
            time.sleep(2)
        env = os.environ.copy()
        env['LD_LIBRARY_PATH'] = str(root / 'lib') + ':' + env.get('LD_LIBRARY_PATH', '')
        with (root / 'session-stream.log').open('w') as log:
            proc = subprocess.Popen(command,
                                    cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    close_fds=True)
            result['exit_code'], result['reason'] = wait_client(proc, stop_file, stopping, guard)
    except Exception as error:
        result['error'] = str(error)
    finally:
        errors = []
        if proc is not None and proc.poll() is None:
            try:
                proc.kill()
                proc.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired) as error:
                errors.append(str(error))
        if guard is not None:
            errors.extend(cleanup(saved, pid))
            result['cleanup_errors'] = errors
            (root / 'session-result.json').write_text(json.dumps(result, indent=2))
            try:
                if not errors:
                    guard.stdin.write(b'done\n')
                    guard.stdin.flush()
                guard.stdin.close()
                guard.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired) as error:
                errors.append(str(error))
        result['cleanup_errors'] = errors
        (root / 'session-result.json').write_text(json.dumps(result, indent=2))
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        lock.close()
    return result


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='/storage/playnite-bridge')
    parser.add_argument('--bin', default='/storage/playnite-bridge/bin/moonlight')
    parser.add_argument('--config', required=True)
    parser.add_argument('--app', default='Playnite')
    parser.add_argument('--host', required=True)
    parser.add_argument('--audio', default='surround71:CARD=AMLAUGESOUND,DEV=0')
    parser.add_argument('--quit-app-after', action='store_true',
                        help='Ask Sunshine to close the PC app on disconnect')
    parser.add_argument('--4k-hdr', dest='hdr4k', action='store_true')
    return parser.parse_args(argv)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--watchdog':
        watchdog(json.loads(sys.argv[2]), sys.stdin.buffer)
    else:
        outcome = run(arguments())
        sys.exit(1 if outcome.get('error') or outcome['cleanup_errors'] else 0)
