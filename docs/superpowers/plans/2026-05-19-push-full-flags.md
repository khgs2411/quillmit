# Push and Full Flags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--push` as a push-after-successful-commit modifier and add `--full` as the exact CLI equivalent of `quill --add --commit --push`.

**Architecture:** Keep Quillmit as one zsh executable with the existing `MODE` flow. Add explicit parser state for push/full intent and argument-order-independent conflict validation, then keep the push side effect inside the existing commit lifecycle after `git commit -F "$MESSAGE_FILE"` succeeds. Extend the shell-only test suite with local bare-remotes and fake provider CLIs; update README usage examples only.

**Tech Stack:** zsh, Git CLI, shell-only tests in `test_quill.sh`, README markdown.

---

## Approved Inputs

- Source issue: [TOP-550](/TOP/issues/TOP-550) asks for a new `--push` flag that runs `git push` and a `--full` flag that runs `quill --add --commit --push`.
- Approved design spec: `docs/superpowers/specs/2026-05-19-push-full-flags-design.md`.
- Design commit: `13f63cb8c3050f352d9ff457455d0f1304bbb5fe`.
- Vesta design audit: [TOP-552](/TOP/issues/TOP-552), verdict `Ready for Development`.
- Vesta planning constraints to carry forward:
  - Bare `quill --push` is accepted as a post-commit modifier, not a standalone clean-repo push shortcut.
  - Argument-order validation must be explicit so `--prepare --full`, `--full --quit`, and `--copy --push` fail consistently regardless of flag order.
  - Push only after a successful local commit.
  - Do not auto-stage except under `--add` or `--full`.
  - Do not add force, tags, upstream, remote, or branch arguments to `git push`.
  - Preserve Git push diagnostics and leave local commits intact after push failure.

## Repository Evidence

- `quill:6-11` owns usage text.
- `quill:14-19` owns top-level parser state: `MODE`, `REPO_INPUT`, `VERBOSE`, `ADD_ALL`, `PROVIDER`, and `CONFIG_FILE`.
- `quill:26-81` is the single argument parser.
- `quill:137-148` preserves the early clean-repo exit and staged-first context selection.
- `quill:323-335` owns commit side effects and is the right place to sequence push after commit.
- `quill:366-390` runs generated message display and non-interactive modes.
- `quill:392-412` runs interactive choices; only `c|commit` should push when `--push` was provided.
- `test_quill.sh:25-107` provides fake provider CLIs and repo helpers.
- `test_quill.sh:249-350` covers commit, staged-only commit, no-staged failure, `--add --commit`, and `--commit` alias behavior.
- `test_quill.sh:404-421` lists tests manually, so every new test must be added to that call list.
- `README.md:92-125` documents staged-first usage and commit behavior.
- Git history commit `581896c` established staged-first generation plus explicit `--add`; preserve that behavior.
- llm-wiki `code-style` guidance consulted: keep the CLI path linear, introduce separate helpers only when they own real behavior, keep side effects visibly sequenced near the lifecycle owner, and test workflow behavior rather than abstraction seams.

## Assumptions

Assumption: push uses Git's configured default remote/upstream with exactly `git -C "$REPO" push` -- chosen because TOP-550 only asks to run `git push` and the approved design excludes remote/branch/upstream arguments; revisit if a future issue requests first-push upstream setup.

Assumption: invalid push/full combinations should fail before provider generation -- chosen because `--prepare`, `--copy`, and `--quit` have no commit side effect to attach push to, and Vesta requested explicit conflict handling; revisit if Quillmit later gains a generalized action pipeline.

Assumption: a local commit that succeeds before push failure remains in the repository -- chosen because rollback would be destructive and outside the approved design; revisit only if product policy changes to require all-or-nothing push semantics.

## File Structure

- Modify `quill`: parser state, usage text, flag validation, push helper, and commit lifecycle sequencing.
- Modify `test_quill.sh`: add local bare-remote helpers and focused tests for `--push`, `--full`, invalid combinations, push failure, interactive push, and README-visible docs.
- Modify `README.md`: document `--commit --push`, `--add --commit --push`, `--full`, interactive `--push`, and push-failure expectations.

No new product files are needed. Do not split `quill`, do not introduce an action pipeline, and do not change provider execution.

### Task 1: Add Failing Parser And README Tests

**Files:**
- Modify: `test_quill.sh:13-23`
- Modify: `test_quill.sh:385-421`
- Test: `test_quill.sh`

- [ ] **Step 1: Add an equality assertion helper**

Insert this helper after `assert_not_contains` at `test_quill.sh:19-23`:

