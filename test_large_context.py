"""Offline CLI regression checks. No real providers, commits, or installation."""

import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import sqlite3
import struct
import subprocess
import sys
import tempfile
import termios
import time


ROOT = Path(__file__).resolve().parent
FAKE_PROVIDER = r'''
import json, os, signal, sqlite3, subprocess, sys, time
from pathlib import Path
root = Path(os.environ["FAKE_STATE"])
prompt = sys.stdin.buffer.read()
with sqlite3.connect(root / "calls.db") as db:
    db.execute("BEGIN IMMEDIATE")
    active, peak = db.execute("SELECT active, peak FROM state").fetchone()
    db.execute("UPDATE state SET active=?, peak=?", (active + 1, max(peak, active + 1)))
    cursor = db.execute("INSERT INTO calls(prompt) VALUES (?)", (prompt,))
    call = cursor.lastrowid
(root / f"prompt-{call}").write_bytes(prompt)
if os.environ.get("FAKE_BLOCK"):
    # Prove cancellation reaches descendants, including ones ignoring TERM/INT.
    child = subprocess.Popen([sys.executable, "-c", "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); signal.signal(signal.SIGINT, signal.SIG_IGN); print('ready', flush=True); time.sleep(300)"], stdout=subprocess.PIPE)
    child.stdout.readline()
    (root / "pids").write_text(json.dumps([os.getpid(), child.pid]))
    while True: time.sleep(1)
time.sleep(float(os.environ.get("FAKE_DELAY", "0.03")))
if os.environ.get("FAKE_FAIL"):
    print("ordinary provider failure", file=sys.stderr)
    sys.exit(7)
if b"Summarize this portion" in prompt:
    response = "- Preserve the requested change across files.\n"
else:
    response = "Describe the complete change\n\nPreserve behavior and update assets.\n"
if "-o" in sys.argv:
    Path(sys.argv[sys.argv.index("-o") + 1]).write_text(response)
else:
    print(response, end="")
with sqlite3.connect(root / "calls.db") as db:
    db.execute("UPDATE state SET active=active-1")
'''


def run(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def git(repo, *args):
    return run("git", "-C", str(repo), *args, env=dict(os.environ, GIT_OPTIONAL_LOCKS="0")).stdout


def snapshot(repo):
    git_dir = Path(os.fsdecode(git(repo, "rev-parse", "--absolute-git-dir")).strip())
    index = git_dir / "index"
    return (
        hashlib.sha256(index.read_bytes()).hexdigest() if index.exists() else None,
        git(repo, "symbolic-ref", "HEAD"),
        subprocess.run(["git", "-C", str(repo), "rev-parse", "--verify", "HEAD"], capture_output=True).stdout,
        git(repo, "status", "--porcelain=v1", "-z"),
        hashlib.sha256(git(repo, "diff", "--cached", "--no-ext-diff")).hexdigest(),
        hashlib.sha256(git(repo, "diff", "--no-ext-diff")).hexdigest(),
    )


class Harness:
    def __init__(self, root, provider="codex", budget=20000):
        self.root = root
        self.root.mkdir()
        self.bin = root / "bin"
        self.bin.mkdir()
        for name in ("codex", "claude", "gemini"):
            script = self.bin / name
            script.write_text(f"#!{sys.executable}\n" + FAKE_PROVIDER)
            script.chmod(0o755)
        with sqlite3.connect(root / "calls.db") as db:
            db.executescript("CREATE TABLE state(active, peak); INSERT INTO state VALUES (0,0); CREATE TABLE calls(prompt BLOB);")
        self.config = root / "quill.config"
        self.config.write_text(
            f"DEFAULT_PROVIDER={provider}\n{provider.upper()}_MAX_PROMPT_BYTES={budget}\n"
            f"{provider.upper()}_FALLBACK_MODEL=\n"
        )
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        FAKE_STATE=str(root), XDG_CACHE_HOME=str(root / "cache"),
                        TMPDIR=str(root), GIT_OPTIONAL_LOCKS="0")

    def command(self, repo, verbose=False):
        return [str(ROOT / "quill"), "--config", str(self.config), "--quit",
                *(["--verbose"] if verbose else []), str(repo)]

    def generate(self, repo, failure=False, verbose=False):
        env = dict(self.env)
        if failure:
            env["FAKE_FAIL"] = "1"
        before = snapshot(repo)
        result = subprocess.run(self.command(repo, verbose), env=env, capture_output=True, timeout=60)
        assert snapshot(repo) == before, "Generation changed Git state"
        assert (result.returncode != 0) == failure, result.stderr.decode()
        assert not any(path.is_dir() for path in self.root.glob("quill.*")), "Temporary generation files remain"
        return result

    def calls(self):
        with sqlite3.connect(self.root / "calls.db") as db:
            prompts = [row[0] for row in db.execute("SELECT prompt FROM calls ORDER BY rowid")]
            active, peak = db.execute("SELECT active, peak FROM state").fetchone()
        return prompts, active, peak


