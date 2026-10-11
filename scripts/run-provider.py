"""Own one provider process group until it has completed or been cancelled."""

import os
import signal
import subprocess
import sys


child = None
cancelled = 0


def terminate_group():
    if child is not None:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def cancel(signum, _frame):
    global cancelled
    cancelled = signum
    terminate_group()


for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(signum, cancel)

try:
    # A separate session keeps cancellation confined to this invocation's children.
    if not cancelled:
        child = subprocess.Popen(sys.argv[1:], start_new_session=True)
        if cancelled:
            terminate_group()
        result = child.wait()
    else:
        result = 128 + cancelled
finally:
    # Also remove descendants left behind by a provider that has already exited.
    terminate_group()
    if child is not None:
        child.wait()

sys.exit(128 + cancelled if cancelled else (128 - result if result < 0 else result))
