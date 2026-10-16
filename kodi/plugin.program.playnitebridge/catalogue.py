"""Read-only Playnite catalogue validation and widget selection."""
import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

ROUTES = {'recent': 'Recently played', 'mostplayed': 'Most played',
          'favourites': 'Favourites', 'installed': 'Installed', 'all': 'All games'}


def activity(value):
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError('Invalid last activity')
    date = datetime.fromisoformat(value.replace('Z', '+00:00'))
    # shortcut: unspecified source timezone sorts as UTC; export offsets for precise cross-zone ordering.
    return date.replace(tzinfo=date.tzinfo or timezone.utc).timestamp()


def load_catalogue(path):
    data = json.loads(Path(path).read_text(encoding='utf-8-sig'))
    if not isinstance(data, dict) or data.get('schema_version') != 1 or not isinstance(data.get('games'), list):
        raise ValueError('Unsupported catalogue format')
    games, ids = [], set()
    for raw in data['games']:
        if not isinstance(raw, dict):
            raise ValueError('Invalid game record')
        game = dict(raw)
        if not isinstance(game.get('id'), str):
            raise ValueError('Invalid game ID')
        game['id'] = str(UUID(game['id']))
        if game['id'] in ids or not isinstance(game.get('name'), str) or not game['name'].strip():
            raise ValueError('Duplicate game or missing name')
        ids.add(game['id'])
        for flag in ('installed', 'favourite', 'hidden'):
            if type(game.get(flag)) is not bool:
                raise ValueError('Invalid game flag')
        for field in ('playtime_seconds', 'play_count'):
            if type(game.get(field)) is not int or game[field] < 0:
                raise ValueError('Invalid play statistics')
        game['_activity'] = activity(game.get('last_activity'))
        cover = game.get('cover')
        game['art'] = ''
        if isinstance(cover, str):
            base = Path(path).parent.resolve()
            candidate = (base / cover).resolve()
            try:
                candidate.relative_to(base / 'artwork')
                if candidate.is_file():
                    game['art'] = str(candidate)
            except ValueError:
                pass
        games.append(game)
    return games


def select_games(games, route):
    if route not in ROUTES:
        raise ValueError('Unknown games folder')
    visible = [g for g in games if not g['hidden']]
    if route == 'recent':
        return sorted((g for g in visible if g['_activity'] is not None),
                      key=lambda g: (-g['_activity'], g['name'].casefold(), g['id']))
    if route == 'mostplayed':
        return sorted((g for g in visible if g['playtime_seconds'] > 0),
                      key=lambda g: (-g['playtime_seconds'], g['name'].casefold(), g['id']))
    if route == 'favourites':
        visible = [g for g in visible if g['favourite']]
    elif route == 'installed':
        visible = [g for g in visible if g['installed']]
    return sorted(visible, key=lambda g: (g['name'].casefold(), g['id']))
