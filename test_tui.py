"""Commit and PR tests with fake UI and providers, using a real pseudo-terminal."""
import json
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


class PullRequestFlow(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="quill-tui-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "repo"
        self.package = self.root / "package"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.package / ".deps/fzf").mkdir(parents=True)
        shutil.copy2(ROOT / "quill", self.package / "quill")
        (self.package / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/worktree", self.package / "scripts/worktree")
        shutil.copy2(ROOT / "scripts/filter-diff.py", self.package / "scripts/filter-diff.py")
        shutil.copy2(ROOT / "scripts/run-provider.py", self.package / "scripts/run-provider.py")
        shutil.copy2(ROOT / "scripts/parse-pr-draft.py", self.package / "scripts/parse-pr-draft.py")
        (self.package / "quill.config").write_text("CODEX_FALLBACK_MODEL=\n")
        self.git("init", "-q", "-b", "master", str(self.repo), cwd=self.root)
        self.git("config", "user.name", "TUI Test")
        self.git("config", "user.email", "test@example.com")
        (self.repo / "file").write_text("base\n")
        self.git("add", "file")
        self.git("commit", "-qm", "Initial")
        self.git("branch", "stable")
        self.git("init", "--bare", "-q", str(self.root / "remote.git"))
        self.git("remote", "add", "origin", str(self.root / "remote.git"))
        self.git("push", "-q", "origin", "master", "stable")
        self.git("switch", "-qc", "feature")
        (self.repo / "file").write_text("feature\n")
        self.git("commit", "-qam", "Feature")
        self.script(self.bin / "codex", r'''
import re
prompt = sys.stdin.read()
base = re.search(r"Base branch: (.*)", prompt).group(1)
with (root / "generated").open("a") as f: f.write(base + "\n")
Path(sys.argv[sys.argv.index("-o") + 1]).write_text("Title for " + base + "\n\nBody for " + base + "\n")
''')
        self.script(self.bin / "gh", r'''
if sys.argv[1:3] == ["repo", "view"]: print("test/repo")
elif sys.argv[1:3] == ["pr", "create"]:
    body = Path(sys.argv[sys.argv.index("--body-file") + 1]).read_text()
    (root / "created").write_text(json.dumps({"args": sys.argv[1:], "body": body, "cwd": os.getcwd()}))
else: sys.exit(1)
''')
        self.script(self.package / ".deps/fzf/fzf", r'''
assert not os.environ.get("FZF_DEFAULT_OPTS")
assert not os.environ.get("FZF_DEFAULT_OPTS_FILE")
assert not (root / "created").exists(), "PR created before approval"
options = sys.stdin.read().splitlines()
actions = (root / "actions").read_text().splitlines()
action = actions.pop(0)
(root / "actions").write_text("\n".join(actions))
if "--no-input" in sys.argv:
    with (root / "previews").open("a") as f:
        f.write(Path(os.environ["QUILL_PR_PREVIEW"]).read_text())
    if action == "approve": print("\nCreate pull request")
    elif action == "back": print("esc\nCreate pull request")
    elif action == "cancel": print("ctrl-c\nCreate pull request")
    else: sys.exit(2)
else:
    if action == "cancel": sys.exit(130)
    assert action in options, action
    print(action)
''')
        self.script(self.bin / "fzf", "raise RuntimeError('Global fzf must not be used')")

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def script(self, path, code):
        path.write_text("#!" + sys.executable + "\nimport os, sys, json\nfrom pathlib import Path\n"
                        "root = Path(os.environ['FLOW_ROOT'])\n" + code)
        path.chmod(0o755)

    def run_flow(self, actions, *args, expected_success=True, workflow="pr", choices=()):
        (self.root / "actions").write_text("\n".join(actions))
        env = dict(os.environ, FLOW_ROOT=str(self.root),
                   PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                   XDG_CACHE_HOME=str(self.root / "cache"),
                   FZF_DEFAULT_OPTS="--filter=master --bind=start:accept",
                   FZF_DEFAULT_OPTS_FILE="/not/a/real/file")
        master, slave = pty.openpty()
        process = None
        try:
            command = [str(self.package / "quill"), *([workflow] if workflow else []), *args, str(self.repo)]
            process = subprocess.Popen(command,
                                       cwd=self.root, env=env, stdin=slave, stdout=slave, stderr=slave)
            os.close(slave)
            slave = None
            output = bytearray()
            pending_choices = iter(choices)
            prompt = b"[c]ommit, [e]dit, co[p]y, [r]egenerate, [q]uit: "
            answered = 0
            deadline = time.monotonic() + 20
            while True:
                if time.monotonic() > deadline:
                    self.fail("Workflow timed out: " + output.decode(errors="replace"))
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    if not data:
                        break
                    output.extend(data)
                    if output.count(prompt) > answered:
                        choice = next(pending_choices, None)
                        if choice is not None:
                            os.write(master, choice.encode() + b"\n")
                            answered += 1
                elif process.poll() is not None:
                    break
            code = process.wait(timeout=5)
            self.assertEqual(code == 0, expected_success, output.decode(errors="replace"))
            return output.decode(errors="replace")
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            if slave is not None:
                os.close(slave)

    def test_back_regenerates_for_new_target_before_creation(self):
        self.run_flow(["master", "back", "stable", "approve"])
        self.assertEqual((self.root / "generated").read_text().splitlines(), ["origin/master", "origin/stable"])
        result = json.loads((self.root / "created").read_text())
        self.assertEqual(result["args"][result["args"].index("--base") + 1], "stable")
        self.assertEqual(result["body"], "Body for origin/stable\n")
        self.assertEqual(result["cwd"], str(self.repo))
        previews = (self.root / "previews").read_text()
        self.assertIn("Title for origin/master", previews)
        self.assertIn("Title for origin/stable", previews)

    def test_closing_lines_and_guidance_survive_regeneration(self):
        self.script(self.bin / "codex", r'''
prompt = sys.stdin.read()
assert prompt.index("Requirements:") < prompt.index("Additional guidance from the user")
assert "Discuss rollout" in prompt
base = re.search(r"Base branch: (.*)", prompt).group(1)
Path(sys.argv[sys.argv.index("-o") + 1]).write_text("Title\n\nBody for " + base + "\n")
'''.replace("prompt =", "import re\nprompt =", 1))
        self.run_flow(["master", "back", "stable", "approve"],
                      "--closes", "3,4", "--prompt", "Discuss rollout")
        previews = (self.root / "previews").read_text()
        self.assertEqual(previews.count("Closes #3\nCloses #4\n"), 2)
        self.assertEqual(json.loads((self.root / "created").read_text())["body"],
                         "Body for origin/stable\n\nCloses #3\nCloses #4\n")

    def test_prepare_in_linked_worktree_without_terminal_or_fzf(self):
        (self.package / ".deps/fzf/fzf").unlink()
        linked = self.root / "linked"
        self.git("worktree", "add", "-qb", "linked-feature", str(linked))
        result = subprocess.run(
            [str(self.package / "quill"), "pr", "--prepare", "--base", "master",
             "--closes", "3,4", str(linked)], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=dict(os.environ, FLOW_ROOT=str(self.root),
                     PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                     XDG_CACHE_HOME=str(self.root / "cache")))
        self.assertEqual(result.returncode, 0, result.stderr)
        draft = Path(result.stdout.decode().splitlines()[-1])
        expected = self.git("rev-parse", "--path-format=absolute", "--git-path",
                            "QUILL_PR_EDITMSG", cwd=linked).stdout.decode().strip()
        self.assertEqual(str(draft), expected)
        self.assertEqual(draft.read_text(), "From: linked-feature\nInto: test/repo:master\n\n"
                         "Title for origin/master\n\nBody for origin/master\n\nCloses #3\nCloses #4\n")
        self.assertFalse((self.repo / ".git/QUILL_PR_EDITMSG").exists())
        self.assertFalse((self.root / "created").exists())
        self.assertFalse((self.root / "previews").exists())

    def test_large_pr_guidance_reaches_commit_digest(self):
        (self.repo / "large").write_text("".join(f"Change {i} with enough context to batch\n" for i in range(1000)))
        self.git("add", "large")
        self.git("commit", "-qm", "Large change")
        (self.package / "quill.config").write_text("CODEX_MAX_PROMPT_BYTES=20000\nCODEX_FALLBACK_MODEL=\n")
        self.script(self.bin / "codex", r'''
prompt = sys.stdin.read()
assert "from the commit history below" in prompt and "Summarize this portion" not in prompt
assert prompt.index("Requirements:") < prompt.index("Additional guidance from the user")
assert "Discuss rollout" in prompt
(root / "synthesized").write_text(prompt)
message = "Combined title\n\nCombined body\n"
Path(sys.argv[sys.argv.index("-o") + 1]).write_text(message)
''')
        self.run_flow([], "--base", "master", "--prepare", "--prompt", "Discuss rollout", "--closes", "3",
                      "--config", str(self.package / "quill.config"))
        self.assertTrue((self.root / "synthesized").exists())
        self.assertFalse((self.root / "created").exists())
        self.assertTrue((self.repo / ".git/QUILL_PR_EDITMSG").read_text().endswith("Combined body\n\nCloses #3\n"))

    def test_branch_cancel_does_not_generate_or_create(self):
        self.run_flow(["cancel"])
        self.assertFalse((self.root / "generated").exists())
        self.assertFalse((self.root / "created").exists())

    def test_preview_cancel_does_not_create(self):
        self.run_flow(["master", "cancel"])
        self.assertFalse((self.root / "created").exists())

    def test_explicit_base_still_requires_approval_and_supports_back(self):
        self.run_flow(["back", "stable", "approve"], "--remote", "origin", "--base", "master")
        self.assertEqual((self.root / "generated").read_text().splitlines(), ["origin/master", "origin/stable"])

    def test_scripted_mode_needs_no_fzf(self):
        (self.package / ".deps/fzf/fzf").unlink()
        self.run_flow([], "--remote", "origin", "--base", "stable", "--no-preview")
        self.assertTrue((self.root / "created").exists())
        self.assertFalse((self.root / "previews").exists())

    def test_provider_failure_never_creates_pr(self):
        for behavior in ("sys.exit(1)", "Path(sys.argv[sys.argv.index('-o') + 1]).write_text('')"):
            with self.subTest(behavior=behavior):
                self.script(self.bin / "codex", "sys.stdin.read()\n" + behavior)
                before = self.git("rev-parse", "HEAD").stdout
                self.run_flow([], "--base", "master", "--no-preview", expected_success=False)
                self.assertFalse((self.root / "created").exists())
                self.assertEqual(self.git("rev-parse", "HEAD").stdout, before)

    def test_pr_content_preserves_markdown_unicode_and_shell_literals(self):
        title = "Handle café and $HOME with `literal` text"
        body = "## Changes\n\n- Preserve 'quotes' and \"double quotes\"\n- $(touch injected)\n\n```sh\necho $HOME\n```\n"
        content = "\n\n" + title + "\n\n" + body
        self.script(self.bin / "codex", "sys.stdin.read()\nPath(sys.argv[sys.argv.index('-o') + 1]).write_text(" + repr(content) + ")")
        self.run_flow(["master", "approve"])
        result = json.loads((self.root / "created").read_text())
        self.assertEqual(result["args"][result["args"].index("--title") + 1], title)
        self.assertEqual(result["body"], body)
        self.assertFalse((self.root / "injected").exists())
        self.assertFalse((self.repo / "injected").exists())

    def test_outer_response_fence_is_removed(self):
        self.script(self.bin / "codex", "sys.stdin.read()\nPath(sys.argv[sys.argv.index('-o') + 1]).write_text('```markdown\\nTitle\\n\\nBody\\n```\\n')")
        self.run_flow([], "--base", "master", "--no-preview")
        result = json.loads((self.root / "created").read_text())
        self.assertEqual(result["args"][result["args"].index("--title") + 1], "Title")
        self.assertEqual(result["body"].strip(), "Body")


class CommitFlow(unittest.TestCase):
    def setUp(self):
        self.fixture = PullRequestFlow()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.script(self.fixture.bin / "codex", r'''
(root / "generated").write_text(sys.stdin.read())
Path(sys.argv[sys.argv.index("-o") + 1]).write_text("Generated commit title\n\nGenerated body\n")
''')
        (self.fixture.repo / "file").write_text("pending change\n")

    def run_commit(self, *args, choices=(), expected_success=True):
        return self.fixture.run_flow([], *args, workflow="", choices=choices,
                                     expected_success=expected_success)

    def test_default_prepares_and_prompts_for_action(self):
        output = self.run_commit(choices=["q"])
        self.assertIn("Prepared commit message", output)
        self.assertIn("[c]ommit, [e]dit, co[p]y, [r]egenerate, [q]uit", output)
        self.assertIn("Quit without committing", output)
        self.assertEqual((self.fixture.repo / ".git/COMMIT_EDITMSG").read_text(),
                         "Generated commit title\n\nGenerated body\n")
        self.assertTrue(self.fixture.git("status", "--short").stdout)

    def test_interactive_push_pushes_only_after_commit_choice(self):
        self.fixture.git("add", "file")
        self.fixture.git("push", "-qu", "origin", "feature")
        self.run_commit("--push", choices=["c"])
        remote_title = self.fixture.git("--git-dir", str(self.fixture.root / "remote.git"),
                                        "log", "-1", "--pretty=%s", "feature").stdout.decode().strip()
        self.assertEqual(remote_title, "Generated commit title")

    def test_interactive_push_does_not_push_after_quit_choice(self):
        self.fixture.git("add", "file")
        self.fixture.git("push", "-qu", "origin", "feature")
        before = self.fixture.git("rev-parse", "HEAD").stdout
        self.run_commit("--push", choices=["q"])
        self.assertEqual(self.fixture.git("--git-dir", str(self.fixture.root / "remote.git"),
                                         "rev-parse", "feature").stdout, before)
        self.assertTrue(self.fixture.git("diff", "--cached").stdout)

    def test_unstaged_commit_refuses_before_generation_at_terminal(self):
        output = self.run_commit("-c", expected_success=False)
        self.assertIn("No staged changes to commit.", output)
        self.assertIn("Stage files with git add <file> and run quill again.", output)
        self.assertFalse((self.fixture.root / "generated").exists())


if __name__ == "__main__":
    unittest.main()
