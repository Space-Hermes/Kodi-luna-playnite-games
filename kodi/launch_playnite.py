"""Copy beside launch-config.json in the add-on's userdata directory."""
import json
from pathlib import Path
import sys
from uuid import UUID


def launch_arguments(config, game_id=None):
    for key in ('host', 'moonlight_config', 'coreelec_directory', 'moonlight_binary'):
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise ValueError('Missing launch configuration: ' + key)
    if not isinstance(config.get('hdr4k', False), bool):
        raise ValueError('hdr4k must be boolean')
    app = 'PlayniteBridge-' + str(UUID(game_id)) if game_id else 'PlayniteBridge-Playnite'
    args = ['--host', config['host'], '--config', config['moonlight_config'],
            '--root', config['coreelec_directory'], '--bin', config['moonlight_binary'],
            '--app', app]
    if config.get('hdr4k', False):
        args.append('--4k-hdr')
    return args


if __name__ == '__main__':
    config = json.loads(Path(__file__).with_name('launch-config.json').read_text())
    args = launch_arguments(config, sys.argv[1] if len(sys.argv) > 1 else None)
    sys.path.insert(0, config['coreelec_directory'])
    import kodi_session
    kodi_session.run(args)