```zsh
assert_equals() {
  local actual="$1"
  local expected="$2"
  [[ "$actual" == "$expected" ]] || fail "expected '$expected' but got '$actual'"
}
```

- [ ] **Step 2: Add invalid-combination and README tests**

Insert these tests before `test_install_links_quill_only` at `test_quill.sh:385`:

```zsh
test_push_rejects_non_commit_modes_before_generation() {
  local repo="$TMP_ROOT/push-invalid-copy"
  make_dirty_repo "$repo"
  local output_file="$TMP_ROOT/push-invalid-copy-output.txt"

  if PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --copy --push "$repo" > "$output_file" 2>&1; then
    fail "expected --copy --push to fail"
  fi

  local output
  output="$(<"$output_file")"
  assert_contains "$output" "--push cannot be combined with --copy"
  assert_not_contains "$output" "Generating commit message"
  assert_not_contains "$output" "Add terminal commit message helper"
}

test_full_rejects_non_commit_modes_regardless_of_order() {
  local repo="$TMP_ROOT/full-invalid-quit"
  make_dirty_repo "$repo"
  local output_file="$TMP_ROOT/full-invalid-quit-output.txt"

  if PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --full --quit "$repo" > "$output_file" 2>&1; then
    fail "expected --full --quit to fail"
  fi

  local output
  output="$(<"$output_file")"
  assert_contains "$output" "--full cannot be combined with --quit"
  assert_not_contains "$output" "Generating commit message"
  assert_not_contains "$output" "Add terminal commit message helper"

  output_file="$TMP_ROOT/full-invalid-prepare-output.txt"
  if PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --prepare --full "$repo" > "$output_file" 2>&1; then
    fail "expected --prepare --full to fail"
  fi

  output="$(<"$output_file")"
  assert_contains "$output" "--full cannot be combined with --prepare"
  assert_not_contains "$output" "Generating commit message"
  assert_not_contains "$output" "Add terminal commit message helper"
}

test_readme_documents_push_and_full_flags() {
  local readme
  readme="$(<"$ROOT/README.md")"

  assert_contains "$readme" "quill --commit --push"
  assert_contains "$readme" "quill --add --commit --push"
  assert_contains "$readme" "quill --full"
  assert_contains "$readme" "Push failures leave the local commit in place."
}
```

- [ ] **Step 3: Add the new tests to the call list**

Update the bottom of `test_quill.sh` so these calls appear before `test_install_links_quill_only`:

```zsh
test_push_rejects_non_commit_modes_before_generation
test_full_rejects_non_commit_modes_regardless_of_order
test_readme_documents_push_and_full_flags
test_install_links_quill_only
```

- [ ] **Step 4: Run the targeted suite and confirm it fails for missing behavior**

Run:

```bash
rtk zsh test_quill.sh
```

Expected: failure from the first new invalid-combination test because `quill` does not yet parse `--push`/`--full` or reject those combinations before generation. The exact first failure may be one of:

```text
FAIL: expected --copy --push to fail
```

or:

```text
FAIL: expected output to contain: --push cannot be combined with --copy
```

### Task 2: Implement Parser State And Conflict Validation

**Files:**
- Modify: `quill:6-81`
- Modify: `quill:83-97`
- Test: `test_quill.sh`

- [ ] **Step 1: Update usage text**

Change the usage line in `quill:8` to include `--push` and `--full`:

```zsh
Usage: quill [--codex|--claude|--gemini|--provider name] [--config file] [--prepare|--commit|--copy|--quit|--add|--push|--full|--verbose] [repo]
```

- [ ] **Step 2: Add parser state**

Replace the state block at `quill:14-19` with:

```zsh
MODE="interactive"
REPO_INPUT=""
VERBOSE=0
ADD_ALL=0
PUSH_AFTER_COMMIT=0
FULL_REQUESTED=0
NON_COMMIT_MODE_FLAGS=""
PROVIDER=""
CONFIG_FILE="$SCRIPT_DIR/quill.config"
```

- [ ] **Step 3: Track non-commit modes inside the parser**

Replace the `--prepare`, `--copy`, and `--quit` parser cases with:

```zsh
    --prepare)
      MODE="prepare"
      NON_COMMIT_MODE_FLAGS="${NON_COMMIT_MODE_FLAGS:+$NON_COMMIT_MODE_FLAGS }--prepare"
      shift
      ;;
```

```zsh
    --copy)
      MODE="copy"
      NON_COMMIT_MODE_FLAGS="${NON_COMMIT_MODE_FLAGS:+$NON_COMMIT_MODE_FLAGS }--copy"
      shift
      ;;
```

