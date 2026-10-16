import json
import unittest
from xbox_kodi_action import request, ALLOWED

class PlaybackActionTests(unittest.TestCase):
    def test_allowed_actions_use_input_api(self):
        for action in ALLOWED:
            payload = json.loads(request(action))
            self.assertEqual(payload['method'], 'Input.ExecuteAction')
            self.assertEqual(payload['params'], {'action': action})

    def test_other_actions_rejected(self):
        with self.assertRaises(ValueError):
            request('stop')

if __name__ == '__main__':
    unittest.main()
