import signal
import unittest
from unittest.mock import patch

import display as pilot


class DisplayRestoreTest(unittest.TestCase):
    def restore(self, failure=None, current='2160p60hz'):
        mode = '/sys/class/display/mode'
        axis = '/sys/class/video/axis'
        saved = dict(zip(pilot.SYSFS, ['0', '0', '2', '256', '256']))
        saved.update({mode: '1080p60hz', axis: '0 0 1919 1079'})
        events = []
        values = {mode: current}

        def read(path):
            if failure == 'read':
                raise OSError('read failed')
            return values[path.as_posix()]

        def write(path, value):
            name = path.as_posix()
            events.append((name, value))
            if failure == name:
                raise OSError('write failed')
            if failure != 'mismatch':
                values[name] = value

        with patch.object(pilot.Path, 'read_text', read), \
             patch.object(pilot.Path, 'write_text', write), \
             patch.object(pilot.time, 'sleep', side_effect=lambda n: events.append(('sleep', n))), \
             patch.object(signal, 'SIGCONT', 18, create=True), \
             patch.object(pilot.os, 'kill', side_effect=lambda *args: events.append(('resume', args))):
            errors = pilot.restore_display(saved, 123)
        return events, errors, saved

    def test_mode_settles_before_planes_and_resume(self):
        events, errors, saved = self.restore()
        expected = ['/sys/class/display/mode', 'sleep', '/sys/class/video/axis',
                    pilot.SYSFS[2], pilot.SYSFS[3], pilot.SYSFS[4],
                    pilot.SYSFS[0], pilot.SYSFS[1], 'resume']
        self.assertEqual([event[0] for event in events], expected)
        self.assertEqual(events[1], ('sleep', 2))
        self.assertEqual(errors, [])

    def test_unchanged_mode_does_not_switch_or_wait(self):
        events, errors, _ = self.restore(current='1080p60hz')
        self.assertNotIn('sleep', [event[0] for event in events])
        self.assertNotIn('/sys/class/display/mode', [event[0] for event in events])
        self.assertEqual(errors, [])

    def test_failures_still_restore_remaining_planes_and_resume(self):
        for failure in ('read', '/sys/class/display/mode', pilot.SYSFS[3], 'mismatch'):
            with self.subTest(failure=failure):
                events, errors, _ = self.restore(failure)
                self.assertTrue(errors)
                self.assertIn((pilot.SYSFS[1], '0'), events)
                self.assertEqual(events[-1], ('resume', (123, 18)))
                if failure == 'read':
                    self.assertNotIn('/sys/class/display/mode', [event[0] for event in events])


if __name__ == '__main__':
    unittest.main()