```zsh
    --quit)
      MODE="quit"
      NON_COMMIT_MODE_FLAGS="${NON_COMMIT_MODE_FLAGS:+$NON_COMMIT_MODE_FLAGS }--quit"
      shift
      ;;
```

- [ ] **Step 4: Add `--push` and `--full` parser cases**

Insert these cases after the `--add` case:

```zsh
    --push)
      PUSH_AFTER_COMMIT=1
      shift
      ;;
    --full)
      ADD_ALL=1
      MODE="commit"
      PUSH_AFTER_COMMIT=1
      FULL_REQUESTED=1
      shift
      ;;
```

- [ ] **Step 5: Add order-independent validation before config/provider work**

Insert this block immediately after the parser loop and before `if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then`:

```zsh
if [[ "$PUSH_AFTER_COMMIT" -eq 1 && -n "$NON_COMMIT_MODE_FLAGS" ]]; then
  if [[ "$FULL_REQUESTED" -eq 1 ]]; then
    print -u2 -- "--full cannot be combined with $NON_COMMIT_MODE_FLAGS"
  else
    print -u2 -- "--push cannot be combined with $NON_COMMIT_MODE_FLAGS"
  fi
  exit 1
fi
```

This intentionally rejects `--copy --commit --push` as well as `--copy --push`; any non-commit mode flag in a push/full command makes the command ambiguous and should fail.

- [ ] **Step 6: Run the suite and confirm parser tests pass while README still fails**

Run:

```bash
rtk zsh test_quill.sh
```

Expected: the invalid-combination tests pass. The README test still fails with:

```text
FAIL: expected output to contain: quill --commit --push
```

If another existing test fails, stop and fix the parser change before moving on.

### Task 3: Add Push Workflow Tests

**Files:**
- Modify: `test_quill.sh:99-107`
- Modify: `test_quill.sh:385-421`
- Test: `test_quill.sh`

- [ ] **Step 1: Add local remote helpers**

Insert these helpers after `commit_editmsg_path` at `test_quill.sh:105-108`:

```zsh
make_tracking_repo() {
  local repo="$1"
  local remote="$2"
  git init --bare "$remote" >/dev/null
  git init "$repo" >/dev/null
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  print -r -- "base" > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -m "Initial" >/dev/null
  git -C "$repo" branch -M main
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -u origin main >/dev/null
}

remote_subject() {
  local remote="$1"
  git --git-dir "$remote" log -1 --pretty=%s
}
```

- [ ] **Step 2: Add non-interactive push tests**

Insert these tests before `test_push_rejects_non_commit_modes_before_generation`:

```zsh
test_commit_push_commits_staged_changes_and_pushes() {
  local repo="$TMP_ROOT/commit-push"
  local remote="$TMP_ROOT/commit-push-remote.git"
  make_tracking_repo "$repo" "$remote"
  print -r -- "changed" > "$repo/file.txt"
  git -C "$repo" add file.txt

  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --commit --push "$repo" >/dev/null

  assert_equals "$(git -C "$repo" log -1 --pretty=%s)" "Add terminal commit message helper"
  assert_equals "$(remote_subject "$remote")" "Add terminal commit message helper"
  [[ -z "$(git -C "$repo" status --short)" ]] || fail "expected repo to be clean after commit push"
}

test_full_stages_commits_and_pushes_unstaged_changes() {
  local repo="$TMP_ROOT/full-push"
  local remote="$TMP_ROOT/full-push-remote.git"
  make_tracking_repo "$repo" "$remote"
  print -r -- "new file" > "$repo/new.txt"
  local prompt_capture="$TMP_ROOT/full-push-prompt.txt"

  QUILL_STDIN_CAPTURE="$prompt_capture" PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --full "$repo" >/dev/null

  assert_contains "$(<"$prompt_capture")" "Context mode: all changed files"
  assert_contains "$(<"$prompt_capture")" "new.txt"
  assert_equals "$(git -C "$repo" log -1 --pretty=%s)" "Add terminal commit message helper"
  assert_equals "$(remote_subject "$remote")" "Add terminal commit message helper"
  assert_equals "$(git -C "$repo" show --pretty= --name-only HEAD)" "new.txt"
  [[ -z "$(git -C "$repo" status --short)" ]] || fail "expected repo to be clean after full push"
}
```

- [ ] **Step 3: Add push failure and no-staged failure tests**

Insert these tests after the non-interactive push tests:

