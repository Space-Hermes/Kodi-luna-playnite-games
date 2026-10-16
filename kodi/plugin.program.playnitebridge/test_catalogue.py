import json
from pathlib import Path
import tempfile
import unittest

from catalogue import load_catalogue, select_games


class CatalogueTests(unittest.TestCase):
    def test_widgets_and_art_boundary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'artwork').mkdir()
            (root / 'artwork' / 'cover.png').write_bytes(b'image')
            (root / 'private.png').write_bytes(b'not artwork')
            games = []
            for i in range(4):
                games.append(dict(id='00000000-0000-0000-0000-%012d' % i,
                                  name=['Zelda', 'Pokémon', 'Hidden', 'Unplayed'][i],
                                  installed=i == 0, favourite=i == 1, hidden=i == 2,
                                  playtime_seconds=[30, 60, 500, 0][i], play_count=i,
                                  last_activity=['2026-01-01T12:00:00+02:00',
                                                 '2026-01-01T11:00:00Z', None, None][i],
                                  cover=['artwork/cover.png', 'artwork/../private.png',
                                         'https://example.invalid/x.png', None][i]))
            path = root / 'catalogue.json'
            path.write_text(json.dumps(dict(schema_version=1, games=games)), encoding='utf-8')
            loaded = load_catalogue(path)
            self.assertTrue(loaded[0]['art'].endswith('cover.png'))
            self.assertEqual(loaded[1]['art'], '')
            self.assertEqual(loaded[2]['art'], '')
            for route in ('recent', 'mostplayed', 'favourites'):
                self.assertEqual(select_games(loaded, route)[0]['name'], 'Pokémon')
            self.assertEqual(len(select_games(loaded, 'all')), 3)
            self.assertEqual([g['name'] for g in select_games(loaded, 'installed')], ['Zelda'])
            for bad in ({'schema_version': 2, 'games': []},
                        {'schema_version': 1, 'games': [games[0], games[0]]},
                        {'schema_version': 1, 'games': [dict(games[0], playtime_seconds=-1)]}):
                path.write_text(json.dumps(bad), encoding='utf-8')
                with self.assertRaises(ValueError):
                    load_catalogue(path)
            path.write_text('{', encoding='utf-8')
            with self.assertRaises(ValueError):
                load_catalogue(path)

    def test_empty_and_missing(self):
        self.assertEqual(select_games([], 'recent'), [])
        with self.assertRaises(OSError):
            load_catalogue('missing-catalogue-test-file.json')
        with self.assertRaises(ValueError):
            select_games([], 'unknown')


if __name__ == '__main__':
    unittest.main()
