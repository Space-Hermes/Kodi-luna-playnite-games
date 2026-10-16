"""Send playback-menu actions through Kodi's idle-timer-aware input path."""
import json
import sys

ALLOWED = {'osd', 'select', 'close', 'up', 'down', 'left', 'right'}


def request(action):
    if action not in ALLOWED:
        raise ValueError('Unsupported playback-menu action')
    return json.dumps({'jsonrpc': '2.0', 'id': 1,
                       'method': 'Input.ExecuteAction', 'params': {'action': action}})


if __name__ == '__main__':
    import xbmc
    result = json.loads(xbmc.executeJSONRPC(request(sys.argv[1])))
    if 'error' in result:
        raise RuntimeError(str(result['error']))