def staged_repo(path, content):
    run("git", "init", "-q", str(path))
    for name, data in content.items():
        (path / name).write_bytes(data)
    git(path, "add", "--all")
    return path


def check_payloads(root):
    payload = base64.b64encode(b"asset bytes" * 30000)
    other = base64.b64encode(b"other bytes" * 30000)
    content = (b'<img src="data:image/png;base64,' + payload + b'">keep surrounding code\n'
               b'<img src="data:image/png;base64,' + other + b'">second asset\n'
               b'<img src="DATA:image/svg+xml;charset=utf-8;BASE64,QUJD">metadata\n'
               b'plain Base64 stays: QUJD\ninvalid: "data:image/png;base64,invalid!"\n'
               b'ordinary data URI: "data:text/plain,hello"\n')
    repo = staged_repo(root / "assets", {"assets.html": content})
    for provider in ("codex", "claude", "gemini"):
        harness = Harness(root / f"payload-{provider}")
        harness.config.write_text(f"DEFAULT_PROVIDER={provider}\n{provider.upper()}_FALLBACK_MODEL=\n")
        harness.generate(repo)
        prompts, active, peak = harness.calls()
        assert len(prompts) == 1 and active == 0 and peak == 1
        prompt = prompts[0]
        assert payload not in prompt and other not in prompt
        for original in (payload, other):
            assert str(len(original)).encode() + b" encoded bytes" in prompt
            assert hashlib.sha256(original).hexdigest().encode() in prompt
        for text in (b'">keep surrounding code', b'">second asset', b'plain Base64 stays: QUJD',
                     b'"data:image/png;base64,invalid!"', b'data:text/plain,hello',
                     b'DATA:image/svg+xml;charset=utf-8;BASE64,[Base64 payload omitted', b'+<img'):
            assert text in prompt, text
    print("PASS: Base64 assets filtered; metadata, fingerprints, code, diff markers and unrelated text preserved across all providers")


def check_batches(root):
    content = b"".join(f"line {i}: preserve meaningful source behavior and content\n".encode() for i in range(1200))
    repo = staged_repo(root / "large", {"large.txt": content})
    for provider in ("codex", "claude", "gemini"):
        harness = Harness(root / f"batches-{provider}", provider)
        result = harness.generate(repo, verbose=provider == "claude")
        prompts, active, peak = harness.calls()
        assert len(prompts) > 2 and peak == 1 and active == 0
        assert all(b"Summarize this portion" in prompt for prompt in prompts[:-1])
        assert b"Generate one git commit message from summaries" in prompts[-1]
        assert all(len(prompt) <= 20000 for prompt in prompts)
        assert b"sequential batches" in result.stdout
        for verbose in (False, True):
            failed = Harness(root / f"failed-{provider}-{verbose}", provider)
            failed.generate(repo, failure=True, verbose=verbose)
            assert len(failed.calls()[0]) == 1, "Failure dispatched additional calls"
    print("PASS: sequential batches and final synthesis; first failure stops generation in quiet/verbose modes across all providers")
    return repo


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def check_cancel(root, repo):
    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        harness = Harness(root / f"cancel-{signum}")
        before = snapshot(repo)
        process = subprocess.Popen(harness.command(repo), env=dict(harness.env, FAKE_BLOCK="1"),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        pids = []
        try:
            deadline = time.monotonic() + 15
            while not (harness.root / "pids").exists() and time.monotonic() < deadline:
                assert process.poll() is None, process.communicate()
                time.sleep(0.02)
            pids = json.loads((harness.root / "pids").read_text())
            process.send_signal(signum)
            process.communicate(timeout=10)
            assert process.returncode == 128 + signum, process.returncode
            deadline = time.monotonic() + 5
            while any(alive(pid) for pid in pids) and time.monotonic() < deadline:
                time.sleep(0.02)
            assert not any(alive(pid) for pid in pids), f"Provider descendants survived: {pids}"
            assert len(harness.calls()[0]) == 1
            assert snapshot(repo) == before
            assert not any(path.is_dir() for path in harness.root.glob("quill.*")), "Cancellation left temporary files"
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=10)
            for pid in pids:
                if alive(pid):
                    os.kill(pid, signal.SIGKILL)
    print("PASS: INT/TERM/HUP stop dispatch, terminate provider and resistant descendant, and clean temporary files")


def check_staged(root, repo):
    harness = Harness(root / "offending", budget=160000)
    result = harness.generate(repo)
    prompts, active, peak = harness.calls()
    assert prompts and peak == 1 and active == 0
    assert all(len(prompt) <= 160000 for prompt in prompts)
    assert any(b"Base64 payload omitted" in prompt for prompt in prompts)
    raw_bytes = len(git(repo, "diff", "--cached", "--no-ext-diff"))
    context_bytes = sum(len(prompt) for prompt in prompts)
    print(f"PASS: offending staged diff {raw_bytes:,} bytes -> {context_bytes:,} total prompt bytes; {len(prompts)} fake calls; peak concurrency {peak}; Git state unchanged")
    print(result.stdout.decode().strip())


