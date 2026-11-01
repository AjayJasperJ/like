"""Bound native test startup/execution and capture a failure screenshot."""
import os
import signal
import subprocess
import sys
from pathlib import Path

device, platform, test_file = sys.argv[1:]
output = Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'device-diagnostics'
output.mkdir(parents=True, exist_ok=True)

def screenshot():
    target = output / (platform + '-' + Path.cwd().name + '-' + Path(test_file).stem + '.png')
    try:
        if platform == 'ios':
            subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(target)], timeout=30, check=False)
        else:
            with target.open('wb') as image:
                subprocess.run(['adb', '-s', device, 'exec-out', 'screencap', '-p'], stdout=image, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired):
        print('Failure screenshot unavailable', flush=True)

print('Running ' + platform + ' ' + Path.cwd().name + ' ' + test_file, flush=True)
log_path = output / (platform + '-' + Path.cwd().name + '-' + Path(test_file).stem + '.log')
log_file = log_path.open('w')
process = subprocess.Popen(
    ['flutter', 'test', test_file, '-d', device, '--reporter', 'expanded', '--verbose'],
    stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True,
)

def stop():
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

try:
    result = process.wait(timeout=600)
except subprocess.TimeoutExpired:
    screenshot()
    stop()
    log_file.close()
    print(log_path.read_text()[-24000:], flush=True)
    raise SystemExit('Native test exceeded its ten-minute startup/execution limit')
except KeyboardInterrupt:
    stop()
    raise
log_file.close()
print(log_path.read_text()[-24000:], flush=True)
if result:
    screenshot()
raise SystemExit(result)
