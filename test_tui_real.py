"""Real terminal smoke tests. Run scripts/setup-deps before this suite."""
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import termios
import time
import unittest

import test_tui


class RealTerminal(unittest.TestCase):
    def setUp(self):
        self.fixture = test_tui.PullRequestFlow()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        dependency = test_tui.ROOT / ".deps/fzf/fzf"
        self.assertTrue(dependency.is_file(), "Run ./scripts/setup-deps first")
        shutil.copy2(dependency, self.fixture.package / ".deps/fzf/fzf")
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            env = dict(os.environ, TERM="xterm-256color", FLOW_ROOT=str(self.fixture.root),
                       PATH=str(self.fixture.bin) + os.pathsep + os.environ["PATH"],
                       FZF_DEFAULT_OPTS="--filter=stable --bind=start:accept")
            os.chdir(self.fixture.root)
            os.execve(str(self.fixture.package / "quill"),
                      ["quill", "pr", str(self.fixture.repo)], env)
        self.addCleanup(self.stop)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        self.output = bytearray()
        self.wait_text(b"base branch")

    def stop(self):
        # Closing the controlling terminal also stops its foreground fzf process.
        os.close(self.fd)
        pid, _ = os.waitpid(self.pid, os.WNOHANG)
        if not pid:
            try:
                os.kill(self.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(self.pid, 0)

    def wait_text(self, text):
        deadline = time.monotonic() + 15
        while text not in self.output:
            self.assertLess(time.monotonic(), deadline, self.output.decode(errors="replace"))
            if select.select([self.fd], [], [], 0.1)[0]:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    self.fail("Terminal closed: " + self.output.decode(errors="replace"))
                self.output.extend(data)
                # fzf asks for cursor position while initializing the terminal.
                if b"\x1b[6n" in data:
                    os.write(self.fd, b"\x1b[1;1R")
        self.output.clear()

    def send(self, keys):
        os.write(self.fd, keys)

    def wait_file(self, name):
        deadline = time.monotonic() + 10
        path = self.fixture.root / name
        while not path.exists():
            self.assertLess(time.monotonic(), deadline, "Missing " + name)
            if select.select([self.fd], [], [], 0.05)[0]:
                try:
                    os.read(self.fd, 65536)
                except OSError:
                    break
        self.assertTrue(path.exists(), "Missing " + name)
        return path

    def test_filter_and_keyboard_approval(self):
        self.send(b"stable")
        self.wait_text(b"stable")
        self.send(b"\r")
        self.wait_text(b"Review pull request")
        self.assertFalse((self.fixture.root / "created").exists())
        self.send(b"\x1b[6~")  # Page Down in preview
        self.send(b"\r")
        import json
        result = json.loads(self.wait_file("created").read_text())
        self.assertEqual(result["args"][result["args"].index("--base") + 1], "stable")

    def test_escape_returns_to_selection_then_cancels(self):
        self.send(b"master\r")
        self.wait_text(b"Review pull request")
        self.send(b"\x1b")
        self.wait_text(b"base branch")
        self.send(b"\x1b")
        self.wait_text(b"cancelled")
        self.assertFalse((self.fixture.root / "created").exists())

    def test_mouse_selection_and_preview_cancellation(self):
        # Reverse layout: border, input, info, two header lines, then candidates.
        # Two SGR clicks select and accept the first candidate.
        self.send(b"\x1b[<0;8;7M\x1b[<0;8;7m")
        time.sleep(0.1)
        self.send(b"\x1b[<0;8;7M\x1b[<0;8;7m")
        self.wait_text(b"Review pull request")
        self.send(b"\x1b[<65;20;10M")  # Mouse wheel in preview
        self.send(b"\x03")
        self.wait_text(b"cancelled")
        self.assertFalse((self.fixture.root / "created").exists())


if __name__ == "__main__":
    unittest.main()
