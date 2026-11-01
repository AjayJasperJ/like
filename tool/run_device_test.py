"""Bound native tests; recover once from an iOS VM-service discovery stall."""
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

device, platform, test_file = sys.argv[1:]
output = Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'device-diagnostics'
output.mkdir(parents=True, exist_ok=True)
stem = platform + '-' + Path.cwd().name + '-' + Path(test_file).stem


def screenshot(attempt):
    target = output / (stem + '-' + str(attempt) + '.png')
    try:
        if platform == 'ios':
            subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(target)], timeout=30, check=False)
        else:
            with target.open('wb') as image:
                subprocess.run(['adb', '-s', device, 'exec-out', 'screencap', '-p'], stdout=image, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired):
        print('Failure screenshot unavailable', flush=True)


def stop(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    except ProcessLookupError:
        pass


for attempt in range(1, 3):
    log_path = output / (stem + '-' + str(attempt) + '.log')
    print('Running ' + stem + ' attempt ' + str(attempt), flush=True)
    stalled = False
    waiting_since = None
    started = time.monotonic()
    with log_path.open('w') as log_file:
        process = subprocess.Popen(
            ['flutter', 'test', test_file, '-d', device, '--reporter', 'expanded', '--verbose'],
            stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True,
        )
        try:
            while process.poll() is None:
                now = time.monotonic()
                log = log_path.read_text(errors='replace')
                # Discovery precedes all test execution. Never retry a connected
                # test, a compiler error, or an assertion failure.
                discovering = (
                    platform == 'ios'
                    and 'Waiting for VM Service port to be available' in log
                    and 'VM Service URL on device:' not in log
                    and 'Connecting to VM Service' not in log
                )
                if discovering:
                    if waiting_since is None:
                        waiting_since = now
                    if now - waiting_since >= 90:
                        stalled = True
                        break
                else:
                    waiting_since = None
                if now - started >= 600:
                    break
                time.sleep(1)
            if process.poll() is None:
                screenshot(attempt)
                stop(process)
                result = 1
            else:
                result = process.returncode
        except KeyboardInterrupt:
            stop(process)
            raise
    print(log_path.read_text(errors='replace')[-24000:], flush=True)
    if result == 0:
        raise SystemExit(0)
    if not stalled or attempt == 2:
        screenshot(attempt)
        raise SystemExit(result)
    print('::warning::iOS VM-service discovery stalled before tests; rebooting simulator for one retry', flush=True)
    subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=True, timeout=60)
    subprocess.run(['xcrun', 'simctl', 'boot', device], check=True, timeout=60)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True, timeout=180)
