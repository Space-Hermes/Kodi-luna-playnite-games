"""Kodi entry point for session_stream.py; accepts its command-line options."""
import json
from pathlib import Path
import subprocess
import sys
import time

import session_stream


def run(argv=None):
    import fcntl
    import xbmc

    argv = sys.argv[1:] if argv is None else argv
    args = session_stream.arguments(argv)
    root = Path(args.root)
    result = {'audio_resumed': False}
    lock = None
    try:
        root.mkdir(parents=True, exist_ok=True)
        # A second Kodi invocation must not resume audio underneath an active stream.
        lock = (root / 'session-caller.lock').open('a')
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if xbmc.Player().isPlaying():
            raise RuntimeError('Playback active; session cancelled')
        session_stream.client_command(args)
        xbmc.audioSuspend()
        try:
            time.sleep(1)
            status = Path('/proc/asound/card0/pcm3p/sub0/status')
            deadline = time.monotonic() + 2
            while status.read_text().strip() != 'closed':
                if time.monotonic() >= deadline:
                    raise RuntimeError('Kodi HDMI PCM output did not release; session cancelled')
                time.sleep(0.1)
            subprocess.run(['/usr/bin/python3', str(root / 'session_stream.py')] + argv,
                           check=True, start_new_session=True)
        finally:
            xbmc.audioResume()
            result['audio_resumed'] = True
    except Exception as error:
        result['error'] = str(error)
    finally:
        if lock is not None:
            lock.close()
    (root / 'kodi-session-result.json').write_text(json.dumps(result))
    return result


if __name__ == '__main__':
    run()
