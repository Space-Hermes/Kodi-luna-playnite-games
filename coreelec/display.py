"""Hardware-specific CoreELEC NG Amlogic display handoff; not a generic Linux backend."""

import os
from pathlib import Path
import signal
import subprocess
import time

VFM = Path('/sys/class/vfm/map')

ROUTE = 'playnitebridge_moonlight'

SYSFS = ['/sys/class/graphics/fb0/blank', '/sys/class/graphics/fb1/blank',
         '/sys/class/video/disable_video',
         '/sys/class/graphics/fb0/osd_plane_alpha',
         '/sys/class/graphics/fb1/osd_plane_alpha']

def wait_stopped(pid):
    for _ in range(40):
        status = Path('/proc/%s/status' % pid).read_text()
        state = next(line.split()[1] for line in status.splitlines() if line.startswith('State:'))
        if state in ('T', 't'):
            return
        time.sleep(0.05)
    raise RuntimeError('Kodi did not enter stopped state')

def restore_display(saved, pid):
    errors = []
    mode = '/sys/class/display/mode'
    axis = '/sys/class/video/axis'
    # A mode change can reset OSD state: finish it before exposing Kodi's planes.
    try:
        if mode in saved:
            try:
                if Path(mode).read_text().strip() != saved[mode]:
                    Path(mode).write_text(saved[mode])
                    time.sleep(2)
                    if Path(mode).read_text().strip() != saved[mode]:
                        errors.append('Display mode restoration readback mismatch')
            except OSError as error:
                errors.append(str(error))
        order = [axis, SYSFS[2], SYSFS[3], SYSFS[4], SYSFS[0], SYSFS[1]]
        order += [name for name in saved if name not in order and name != mode]
        for name in order:
            if name not in saved:
                continue
            try:
                Path(name).write_text(saved[name])
            except OSError as error:
                errors.append(str(error))
    finally:
        try:
            os.kill(pid, signal.SIGCONT)
        except OSError as error:
            errors.append(str(error))
    return errors

def snapshot_display():
    saved = {name: Path(name).read_text().strip() for name in SYSFS}
    # CoreELEC's framebuffer blank nodes return no readable value; restore visible Kodi.
    for name in SYSFS[:2]:
        if not saved[name]:
            saved[name] = '0'
    return saved

def remove_route():
    if ROUTE + ' {' not in VFM.read_text():
        return
    # Wait for the client to release its decoder before removing our own route.
    for _ in range(20):
        mapping = VFM.read_text()
        providers = mapping.split('provider list:', 1)[-1].split('receiver list:', 1)[0]
        if 'decoder' not in providers.split():
            VFM.write_text('rm ' + ROUTE + '\n')
            if ROUTE + ' {' in VFM.read_text():
                raise RuntimeError('Temporary video route was not removed')
            return
        time.sleep(0.1)
    raise RuntimeError('Decoder still active; temporary route retained')

def bounded_wait(proc, seconds):
    try:
        return proc.wait(timeout=seconds), False
    except subprocess.TimeoutExpired:
        proc.send_signal(signal.SIGINT)
        try:
            return proc.wait(timeout=5), True
        except subprocess.TimeoutExpired:
            proc.kill()
            return proc.wait(timeout=5), True
