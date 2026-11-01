import runpy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


class RecoveryTest(unittest.TestCase):
    def run_case(self, outcomes):
        processes = []
        clock = [0]

        class Process:
            def __init__(self, args, stdout, **kwargs):
                self.outcome = outcomes[len(processes)]
                self.returncode = None if self.outcome == 'stall' else self.outcome
                self.pid = 999999
                if self.outcome == 'stall':
                    stdout.write('Waiting for VM Service port to be available...\n')
                    stdout.flush()
                processes.append(self)

            def poll(self):
                return self.returncode

            def wait(self, timeout=None):
                self.returncode = 1
                return self.returncode

        def sleep(seconds):
            clock[0] += 31

        with tempfile.TemporaryDirectory() as folder:
            with patch.dict('os.environ', {'RUNNER_TEMP': folder}), patch('sys.argv', ['runner', 'fake', 'ios', 'flow.dart']), patch('subprocess.Popen', Process), patch('subprocess.run') as run, patch('os.killpg'), patch('time.monotonic', side_effect=lambda: clock[0]), patch('time.sleep', side_effect=sleep), patch('builtins.print'):
                with self.assertRaises(SystemExit) as exit_result:
                    runpy.run_path(str(Path(__file__).with_name('run_device_test.py')), run_name='__main__')
                reboot_count = sum(call.args[0][2] == 'shutdown' for call in run.call_args_list)
                return exit_result.exception.code, len(processes), reboot_count

    def test_success(self):
        self.assertEqual(self.run_case([0]), (0, 1, 0))

    def test_failure_is_not_retried(self):
        self.assertEqual(self.run_case([1]), (1, 1, 0))

    def test_startup_stall_recovers_once(self):
        self.assertEqual(self.run_case(['stall', 0]), (0, 2, 1))

    def test_repeated_stall_fails(self):
        self.assertEqual(self.run_case(['stall', 'stall']), (1, 2, 1))


unittest.main()
