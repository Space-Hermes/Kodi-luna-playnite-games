import io
import signal
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch, mock_open

import session_stream as session
import kodi_session


BASE = ['--host', '192.0.2.10', '--config', '/example/moonlight.conf']

class SessionTest(unittest.TestCase):
    def test_controller_input_is_opt_in_and_rejects_viewonly_config(self):
        config = 'address=192.0.2.10\n'
        with patch('builtins.open', mock_open(read_data=config)):
            self.assertIn('-viewonly', session.client_command(session.arguments(BASE)))
            command = session.client_command(session.arguments(BASE + ['--input', '/dev/input/event5']))
        self.assertNotIn('-viewonly', command)
        self.assertEqual(command[-2:], ['-input', '/dev/input/event5'])
        self.assertEqual(command[command.index('-mapping') + 1],
                         str(Path('/storage/playnite-bridge/bin/gamecontrollerdb.txt')))
        with patch('builtins.open', mock_open(read_data=config)):
            combined = session.client_command(session.arguments(
                BASE + ['--input', '/dev/input/event5', '--input', '/dev/input/event4']))
        self.assertEqual(combined[-4:], ['-input', '/dev/input/event5', '-input', '/dev/input/event4'])
        with patch('builtins.open', mock_open(read_data=config + 'viewonly=true\n')):
            with self.assertRaisesRegex(RuntimeError, 'Disable viewonly'):
                session.client_command(session.arguments(BASE + ['--input', '/dev/input/event5']))

    def test_bundled_mappings_use_tested_hat_dpad(self):
        source = Path(__file__).with_name('gamecontrollerdb.example.txt').read_text()
        mappings = [line.split(',') for line in source.splitlines() if line and not line.startswith('#')]
        self.assertEqual({row[0] for row in mappings},
                         {'030000005e040000120b00000f050000', '050000005e040000130b000015050000'})
        for row in mappings:
            self.assertTrue({'dpup:h0.1', 'dpdown:h0.4', 'dpleft:h0.8', 'dpright:h0.2',
                             'platform:Linux'}.issubset(set(row)))

    def test_sectionless_config_and_hdr_command(self):
        args = session.arguments(BASE + ['--4k-hdr'])
        with patch('builtins.open', mock_open(read_data='# Moonlight config\naddress = 192.0.2.10\n')):
            command = session.client_command(args)
        self.assertNotIn(args.host, command)
        self.assertEqual(command[-8:], ['-4k', '-fps', '60', '-codec', 'h265', '-hdr', '-bitrate', '40000'])

    def run_caller(self, status_values, clock_values):
        xbmc = Mock()
        xbmc.Player.return_value.isPlaying.return_value = False
        fcntl = Mock(LOCK_EX=2, LOCK_NB=4)
        with patch.dict(sys.modules, {'xbmc': xbmc, 'fcntl': fcntl}), \
             patch.object(Path, 'mkdir'), patch.object(Path, 'open', mock_open()), \
             patch.object(Path, 'write_text'), \
             patch.object(Path, 'read_text', side_effect=status_values), \
             patch.object(kodi_session.session_stream, 'client_command'), \
             patch.object(kodi_session.time, 'sleep'), \
             patch.object(kodi_session.time, 'monotonic', side_effect=clock_values), \
             patch.object(kodi_session.subprocess, 'run') as launch:
            result = kodi_session.run(BASE)
        return result, xbmc, launch

    def test_caller_timeout_resumes_audio_without_launch(self):
        result, xbmc, launch = self.run_caller(['RUNNING'], [0, 3])
        self.assertIn('did not release', result['error'])
        self.assertTrue(result['audio_resumed'])
        launch.assert_not_called()
        xbmc.audioResume.assert_called_once()

    def test_caller_read_failure_resumes_audio_without_launch(self):
        result, xbmc, launch = self.run_caller(OSError('status unreadable'), [0])
        self.assertIn('status unreadable', result['error'])
        launch.assert_not_called()
        xbmc.audioResume.assert_called_once()

    def test_caller_launches_without_session_deadline_and_resumes_audio(self):
        result, xbmc, launch = self.run_caller(['closed'], [0])
        self.assertTrue(result['audio_resumed'])
        self.assertNotIn('error', result)
        self.assertTrue(launch.call_args.kwargs['start_new_session'])
        self.assertNotIn('timeout', launch.call_args.kwargs)
        xbmc.audioResume.assert_called_once()

    def test_command_uses_config_host_and_keeps_app_running_by_default(self):
        with patch('sys.argv', ['session_stream.py']):
            args = session.arguments(BASE)
        with patch('builtins.open', mock_open(read_data='[Moonlight]\naddress=192.0.2.10\n')):
            command = session.client_command(args)
        self.assertNotIn(args.host, command)
        self.assertNotIn('-quitappafter', command)
        self.assertEqual(command[command.index('-config') + 1], args.config)
        args.quit_app_after = True
        with patch('builtins.open', mock_open(read_data='[Moonlight]\naddress=192.0.2.10\n')):
            self.assertIn('-quitappafter', session.client_command(args))

    def test_command_rejects_other_host_or_implicit_app_shutdown(self):
        with patch('sys.argv', ['session_stream.py']):
            args = session.arguments(BASE)
        for config, error in [('[Moonlight]\naddress=other\n', 'address must match'),
                              ('[Moonlight]\naddress=192.0.2.10\nquitappafter=true\n',
                               'Disable quitappafter')]:
            with self.subTest(config=config), patch('builtins.open', mock_open(read_data=config)):
                with self.assertRaisesRegex(RuntimeError, error):
                    session.client_command(args)

    def test_normal_exit_has_no_time_limit(self):
        proc = Mock(returncode=0)
        proc.poll.side_effect = [None] * 500 + [0]
        stopping = Mock()
        stopping.is_set.return_value = False
        stop_file = Mock()
        stop_file.exists.return_value = False
        guard = Mock()
        guard.poll.return_value = None
        self.assertEqual(session.wait_client(proc, stop_file, stopping, guard), (0, 'client_exit'))
        self.assertEqual(stopping.wait.call_count, 500)
        proc.send_signal.assert_not_called()

    def test_stop_file_interrupts_client(self):
        proc = Mock()
        proc.poll.return_value = None
        guard = Mock()
        guard.poll.return_value = None
        stopping = Mock()
        stopping.is_set.return_value = False
        stop_file = Mock()
        stop_file.exists.return_value = True
        with patch.object(session.display, 'bounded_wait', return_value=(0, False)) as wait:
            self.assertEqual(session.wait_client(proc, stop_file, stopping, guard), (0, 'stopped'))
        proc.send_signal.assert_called_once_with(signal.SIGINT)
        wait.assert_called_once_with(proc, 5)

    def test_signal_requests_stop(self):
        proc = Mock()
        proc.poll.return_value = None
        guard = Mock()
        guard.poll.return_value = None
        stopping = Mock()
        stopping.is_set.return_value = True
        with patch.object(session.display, 'bounded_wait', return_value=(0, False)):
            self.assertEqual(session.wait_client(proc, Mock(), stopping, guard), (0, 'stopped'))
        proc.send_signal.assert_called_once_with(signal.SIGINT)

    @patch.object(signal, 'SIGKILL', 9, create=True)
    @patch('session_stream.os.killpg', create=True)
    def test_pipe_eof_recovers_after_supervisor_death(self, killpg):
        state = {'supervisor_pid': 456, 'kodi_pid': 123,
                 'saved': {'display': '0'}, 'root': '/fake', 'input_devices': ['/dev/input/event5']}
        with patch.object(session, 'cleanup', return_value=[]) as cleanup, \
             patch.object(Path, 'write_text'):
            session.watchdog(state, io.BytesIO(b''))
        killpg.assert_called_once_with(456, signal.SIGKILL)
        cleanup.assert_called_once_with({'display': '0'}, 123, ['/dev/input/event5'])

    def test_cleanup_restores_input_after_display_failure(self):
        with patch.object(session.display, 'remove_route'), \
             patch.object(session.display, 'restore_display', return_value=['display failed']), \
             patch.object(session, 'handoff_inputs') as handoff:
            self.assertEqual(session.cleanup({}, 123, ['remote']), ['display failed'])
        handoff.assert_called_once_with(['remote'], 'add')

    def test_handoff_rejects_non_evdev_path_before_any_action(self):
        with patch.object(session.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                session.handoff_inputs(['/tmp/not-input'], 'remove')
        run.assert_not_called()

    @patch('session_stream.os.killpg', create=True)
    def test_success_message_disarms_watchdog(self, killpg):
        with patch.object(session, 'cleanup') as cleanup:
            session.watchdog({}, io.BytesIO(b'done\n'))
        killpg.assert_not_called()
        cleanup.assert_not_called()

    def test_route_cleanup_failure_still_resumes_kodi(self):
        with patch.object(session.display, 'remove_route', side_effect=RuntimeError('busy')), \
             patch.object(session.display, 'restore_display', return_value=[]) as restore:
            self.assertEqual(session.cleanup({'x': '0'}, 123), ['busy'])
        restore.assert_called_once_with({'x': '0'}, 123)

    def test_dead_watchdog_stops_session(self):
        proc = Mock()
        proc.poll.return_value = None
        guard = Mock()
        guard.poll.return_value = 1
        with self.assertRaisesRegex(RuntimeError, 'watchdog exited'):
            session.wait_client(proc, Mock(), Mock(), guard)


if __name__ == '__main__':
    unittest.main()