def check_terminal_ui(root, repo):
    timestamp = r"\[\d{2}/\d{2}/\d{4} (?:[1-9]|1[012]):[0-5]\d:[0-5]\d (?:AM|PM)\]:"
    ansi = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
    for mode in ("color", "no-color", "dumb"):
        harness = Harness(root / f"terminal-{mode}")
        env = dict(harness.env, TERM="dumb" if mode == "dumb" else "xterm-256color",
                   FAKE_DELAY="0.18")  # Longer than the existing 0.12s animation frame.
        env.pop("NO_COLOR", None)
        if mode == "no-color":
            env["NO_COLOR"] = "1"
        before = snapshot(repo)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        started = time.monotonic()
        process = subprocess.Popen(harness.command(repo), env=env, stdin=subprocess.DEVNULL,
                                   stdout=slave, stderr=slave)
        os.close(slave)
        output = bytearray()
        try:
            deadline = started + 30
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
                elif process.poll() is not None:
                    break
            process.wait(timeout=5)
            elapsed = time.monotonic() - started
            text = output.decode()
            plain = ansi.sub("", text)
            assert process.returncode == 0, plain
            assert snapshot(repo) == before
            assert re.search(timestamp + r" Generating commit message with Codex", plain)
            assert re.search(timestamp + r" ✓ Summary 1/\d+ · \d+\.\ds", plain)
            total = re.search(timestamp + r" ✓ Generated commit message with Codex · (\d+\.\d)s total", plain)
            assert total, plain
            assert 0 < float(total[1]) <= elapsed + 0.05  # Display rounds to tenths.
            assert "Describe the complete change\r\n\r\nPreserve behavior and update assets." in plain
            assert harness.calls()[2] == 1
            assert bool(re.search(r"\x1b\[\d+m", text)) == (mode == "color")
            if mode == "dumb":
                assert "\x1b" not in text
            else:
                assert "✦ quillmit" in plain
                assert re.search(r"Summary \d+/\d+ \[[= >-]+\] \d+/\d+ · \d+\.\ds elapsed", plain), plain
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            os.close(master)
    print("PASS: real terminal rendering, timestamp format, stage/total durations, loading animation, NO_COLOR and TERM=dumb")


def check_action_ui(root):
    repo = staged_repo(root / "actions", {"small.txt": b"meaningful change\n"})
    for scenario in ("success", "commit-failed", "push-failed"):
        harness = Harness(root / f"actions-{scenario}")
        real_git = shutil.which("git")
        wrapper = harness.bin / "git"
        wrapper.write_text(f"#!{sys.executable}\n" + r'''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
command = args[2] if args[:1] == ["-C"] else args[0]
root = Path(os.environ["FAKE_STATE"])
if command not in ("commit", "push"):
    os.execv(os.environ["REAL_GIT"], [os.environ["REAL_GIT"], *args])
with (root / "git-actions").open("a") as log:
    log.write(command + "\n")
if command == "commit":
    message = Path(args[args.index("-F") + 1]).read_text()
    (root / "committed-message").write_text(message)
if os.environ["FAKE_ACTION"] == command + "-failed":
    print("Fake action failure", file=sys.stderr)
    sys.exit(7)
print("Fake " + command + " completed; Git state untouched")
''')
        wrapper.chmod(0o755)
        before = snapshot(repo)
        command = harness.command(repo)
        command.remove("--quit")
        command[1:1] = ["--commit", "--push"]
        result = subprocess.run(command, env=dict(harness.env, REAL_GIT=real_git,
                                FAKE_ACTION=scenario), capture_output=True, timeout=15)
        text = result.stdout.decode() + result.stderr.decode()
        assert (result.returncode == 0) == (scenario == "success"), text
        assert snapshot(repo) == before
        assert "\x1b" not in text
        assert (harness.root / "committed-message").read_text() == (
            "Describe the complete change\n\nPreserve behavior and update assets.\n"
        ), "Display formatting changed the commit message"
        actions = (harness.root / "git-actions").read_text().splitlines()
        assert actions == (["commit"] if scenario == "commit-failed" else ["commit", "push"])
        for label in (
            ["Commit failed"] if scenario == "commit-failed" else
            ["Commit created", "Push failed. Commit remains local."] if scenario == "push-failed" else
            ["Commit created", "Push completed"]
        ):
            assert re.search(re.escape(label) + r" · \d+\.\ds", text), text
    print("PASS: commit/push timing and failure messages; display formatting never enters commit text; Git actions are fake")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged-repo", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="quill-context-check-") as temporary:
        root = Path(temporary).resolve()
        check_payloads(root)
        repo = check_batches(root)
        check_cancel(root, repo)
        check_terminal_ui(root, repo)
        check_action_ui(root)
        if args.staged_repo:
            check_staged(root, args.staged_repo.resolve())