```zsh
test_push_failure_leaves_local_commit_and_exits_nonzero() {
  local repo="$TMP_ROOT/push-fails"
  local remote="$TMP_ROOT/push-fails-remote.git"
  make_tracking_repo "$repo" "$remote"
  print -r -- "changed" > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" remote set-url origin "$TMP_ROOT/missing-remote.git"
  local output_file="$TMP_ROOT/push-fails-output.txt"

  if PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --commit --push "$repo" > "$output_file" 2>&1; then
    fail "expected push failure to exit nonzero"
  fi

  local output
  output="$(<"$output_file")"
  assert_contains "$output" "Push failed. Commit remains local."
  assert_equals "$(git -C "$repo" log -1 --pretty=%s)" "Add terminal commit message helper"
  assert_equals "$(remote_subject "$remote")" "Initial"
}

test_push_does_not_run_when_commit_mode_has_no_staged_changes() {
  local repo="$TMP_ROOT/push-no-staged"
  local remote="$TMP_ROOT/push-no-staged-remote.git"
  make_tracking_repo "$repo" "$remote"
  print -r -- "unstaged" > "$repo/file.txt"
  git -C "$repo" remote set-url origin "$TMP_ROOT/missing-no-staged-remote.git"
  local output_file="$TMP_ROOT/push-no-staged-output.txt"

  if PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --commit --push "$repo" > "$output_file" 2>&1; then
    fail "expected commit mode to fail when no changes are staged"
  fi

  local output
  output="$(<"$output_file")"
  assert_contains "$output" "No staged changes to commit."
  assert_not_contains "$output" "Push failed. Commit remains local."
  assert_equals "$(git -C "$repo" log -1 --pretty=%s)" "Initial"
  assert_equals "$(remote_subject "$remote")" "Initial"
}
```

- [ ] **Step 4: Add interactive push tests**

Insert these tests after the no-staged failure test:

```zsh
test_interactive_push_pushes_only_after_commit_choice() {
  local repo="$TMP_ROOT/interactive-push"
  local remote="$TMP_ROOT/interactive-push-remote.git"
  make_tracking_repo "$repo" "$remote"
  print -r -- "changed" > "$repo/file.txt"
  git -C "$repo" add file.txt

  print c | PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --push "$repo" >/dev/null

  assert_equals "$(git -C "$repo" log -1 --pretty=%s)" "Add terminal commit message helper"
  assert_equals "$(remote_subject "$remote")" "Add terminal commit message helper"
}

test_interactive_push_does_not_push_after_quit_choice() {
  local repo="$TMP_ROOT/interactive-push-quit"
  local remote="$TMP_ROOT/interactive-push-quit-remote.git"
  make_tracking_repo "$repo" "$remote"
  print -r -- "changed" > "$repo/file.txt"
  git -C "$repo" add file.txt

  print q | PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --push "$repo" >/dev/null

  assert_equals "$(git -C "$repo" log -1 --pretty=%s)" "Initial"
  assert_equals "$(remote_subject "$remote")" "Initial"
  [[ -n "$(git -C "$repo" status --short)" ]] || fail "expected staged change to remain after quitting"
}
```

- [ ] **Step 5: Add push workflow tests to the call list**

Update the bottom of `test_quill.sh` so these calls appear before the invalid-combination tests:

```zsh
test_commit_push_commits_staged_changes_and_pushes
test_full_stages_commits_and_pushes_unstaged_changes
test_push_failure_leaves_local_commit_and_exits_nonzero
test_push_does_not_run_when_commit_mode_has_no_staged_changes
test_interactive_push_pushes_only_after_commit_choice
test_interactive_push_does_not_push_after_quit_choice
test_push_rejects_non_commit_modes_before_generation
test_full_rejects_non_commit_modes_regardless_of_order
test_readme_documents_push_and_full_flags
```

- [ ] **Step 6: Run the suite and confirm push tests fail for missing push behavior**

Run:

```bash
rtk zsh test_quill.sh
```

Expected: a push workflow test fails because `commit_message` does not yet call `git push`. A representative failure is:

```text
FAIL: expected 'Add terminal commit message helper' but got 'Initial'
```

### Task 4: Implement Push After Commit

**Files:**
- Modify: `quill:323-335`
- Test: `test_quill.sh`

- [ ] **Step 1: Add the push helper**

Insert this helper immediately before `commit_message` at `quill:323`:

```zsh
push_commits() {
  if git -C "$REPO" push; then
    return 0
  fi

  print -u2 -- "Push failed. Commit remains local."
  return 1
}
```

This helper owns a real side effect and one user-facing failure message. It must not add arguments to `git push`, retry, suppress Git output, or roll back commits.

