import unittest
from launch_playnite import launch_arguments


class LaunchTest(unittest.TestCase):
    def test_explicit_paths_and_game(self):
        config = dict(host='192.0.2.10', moonlight_config='/example/moonlight.conf',
                      coreelec_directory='/example', moonlight_binary='/example/moonlight', hdr4k=True)
        game = '11111111-2222-3333-4444-555555555555'
        args = launch_arguments(config, game)
        self.assertIn('PlayniteBridge-' + game, args)
        self.assertIn('--4k-hdr', args)
        self.assertIn(config['host'], args)
        self.assertIn('PlayniteBridge-Playnite', launch_arguments(config))
        with self.assertRaises(ValueError):
            launch_arguments(config, 'invalid')
        with self.assertRaises(ValueError):
            launch_arguments({})


if __name__ == '__main__':
    unittest.main()
