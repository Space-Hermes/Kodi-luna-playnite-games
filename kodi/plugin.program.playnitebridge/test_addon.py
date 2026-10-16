import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch


class KodiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.profile = Path(self.temp.name)
        self.modules = {name: MagicMock() for name in
                        ('xbmc', 'xbmcaddon', 'xbmcgui', 'xbmcplugin', 'xbmcvfs')}
        self.modules['xbmcvfs'].translatePath.return_value = str(self.profile)
        self.patch = patch.dict(sys.modules, self.modules)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        sys.modules.pop('addon', None)
        self.addon = importlib.import_module('addon')

    def run_route(self, query):
        with patch.object(sys, 'argv', ['plugin://plugin.program.playnitebridge/', '1', query]):
            self.addon.run()

    def test_root_and_missing_catalogue(self):
        self.run_route('')
        self.assertEqual(self.modules['xbmcplugin'].addDirectoryItem.call_count, 6)
        urls = [call.args[1] for call in self.modules['xbmcplugin'].addDirectoryItem.call_args_list]
        self.assertIn('plugin://plugin.program.playnitebridge/?route=recent', urls)
        self.run_route('?route=recent')
        self.modules['xbmcgui'].ListItem.assert_called_with(label='Library unavailable - open Playnite')
        self.modules['xbmc'].executebuiltin.assert_not_called()

    def test_launch_hook_passes_validated_game_id(self):
        self.run_route('?route=launch')
        self.modules['xbmcgui'].Dialog().ok.assert_called_once()
        self.modules['xbmc'].executebuiltin.assert_not_called()
        game_id = '00000000-0000-0000-0000-000000000001'
        game = dict(id=game_id, name='Pokémon', installed=True, favourite=False,
                    hidden=False, last_activity=None, playtime_seconds=0, play_count=0, cover=None)
        (self.profile / 'catalogue.json').write_text(json.dumps(dict(schema_version=1, games=[game])), encoding='utf-8')
        (self.profile / 'launch_playnite.py').write_text('# test placeholder', encoding='utf-8')
        self.run_route('?route=launch&id=' + game_id)
        self.modules['xbmc'].executebuiltin.assert_called_once_with(
            'RunScript("%s",%s)' % (self.profile / 'launch_playnite.py', game_id))
        self.modules['xbmc'].executebuiltin.reset_mock()
        self.run_route('?route=launch&id=invalid%29%2CShutdown%28')
        self.modules['xbmc'].executebuiltin.assert_not_called()


if __name__ == '__main__':
    unittest.main()