- [ ] **Step 2: Sequence push inside `commit_message`**

Replace `commit_message` at `quill:323-335` with:

```zsh
commit_message() {
  if [[ "$ADD_ALL" -eq 1 ]]; then
    git -C "$REPO" add -A
  fi

  if [[ -z "$(git -C "$REPO" diff --cached --name-only)" ]]; then
    print -u2 -- "No staged changes to commit."
    print -u2 -- "Stage files with git add <file> and run quill again."
    return 1
  fi

  if ! git -C "$REPO" commit -F "$MESSAGE_FILE"; then
    return 1
  fi

  if [[ "$PUSH_AFTER_COMMIT" -eq 1 ]]; then
    push_commits
  fi
}
```

- [ ] **Step 3: Run the suite and confirm only README docs remain failing**

Run:

```bash
rtk zsh test_quill.sh
```

Expected: push workflow tests pass. The README test still fails until Task 5 updates documentation.

### Task 5: Update README Usage Docs

**Files:**
- Modify: `README.md:92-125`
- Test: `test_quill.sh`

- [ ] **Step 1: Add push and full usage examples**

Insert this section after the existing `quill --add --commit` example and its explanatory paragraph:

````markdown
To commit staged changes and then push with Git's configured default push target:

```sh
quill --commit --push
```

To stage all changes, commit, and push:

```sh
quill --add --commit --push
```

`--full` is shorthand for `--add --commit --push`:

```sh
quill --full
```

In interactive mode, `quill --push` prepares the message as usual and pushes only
if you choose `[c]ommit`. It does not push after copy, regenerate, quit, or an
empty choice.

Push failures leave the local commit in place. Quillmit prints Git's push
diagnostics, reports that the commit remains local, and exits nonzero.
````

- [ ] **Step 2: Keep the existing staged-first wording intact**

Confirm the README still contains these existing claims:

```markdown
If files are staged, Quillmit generates the message from staged changes only.
If nothing is staged, it generates from the changed working tree.
Commit actions only commit staged changes by default.
```

and:

```markdown
In interactive mode, `quill --add` generates from all changed files and stages
everything only if you choose `[c]ommit`.
```

- [ ] **Step 3: Run the suite and confirm all tests pass**

Run:

```bash
rtk zsh test_quill.sh
```

Expected:

```text
All tests passed
```

### Task 6: Final Verification And Handoff

**Files:**
- Verify: `quill`
- Verify: `test_quill.sh`
- Verify: `README.md`

- [ ] **Step 1: Run the required automated verification**

Run:

```bash
rtk zsh test_quill.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 2: Inspect the final diff for scope**

Run:

```bash
rtk git diff -- quill test_quill.sh README.md
```

Expected:

- `quill` changes are limited to usage text, parser state/cases, conflict validation, `push_commits`, and `commit_message`.
- `test_quill.sh` changes are limited to assertion/helper additions, local remote helpers, new push/full tests, and the manual call list.
- `README.md` changes are limited to usage examples and push behavior.
- No provider prompt changes, no action pipeline, no remote/branch/upstream push arguments, and no force/tag push arguments.

- [ ] **Step 3: Commit the implementation**

Run:

```bash
rtk git add quill test_quill.sh README.md
rtk git commit -m "feat: add push and full flags"
```

Expected: one product-code commit containing only the three implementation files.

## Merlin Handoff Notes

- Start with tests. Do not implement push behavior before adding the failing parser and push workflow tests.
- Keep `--push` as a modifier. It must not push a clean repository by itself because the approved design treats it as post-commit behavior.
- Conflict validation must be independent of final `MODE`; track whether any non-commit mode flag was ever supplied.
- `--full` should set `ADD_ALL=1`, `MODE="commit"`, and `PUSH_AFTER_COMMIT=1`.
- `--yes --push` must work because `--yes` is an alias for commit mode.
- Push must run exactly as `git -C "$REPO" push`.
- A push failure after a successful commit must return nonzero and leave the local commit in place.
- Automated tests must use local bare remotes only; do not depend on network remotes or real provider CLIs.

## Plan Self-Review

- Spec coverage: covered CLI surface, `--full` equivalence, execution order, failure behavior, guardrails, README docs, and verification from the approved design.
- Vesta coverage: carried forward order-independent validation and the accepted bare `--push` post-commit assumption.
- Red-flag scan: no unresolved values or deferred decisions.
- Scope check: one executable, one test file, one README section; no unrelated refactor.
- Ambiguity check: explicit invalid-combination error text and exact `git push` command are specified.
