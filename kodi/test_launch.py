import unittest
import tempfile
from pathlib import Path
import xml.etree.ElementTree as ET
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

    def test_device_names_are_opt_in_and_discovered_at_launch(self):
        config = dict(host='192.0.2.10', moonlight_config='/example/moonlight.conf',
                      coreelec_directory='/example', moonlight_binary='/example/moonlight')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for event, name in [('event4', 'UR02'), ('event9', 'Xbox Wireless Controller'),
                                ('event2', 'Unrelated keyboard'), ('event6bad', 'UR02')]:
                device = root / event / 'device'
                device.mkdir(parents=True)
                (device / 'name').write_text(name)
            (root / 'event8').mkdir()  # Removed/unreadable input is ignored.
            self.assertNotIn('--input', launch_arguments(config, input_root=root))
            config['input_device_names'] = ['UR02', 'Xbox Wireless Controller']
            args = launch_arguments(config, input_root=root)
            self.assertEqual(args[-4:], ['--input', '/dev/input/event4', '--input', '/dev/input/event9'])
            for invalid in ('UR02', [None], [''], ['  ']):
                config['input_device_names'] = invalid
                with self.assertRaisesRegex(ValueError, 'input_device_names'):
                    launch_arguments(config, input_root=root)

    def test_bluetooth_profile_matches_tested_generic_driver_shape(self):
        profile = ET.parse(Path(__file__).parent / 'buttonmaps/Xbox_Wireless_Controller_15b_8a.xml')
        device = profile.getroot().find('device')
        self.assertEqual((device.get('buttoncount'), device.get('axiscount')), ('15', '8'))
        features = {feature.get('name'): feature for feature in device.find('controller')}
        self.assertEqual(features['up'].get('axis'), '-7')
        self.assertEqual(features['a'].get('button'), '0')


if __name__ == '__main__':
    unittest.main()
