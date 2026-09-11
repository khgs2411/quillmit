"""Worktree contracts: real Git, private fake UI, and fake AI; no network services."""
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent


class WorktreeContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="quill-worktree-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "project with spaces"
        self.package = self.root / "package"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.package / "scripts").mkdir(parents=True)
        (self.package / ".deps/fzf").mkdir(parents=True)
        shutil.copy2(ROOT / "quill", self.package / "quill")
        shutil.copy2(ROOT / "scripts/worktree", self.package / "scripts/worktree")
        (self.package / "quill.config").write_text("CODEX_FALLBACK_MODEL=\n")
        self.git("init", "-q", "-b", "main", str(self.repo), cwd=self.root)
        self.git("config", "user.name", "Worktree Test")
        self.git("config", "user.email", "test@example.com")
        (self.repo / "file").write_text("initial\n")
        self.git("add", "file")
        self.git("commit", "-qm", "Initial")
        self.script(self.bin / "codex", r'''
prompt = sys.stdin.read()
(root / 'prompt').write_text(prompt)
if (root / 'fail-provider').exists(): sys.exit(1)
Path(sys.argv[sys.argv.index('-o') + 1]).write_text((root / 'proposal').read_text())
''')
        (self.root / "proposal").write_text("Branch: fix/retries\nExisting: -\nReason: A focused branch for retry behavior.\n")
        self.script(self.package / ".deps/fzf/fzf", r'''
assert not os.environ.get('FZF_DEFAULT_OPTS')
options = sys.stdin.read().splitlines()
with (root / 'previews').open('a') as f:
    f.write(Path(os.environ['QUILL_WORKTREE_PREVIEW']).read_text())
actions = (root / 'actions').read_text().splitlines()
action = actions.pop(0)
(root / 'actions').write_text('\n'.join(actions))
if action == 'esc': print('esc\n')
else:
    assert action in options
    print('\n' + action)
''')
        self.env = dict(os.environ, WT_TEST_ROOT=str(self.root), PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        XDG_CACHE_HOME=str(self.root / "cache"), FZF_DEFAULT_OPTS="--filter=Create")

    def script(self, path, body):
        path.write_text("#!" + sys.executable + "\nimport os, sys\nfrom pathlib import Path\nroot=Path(os.environ['WT_TEST_ROOT'])\n" + body)
        path.chmod(0o755)

    def git(self, *args, cwd=None):
        return subprocess.check_output(["git", *args], cwd=cwd or self.repo, stderr=subprocess.PIPE).decode().strip()

    def run_quill(self, *args, ok=True, cwd=None):
        result = subprocess.run([str(self.package / "quill"), "worktree", *args], cwd=cwd or self.repo,
                                env=self.env, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def create(self, name="feature", cwd=None):
        self.run_quill("create", "--branch", name, "--from", "HEAD", "--no-preview", cwd=cwd)
        return self.repo / ".worktrees" / name

    def remote(self):
        remote = self.root / "remote.git"
        self.git("init", "-q", "--bare", str(remote))
        self.git("symbolic-ref", "HEAD", "refs/heads/main", cwd=remote)
        self.git("remote", "add", "origin", str(remote))
        self.git("push", "-qu", "origin", "main")
        return remote

    def preview(self, actions, *args, edit=None):
        (self.root / "actions").write_text("\n".join(actions))
        master, slave = pty.openpty()
        process = subprocess.Popen([str(self.package / "quill"), "worktree", "create", *args], cwd=self.repo,
                                   env=self.env, stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = bytearray()
        try:
            deadline = time.monotonic() + 20
            while process.poll() is None:
                self.assertLess(time.monotonic(), deadline, output.decode(errors="replace"))
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError:
                        break
                if edit is not None and b"Task description" in output:
                    os.write(master, (edit + "\n").encode())
                    edit = None
            self.assertEqual(process.wait(timeout=5), 0, output.decode(errors="replace"))
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)

    def test_local_creation_links_to_main_and_preserves_ignore_and_index(self):
        (self.repo / ".gitignore").write_text("cache/")
        index = self.git("write-tree")
        target = self.create("feature/café")
        self.assertEqual((self.repo / ".gitignore").read_text(), "cache/\n/.worktrees/\n")
        self.assertEqual(self.git("write-tree"), index)
        common = self.git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=target)
        self.assertEqual(Path(common), self.repo / ".git")
        self.assertEqual(self.git("branch", "--show-current", cwd=target), "feature/café")
        self.create("second", cwd=target)
        self.assertTrue((self.repo / ".worktrees/second").is_dir())
        self.assertFalse((target / ".worktrees").exists())
        self.assertEqual((self.repo / ".gitignore").read_text().count("/.worktrees/"), 1)

    def test_ai_reads_instructions_and_proposes_branch(self):
        (self.repo / "AGENTS.md").write_text("Branch names use fix/ for defects.\n")
        self.run_quill("create", "pr", "--from", "HEAD", "--no-preview")
        self.assertTrue((self.repo / ".worktrees/fix/retries").is_dir())
        self.assertIn("Branch names use fix/", (self.root / "prompt").read_text())
        self.assertIn("Task: pr", (self.root / "prompt").read_text())

    def test_default_base_is_fetched_remote_head_and_new_branch_has_no_upstream(self):
        remote = self.remote()
        clone = self.root / "other"
        self.git("clone", "-q", str(remote), str(clone))
        self.git("config", "user.name", "Other", cwd=clone)
        self.git("config", "user.email", "other@example.com", cwd=clone)
        (clone / "new").write_text("remote update")
        self.git("add", "new", cwd=clone)
        self.git("commit", "-qm", "Remote update", cwd=clone)
        self.git("push", "-q", cwd=clone)
        self.git("branch", "origin/main")  # A local branch must not shadow the remote ref.
        self.run_quill("create", "--branch", "new-feature", "--no-preview")
        target = self.repo / ".worktrees/new-feature"
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=target), self.git("rev-parse", "HEAD", cwd=clone))
        self.assertEqual(self.git("for-each-ref", "--format=%(upstream)", "refs/heads/new-feature"), "")

    def test_local_repo_requires_explicit_base(self):
        output = self.run_quill("create", "--branch", "feature", "--no-preview", ok=False)
        self.assertIn("--from HEAD", output)
        self.assertFalse((self.repo / ".gitignore").exists())

    def test_invalid_proposals_and_provider_failure_do_not_mutate_repo(self):
        for response in ("", "Branch: ../../escape\nExisting: -\nReason: invalid\n", "Branch: safe\nExisting: invented\nReason: invalid\n"):
            with self.subTest(response=response):
                (self.root / "proposal").write_text(response)
                self.run_quill("create", "some task", "--from", "HEAD", "--no-preview", ok=False)
                self.assertFalse((self.repo / ".worktrees").exists())
                self.assertFalse((self.repo / ".gitignore").exists())
        (self.root / "fail-provider").touch()
        self.run_quill("create", "some task", "--from", "HEAD", "--no-preview", ok=False)
        self.assertFalse((self.repo / ".gitignore").exists())

    def test_destination_and_ignore_symlinks_are_refused(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.repo / ".worktrees").symlink_to(outside, target_is_directory=True)
        self.run_quill("create", "--branch", "one", "--from", "HEAD", "--no-preview", ok=False)
        self.assertEqual(list(outside.iterdir()), [])
        (self.repo / ".worktrees").unlink()
        (outside / "ignore").write_text("keep")
        (self.repo / ".gitignore").symlink_to(outside / "ignore")
        self.run_quill("create", "--branch", "one", "--from", "HEAD", "--no-preview", ok=False)
        self.assertEqual((outside / "ignore").read_text(), "keep")

    def test_existing_branch_and_destination_are_preserved(self):
        target = self.create()
        head = self.git("rev-parse", "feature")
        self.run_quill("create", "--branch", "feature", "--from", "HEAD", "--no-preview", ok=False)
        self.assertEqual(self.git("rev-parse", "feature"), head)
        self.assertTrue(target.is_dir())
        occupied = self.repo / ".worktrees/occupied"
        occupied.mkdir()
        (occupied / "keep").write_text("keep")
        self.run_quill("create", "--branch", "occupied", "--from", "HEAD", "--no-preview", ok=False)
        self.assertEqual((occupied / "keep").read_text(), "keep")

    def test_cancel_and_existing_suggestion_do_not_create(self):
        self.preview(["Cancel"], "some task", "--from", "HEAD")
        self.assertFalse((self.repo / ".worktrees").exists())
        existing = self.create("existing")
        (self.root / "proposal").write_text("Branch: new-task\nExisting: existing\nReason: Related task.\n")
        self.preview(["Use existing worktree"], "some task", "--from", "HEAD")
        self.assertTrue(existing.is_dir())
        self.assertFalse((self.repo / ".worktrees/new-task").exists())

    def test_preview_edit_and_approval(self):
        self.preview(["esc", "Create worktree"], "first task", "--from", "HEAD", edit="revised task")
        self.assertTrue((self.repo / ".worktrees/fix/retries").is_dir())
        self.assertIn("Task: revised task", (self.root / "prompt").read_text())
        self.assertIn("Path:", (self.root / "previews").read_text())

    def test_local_removal_preserves_committed_branch(self):
        target = self.create()
        (target / "file").write_text("local work")
        self.git("commit", "-qam", "Local work", cwd=target)
        head = self.git("rev-parse", "HEAD", cwd=target)
        self.run_quill("remove", str(target), cwd=target)
        self.assertFalse(target.exists())
        self.assertEqual(self.git("rev-parse", "feature"), head)
        self.assertNotIn(str(target), self.git("worktree", "list", "--porcelain"))

    def test_main_unknown_and_detached_removal_are_refused(self):
        self.run_quill("remove", str(self.repo), ok=False)
        self.run_quill("remove", str(self.root), ok=False)
        detached = self.root / "detached"
        self.git("worktree", "add", "-q", "--detach", str(detached))
        self.run_quill("remove", str(detached), ok=False)
        self.assertTrue(detached.exists())

    def test_pending_changes_and_ignored_files_block_removal(self):
        target = self.create()
        for mode in ("unstaged", "staged", "untracked", "ignored"):
            with self.subTest(mode=mode):
                if mode in ("unstaged", "staged"):
                    (target / "file").write_text("changed")
                    if mode == "staged": self.git("add", "file", cwd=target)
                elif mode == "untracked": (target / "untracked").touch()
                else:
                    (self.repo / ".git/info/exclude").write_text("secret.env\n")
                    (target / "secret.env").write_text("private")
                self.run_quill("remove", "feature", ok=False)
                self.assertTrue(target.exists())
                self.git("restore", "--staged", "--worktree", "file", cwd=target)
                for name in ("untracked", "secret.env"):
                    (target / name).unlink(missing_ok=True)

    def test_locked_worktree_is_preserved(self):
        target = self.create()
        self.git("worktree", "lock", str(target))
        self.run_quill("remove", "feature", ok=False)
        self.assertTrue(target.exists())

    def test_remote_removal_requires_upstream_and_pushed_commits(self):
        self.remote()
        target = self.create()
        self.assertIn("upstream", self.run_quill("remove", "feature", ok=False))
        self.git("push", "-qu", "origin", "feature", cwd=target)
        (target / "file").write_text("unpushed")
        self.git("commit", "-qam", "Unpushed", cwd=target)
        self.assertIn("unpushed commits", self.run_quill("remove", "feature", ok=False))
        self.git("push", "-q", cwd=target)
        self.run_quill("remove", "feature")
        self.assertFalse(target.exists())
        self.assertTrue(self.git("rev-parse", "feature"))

    def test_missing_remote_branch_or_fetch_failure_blocks_removal(self):
        remote = self.remote()
        target = self.create()
        self.git("push", "-qu", "origin", "feature", cwd=target)
        self.git("push", "-q", "origin", "--delete", "feature")
        self.run_quill("remove", "feature", ok=False)
        self.assertTrue(target.exists())
        self.git("remote", "set-url", "origin", str(self.root / "unavailable"))
        self.run_quill("remove", "feature", ok=False)
        self.assertTrue(target.exists())

    def test_list_works_without_provider_or_tui(self):
        self.create()
        (self.bin / "codex").unlink()
        (self.package / ".deps/fzf/fzf").unlink()
        output = self.run_quill("list")
        self.assertIn("[main]", output)
        self.assertIn("[linked] feature", output)
        self.assertIn("no remote", output)

    def test_empty_repo_cannot_create_a_worktree(self):
        empty = self.root / "empty"
        self.git("init", "-q", str(empty))
        self.run_quill("create", "--branch", "feature", "--from", "HEAD", "--no-preview", cwd=empty, ok=False)
        self.assertFalse((empty / ".worktrees").exists())

    def test_non_repository_and_invalid_options_are_rejected(self):
        self.run_quill("create", "--branch", "one", "--from", "HEAD", "--no-preview", cwd=self.root, ok=False)
        for args in (("remove", "main", "--no-preview"), ("list", "--branch", "one"), ("create", "--from"), ("create", "--bogus")):
            with self.subTest(args=args):
                self.run_quill(*args, ok=False)
        self.assertFalse((self.repo / ".gitignore").exists())

    def test_tracked_worktree_directory_is_refused(self):
        directory = self.repo / ".worktrees"
        directory.mkdir()
        (directory / "keep").write_text("tracked")
        self.git("add", ".worktrees/keep")
        self.run_quill("create", "--branch", "one", "--from", "HEAD", "--no-preview", ok=False)
        self.assertEqual((directory / "keep").read_text(), "tracked")

    def test_foreign_registered_worktree_is_not_removed(self):
        other = self.root / "other-repo"
        self.git("clone", "-q", str(self.repo), str(other))
        foreign = self.root / "foreign-worktree"
        self.git("worktree", "add", "-q", "-b", "foreign", str(foreign), cwd=other)
        self.run_quill("remove", str(foreign), ok=False)
        self.assertTrue(foreign.exists())

    def test_ignored_contents_are_not_sent_to_provider(self):
        (self.repo / ".git/info/exclude").write_text("secret.env\n")
        (self.repo / "secret.env").write_text("private-token-marker")
        self.run_quill("create", "a task", "--from", "HEAD", "--no-preview")
        self.assertNotIn("private-token-marker", (self.root / "prompt").read_text())

    def test_explicit_name_requires_no_provider(self):
        (self.bin / "codex").unlink()
        # Prove this also works when no host codex can be resolved.
        (self.package / "quill.config").write_text("DEFAULT_PROVIDER=claude\n")
        self.create("explicit")
        self.assertFalse((self.root / "prompt").exists())

    def test_existing_effective_ignore_rule_is_not_duplicated(self):
        original = "cache/\n.worktrees/\n"
        (self.repo / ".gitignore").write_text(original)
        self.create()
        self.assertEqual((self.repo / ".gitignore").read_text(), original)

    def test_overridden_ignore_rule_is_repaired(self):
        (self.repo / ".gitignore").write_text("/.worktrees/\n!/.worktrees/\n")
        self.create()
        self.git("check-ignore", ".worktrees/feature/file")

    def test_changes_during_fetch_block_removal(self):
        self.remote()
        target = self.create()
        self.git("push", "-qu", "origin", "feature", cwd=target)
        real_git = shutil.which("git")
        for mode in ("file", "commit"):
            with self.subTest(mode=mode):
                self.script(self.bin / "git", "import subprocess\nreal=" + repr(real_git) + "\n" +
                    "result=subprocess.run([real, *sys.argv[1:]])\n" +
                    "if 'fetch' in sys.argv and result.returncode == 0:\n" +
                    "    target=Path(" + repr(str(target)) + ")\n" +
                    "    (target/'file').write_text(" + repr(mode) + ")\n" +
                    ("    subprocess.run([real,'-C',str(target),'commit','-qam','Concurrent commit'],check=True)\n" if mode == "commit" else "") +
                    "sys.exit(result.returncode)\n")
                self.run_quill("remove", "feature", ok=False)
                self.assertTrue(target.exists())
                self.assertEqual((target / "file").read_text(), mode)
                (self.bin / "git").unlink()
                if mode == "file": self.git("restore", "file", cwd=target)

    def test_diverged_history_blocks_removal(self):
        remote = self.remote()
        target = self.create()
        self.git("push", "-qu", "origin", "feature", cwd=target)
        other = self.root / "other"
        self.git("clone", "-q", str(remote), str(other))
        self.git("switch", "-q", "feature", cwd=other)
        self.git("config", "user.name", "Remote Test", cwd=other)
        self.git("config", "user.email", "test@example.com", cwd=other)
        (other / "remote-file").write_text("remote")
        self.git("add", "remote-file", cwd=other)
        self.git("commit", "-qm", "Remote commit", cwd=other)
        self.git("push", "-q", cwd=other)
        (target / "file").write_text("local")
        self.git("commit", "-qam", "Local commit", cwd=target)
        self.assertIn("unpushed commits", self.run_quill("remove", "feature", ok=False))
        self.assertTrue(target.exists())

    def test_git_operations_block_removal_even_with_clean_files(self):
        target = self.create()
        for operation in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"):
            with self.subTest(operation=operation):
                marker = Path(self.git("rev-parse", "--path-format=absolute", "--git-path", operation, cwd=target))
                if operation.startswith("rebase"):
                    marker.mkdir()
                else: marker.write_text(self.git("rev-parse", "HEAD", cwd=target) + "\n")
                self.run_quill("remove", "feature", ok=False)
                self.assertTrue(target.exists())
                if marker.is_dir(): marker.rmdir()
                else: marker.unlink()

    def test_git_setup_failure_preserves_existing_work(self):
        real_git = shutil.which("git")
        before = self.git("rev-parse", "HEAD")
        self.script(self.bin / "git", "\nif 'worktree' in sys.argv and 'add' in sys.argv:\n    print('Simulated setup failure',file=sys.stderr)\n    sys.exit(1)\nos.execv(" + repr(real_git) + ", [" + repr(real_git) + ", *sys.argv[1:]])")
        self.run_quill("create", "--branch", "blocked", "--from", "HEAD", "--no-preview", ok=False)
        self.assertEqual(self.git("rev-parse", "HEAD"), before)
        self.assertEqual((self.repo / "file").read_text(), "initial\n")
        self.assertEqual(self.git("for-each-ref", "--format=%(refname)", "refs/heads/blocked"), "")
        self.assertIn("/.worktrees/", (self.repo / ".gitignore").read_text())


if __name__ == "__main__":
    unittest.main()
