"""Opt-in live AI smoke tests. No GitHub writes; temporary local remotes only.

--checkout also creates and removes one AI-named worktree in this checkout.
The checkout's .gitignore update remains visible. Only smoke-owned branches are removed.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parent


def run(args, cwd, ok=True, timeout=30):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, capture_output=True,
                            text=True, timeout=timeout)
    if (result.returncode == 0) != ok:
        raise AssertionError(f"Unexpected exit {result.returncode}: {args}\n{result.stdout}{result.stderr}")
    return result.stdout.strip() + ("\n" + result.stderr.strip() if result.stderr.strip() else "")


def git(repo, *args):
    return run(["git", *args], repo).split("\n", 1)[0]


def inventory(repo):
    output = subprocess.check_output(["git", "worktree", "list", "--porcelain", "-z"], cwd=repo)
    records, record = {}, {}
    for value in output.decode().split("\0"):
        if value.startswith("worktree "):
            if record: records[record["path"]] = record
            record = {"path": str(Path(value[9:]).resolve())}
        elif value.startswith("branch "):
            record["branch"] = value[7:]
    if record: records[record["path"]] = record
    return records


def quill(repo, *args, ok=True):
    # Real provider executable, real config, and the actual source command.
    return run([ROOT / "quill", "worktree", *args, "--repo", repo,
                "--config", ROOT / "quill.config"], ROOT, ok=ok, timeout=240)


def create_live(repo, from_head=True):
    before = inventory(repo)
    branches = set(subprocess.check_output(["git", "for-each-ref", "--format=%(refname)", "refs/heads"], cwd=repo).decode().splitlines())
    nonce = uuid.uuid4().hex[:10]
    intent = ("Create a disposable smoke-test worktree for checking Quillmit safety. "
              f"Use a new branch in the codex/smoke-{nonce}- prefix. "
              "There is no existing worktree for this test. Choose a short descriptive suffix.")
    print("Calling the configured AI provider for a worktree proposal...", flush=True)
    started = time.time()
    base_args = ["--from", "HEAD"] if from_head else []
    output = quill(repo, "create", intent, *base_args, "--no-preview")
    log_dirs = [Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "quill",
                Path(tempfile.gettempdir()) / "quill"]
    for directory in log_dirs:
        log = directory / "last.log"
        if log.is_file() and log.stat().st_mtime >= started:
            models = [line for line in log.read_text(errors="replace").splitlines() if line.startswith("model: ")]
            if models: print("Observed provider " + "; ".join(dict.fromkeys(models)), flush=True)
            break
    added = {key: value for key, value in inventory(repo).items() if key not in before}
    assert len(added) == 1, "Expected exactly one new worktree"
    record = next(iter(added.values()))
    target = Path(record["path"])
    branch_ref = record.get("branch", "")
    assert branch_ref.startswith("refs/heads/") and branch_ref not in branches
    assert target.is_relative_to(repo.resolve() / ".worktrees"), "Unexpected destination"
    assert git(target, "rev-parse", "HEAD") == git(repo, "rev-parse", "HEAD")
    assert Path(git(target, "rev-parse", "--path-format=absolute", "--git-common-dir")) == Path(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir"))
    print(output, flush=True)
    return target, branch_ref.removeprefix("refs/heads/"), git(target, "rev-parse", "HEAD")


def check_block(repo, target, expected):
    output = quill(repo, "remove", str(target), ok=False)
    assert expected in output, output
    assert target.exists(), "A blocked removal deleted the worktree"


def safety_cases(repo, target, branch):
    quill(repo, "list")
    check_block(repo, repo, "main worktree")
    for kind in ("unstaged", "staged", "untracked", "ignored"):
        if kind in ("unstaged", "staged"):
            (target / "file").write_text("pending")
            if kind == "staged": git(target, "add", "file")
        elif kind == "untracked": (target / "new-file").write_text("new")
        else:
            (repo / ".git/info/exclude").write_text("secret.env\n")
            (target / "secret.env").write_text("synthetic smoke secret")
        check_block(repo, target, "ignored files" if kind == "ignored" else "changes exist")
        git(target, "restore", "--staged", "--worktree", "file")
        (target / "new-file").unlink(missing_ok=True)
        (target / "secret.env").unlink(missing_ok=True)
    git(repo, "worktree", "lock", str(target))
    check_block(repo, target, "locked")
    git(repo, "worktree", "unlock", str(target))
    for name in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"):
        marker = Path(git(target, "rev-parse", "--path-format=absolute", "--git-path", name))
        if name.startswith("rebase"): marker.mkdir()
        else: marker.write_text(git(target, "rev-parse", "HEAD") + "\n")
        check_block(repo, target, "operation is in progress")
        if marker.is_dir(): marker.rmdir()
        else: marker.unlink()
    # Local-only removal retains branch history, including an unpushed local commit.
    (target / "file").write_text("local committed work")
    git(target, "commit", "-qam", "Live smoke local change")
    local_head = git(target, "rev-parse", "HEAD")
    quill(repo, "remove", str(target))
    assert not target.exists() and git(repo, "rev-parse", branch) == local_head
    git(repo, "worktree", "add", str(target), branch)
    with tempfile.TemporaryDirectory(prefix="quill-smoke-remote-") as remote_dir:
        remote = Path(remote_dir) / "remote.git"
        git(repo, "init", "-q", "--bare", str(remote))
        git(repo, "remote", "add", "smoke", str(remote))
        check_block(repo, target, "no remote upstream")
        git(target, "push", "-qu", "smoke", branch)
        (target / "file").write_text("unpushed local work")
        git(target, "commit", "-qam", "Live smoke unpushed change")
        check_block(repo, target, "unpushed commits")
        git(target, "push", "-q")
        git(repo, "remote", "set-url", "smoke", str(remote.parent / "unavailable"))
        check_block(repo, target, "could not be verified")
        git(repo, "remote", "set-url", "smoke", str(remote))
        head = git(target, "rev-parse", "HEAD")
        quill(repo, "remove", str(target))
        assert not target.exists() and git(repo, "rev-parse", branch) == head
    print("PASS: live AI creation, linking, list, local removal, dirty/ignored/locked/operation guards, upstream, push and fetch guards", flush=True)


def isolated():
    with tempfile.TemporaryDirectory(prefix="quill-live-") as directory:
        repo = Path(directory).resolve() / "repo"
        repo.mkdir()
        git(repo, "init", "-q", "-b", "main")
        git(repo, "config", "user.name", "Quillmit Smoke")
        git(repo, "config", "user.email", "smoke@example.invalid")
        (repo / "file").write_text("initial\n")
        git(repo, "add", "file")
        git(repo, "commit", "-qm", "Initial smoke fixture")
        remote = Path(directory) / "default.git"
        git(repo, "init", "-q", "--bare", str(remote))
        git(remote, "symbolic-ref", "HEAD", "refs/heads/main")
        git(repo, "remote", "add", "origin", str(remote))
        git(repo, "push", "-qu", "origin", "main")
        target, branch, _ = create_live(repo, from_head=False)
        git(repo, "remote", "remove", "origin")
        safety_cases(repo, target, branch)
        # The whole temporary repository is smoke-owned, including its branch history.


def checkout():
    repo = ROOT
    before = inventory(repo)
    main = Path(next(iter(before)))
    assert main == repo, "Run checkout smoke only from the main checkout"
    target, branch, original_head = create_live(repo)
    try:
        output = quill(repo, "list")
        assert str(target) in output
        check_block(repo, repo, "main worktree")
        if git(repo, "remote"):
            check_block(repo, target, "no remote upstream")
        print("PASS: live creation and removal guards in the project checkout", flush=True)
    finally:
        # Cleanup is limited to the exact branch/worktree created above. No force.
        assert git(target, "rev-parse", "HEAD") == original_head, "Smoke branch changed; preserve it for inspection"
        assert not git(target, "status", "--porcelain", "--untracked-files=all")
        assert not git(target, "ls-files", "--others", "--ignored", "--exclude-standard")
        assert git(repo, "rev-parse", branch) == original_head
        git(repo, "worktree", "remove", str(target))
        git(repo, "branch", "-d", branch)
        print("Removed the smoke worktree and branch. The .gitignore rule remains.", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", action="store_true", help="also smoke-test this checkout; leaves its .gitignore rule")
    args = parser.parse_args()
    isolated()
    if args.checkout: checkout()
