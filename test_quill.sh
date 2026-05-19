#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quill-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain: $needle"
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  [[ "$actual" == "$expected" ]] || fail "expected '$expected' but got '$actual'"
}

write_fake_cli() {
  local cli_path="$1"
  local name="$2"
  local message="$3"
  cat > "$cli_path" <<SCRIPT
#!/bin/zsh
set -euo pipefail
out=""
stdin_capture="\${${name:u}_STDIN_CAPTURE:-\${QUILL_STDIN_CAPTURE:-}}"
args_capture="\${${name:u}_ARGS_CAPTURE:-}"
if [[ -n "\$args_capture" ]]; then
  print -r -- "\$*" > "\$args_capture"
fi
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o|--output-last-message)
      out="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [[ -n "\$stdin_capture" ]]; then
  cat > "\$stdin_capture"
else
  cat >/dev/null
fi
print -- "${name} fake noisy transcript"
print -u2 -- "${name} fake stderr warning"
if [[ -n "\$out" ]]; then
  cat > "\$out" <<'MSG'
$message
MSG
else
  cat <<'MSG'
$message
MSG
fi
SCRIPT
  chmod +x "$cli_path"
}

make_fake_bin() {
  local bin="$TMP_ROOT/bin"
  mkdir -p "$bin"
  write_fake_cli "$bin/codex" "codex" "Add terminal commit message helper

Reads the current Git state and drafts a focused commit message.
Keeps the actual commit behind an explicit terminal action."
  write_fake_cli "$bin/claude" "claude" "Feature: Add Claude-backed commit message generation

Routes the same Git context through Claude Code in headless mode.
Keeps provider output quiet while preserving the preview and commit flow."
  write_fake_cli "$bin/gemini" "gemini" "Add Gemini-backed commit message generation

Routes the same Git context through Gemini CLI in non-interactive mode.
Keeps model selection configurable per provider."
  cat > "$bin/pbcopy" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
cat > "${PBCOPY_CAPTURE:?PBCOPY_CAPTURE is required}"
SCRIPT
  chmod +x "$bin/pbcopy"
  cat > "$bin/wl-copy" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
cat > "${WLCOPY_CAPTURE:?WLCOPY_CAPTURE is required}"
SCRIPT
  chmod +x "$bin/wl-copy"
  print -r -- "$bin:$PATH"
}

make_dirty_repo() {
  local repo="$1"
  git init -q "$repo"
  print -r -- "hello" > "$repo/file.txt"
}

make_dirty_repo_with_remote() {
  local repo="$1"
  local remote="$2"
  git init --bare -q "$remote"
  git --git-dir "$remote" symbolic-ref HEAD refs/heads/main
  git init -q "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  git -C "$repo" branch -M main
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" config branch.main.remote origin
  git -C "$repo" config branch.main.merge refs/heads/main
  print -r -- "hello" > "$repo/file.txt"
}

commit_editmsg_path() {
  local repo="$1"
  git -C "$repo" rev-parse --path-format=absolute --git-path COMMIT_EDITMSG
}

test_clean_repo_reports_no_changes() {
  local repo="$TMP_ROOT/clean"
  git init -q "$repo"

  local output
  output="$(PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --quit "$repo")"

  assert_contains "$output" "No changes to commit"
}

test_codex_is_default_and_receives_git_context() {
  local repo="$TMP_ROOT/codex"
  make_dirty_repo "$repo"
  local prompt_capture="$TMP_ROOT/codex-prompt.txt"
  local args_capture="$TMP_ROOT/codex-args.txt"

  local output
  output="$(QUILL_STDIN_CAPTURE="$prompt_capture" CODEX_ARGS_CAPTURE="$args_capture" PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --quit "$repo" 2>&1)"

  assert_contains "$output" "Generating commit message with Codex"
  assert_contains "$output" "Add terminal commit message helper"
  assert_not_contains "$output" "codex fake noisy transcript"
  assert_not_contains "$output" "codex fake stderr warning"
  assert_contains "$(<"$prompt_capture")" "Git status --short:"
  assert_contains "$(<"$prompt_capture")" "?? file.txt"
  assert_contains "$(<"$prompt_capture")" "Do not use conventional commit prefixes"
  assert_contains "$(<"$prompt_capture")" "Bad: feat(pipeline): add telemetry"
  assert_contains "$(<"$args_capture")" "gpt-5.3-codex"
  [[ -n "$(git -C "$repo" status --short)" ]] || fail "expected repo to remain dirty"
}

test_default_prepares_and_prompts_for_action() {
  local repo="$TMP_ROOT/prepare"
  make_dirty_repo "$repo"

  local output
  output="$(print q | PATH="$(make_fake_bin):$PATH" "$ROOT/quill" "$repo")"

  assert_contains "$output" "Prepared commit message"
  assert_contains "$output" "[c]ommit, [e]dit, co[p]y, [r]egenerate, [q]uit"
  assert_contains "$output" "Quit without committing"
  assert_contains "$(<"$(commit_editmsg_path "$repo")")" "Add terminal commit message helper"
  [[ -n "$(git -C "$repo" status --short)" ]] || fail "expected repo to remain dirty after prepare"
}

test_prepare_mode_prepares_and_exits() {
  local repo="$TMP_ROOT/prepare-only"
  make_dirty_repo "$repo"

  local output
  output="$(PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --prepare "$repo")"

  assert_contains "$output" "Prepared commit message"
  assert_not_contains "$output" "[c]ommit, [e]dit, co[p]y, [r]egenerate, [q]uit"
  assert_contains "$(<"$(commit_editmsg_path "$repo")")" "Add terminal commit message helper"
  [[ -n "$(git -C "$repo" status --short)" ]] || fail "expected repo to remain dirty after prepare"
}

test_quit_prints_without_preparing() {
  local repo="$TMP_ROOT/quit"
  make_dirty_repo "$repo"

  local output
  output="$(PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --quit "$repo")"

  assert_contains "$output" "Quit without preparing or committing"
  if [[ -f "$(commit_editmsg_path "$repo")" ]]; then
    assert_not_contains "$(<"$(commit_editmsg_path "$repo")")" "Add terminal commit message helper"
  fi
}

test_staged_changes_use_staged_context_only() {
  local repo="$TMP_ROOT/staged"
  git init -q "$repo"
  print -r -- "base" > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  git -C "$repo" commit -m "Initial" >/dev/null
  print -r -- "staged" > "$repo/file.txt"
  git -C "$repo" add file.txt
  print -r -- "unstaged" > "$repo/other.txt"
  local prompt_capture="$TMP_ROOT/staged-prompt.txt"

  QUILL_STDIN_CAPTURE="$prompt_capture" PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --quit "$repo" >/dev/null

  assert_contains "$(<"$prompt_capture")" "Context mode: staged changes only"
  assert_contains "$(<"$prompt_capture")" "Staged diff:"
  assert_not_contains "$(<"$prompt_capture")" "Unstaged diff:"
  assert_not_contains "$(<"$prompt_capture")" "Untracked files:"
  assert_not_contains "$(<"$prompt_capture")" "other.txt"
}

test_claude_provider_uses_configured_model() {
  local repo="$TMP_ROOT/claude"
  make_dirty_repo "$repo"
  local args_capture="$TMP_ROOT/claude-args.txt"

  local output
  output="$(CLAUDE_ARGS_CAPTURE="$args_capture" PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --claude --quit "$repo")"

  assert_contains "$output" "Generating commit message with Claude"
  assert_contains "$output" "Feature: Add Claude-backed commit message generation"
  assert_contains "$(<"$args_capture")" "--model haiku"
  assert_contains "$(<"$args_capture")" "--bare"
  assert_contains "$(<"$args_capture")" "-p"
}

test_gemini_provider_uses_configured_model() {
  local repo="$TMP_ROOT/gemini"
  make_dirty_repo "$repo"
  local args_capture="$TMP_ROOT/gemini-args.txt"

  local output
  output="$(GEMINI_ARGS_CAPTURE="$args_capture" PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --gemini --quit "$repo")"

  assert_contains "$output" "Generating commit message with Gemini"
  assert_contains "$output" "Add Gemini-backed commit message generation"
  assert_contains "$(<"$args_capture")" "--model gemini-3-flash-preview"
  assert_contains "$(<"$args_capture")" "-p"
}

test_config_overrides_default_provider_and_models() {
  local repo="$TMP_ROOT/config"
  make_dirty_repo "$repo"
  local config="$TMP_ROOT/quill.config"
  local args_capture="$TMP_ROOT/claude-config-args.txt"
  cat > "$config" <<'CONFIG'
DEFAULT_PROVIDER=claude
CLAUDE_MODEL=claude-haiku-4-5-20251001
CONFIG

  local output
  output="$(CLAUDE_ARGS_CAPTURE="$args_capture" PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --config "$config" --quit "$repo")"

  assert_contains "$output" "Generating commit message with Claude"
  assert_contains "$(<"$args_capture")" "--model claude-haiku-4-5-20251001"
}

test_commits_with_generated_message() {
  local repo="$TMP_ROOT/commit"
  make_dirty_repo "$repo"
  git -C "$repo" add file.txt
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"

  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --yes "$repo" >/dev/null

  local subject
  subject="$(git -C "$repo" log -1 --pretty=%s)"
  [[ "$subject" == "Add terminal commit message helper" ]] || fail "unexpected commit subject: $subject"
  [[ -z "$(git -C "$repo" status --short)" ]] || fail "expected repo to be clean after commit"
}

test_commits_only_staged_changes_when_staged_changes_exist() {
  local repo="$TMP_ROOT/staged-commit"
  git init -q "$repo"
  print -r -- "base" > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  git -C "$repo" commit -m "Initial" >/dev/null
  print -r -- "staged" > "$repo/file.txt"
  git -C "$repo" add file.txt
  print -r -- "unstaged" > "$repo/other.txt"

  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --commit "$repo" >/dev/null

  local subject
  subject="$(git -C "$repo" log -1 --pretty=%s)"
  [[ "$subject" == "Add terminal commit message helper" ]] || fail "unexpected commit subject: $subject"
  [[ "$(git -C "$repo" show --pretty= --name-only HEAD)" == "file.txt" ]] || fail "expected only staged file to be committed"
  [[ "$(git -C "$repo" status --short)" == "?? other.txt" ]] || fail "expected unstaged file to remain uncommitted"
}

test_commit_mode_fails_cleanly_without_staged_changes() {
  local repo="$TMP_ROOT/commit-no-staged"
  make_dirty_repo "$repo"
  local output_file="$TMP_ROOT/commit-no-staged-output.txt"

  if PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --commit "$repo" > "$output_file" 2>&1; then
    fail "expected commit mode to fail when no changes are staged"
  fi

  local output
  output="$(<"$output_file")"
  assert_contains "$output" "No staged changes to commit."
  assert_contains "$output" "Stage files with git add <file> and run quill again."
  assert_not_contains "$output" "Changes not staged for commit:"
  assert_not_contains "$output" "no changes added to commit"
  [[ -n "$(git -C "$repo" status --short)" ]] || fail "expected repo to remain dirty"
}

test_add_flag_stages_all_changes_before_commit() {
  local repo="$TMP_ROOT/add-commit"
  make_dirty_repo "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"

  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --add --commit "$repo" >/dev/null

  local subject
  subject="$(git -C "$repo" log -1 --pretty=%s)"
  [[ "$subject" == "Add terminal commit message helper" ]] || fail "unexpected commit subject: $subject"
  [[ "$(git -C "$repo" show --pretty= --name-only HEAD)" == "file.txt" ]] || fail "expected add flag to commit unstaged file"
  [[ -z "$(git -C "$repo" status --short)" ]] || fail "expected repo to be clean after add commit"
}

test_add_flag_generates_context_from_all_changes() {
  local repo="$TMP_ROOT/add-context"
  git init -q "$repo"
  print -r -- "base" > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  git -C "$repo" commit -m "Initial" >/dev/null
  print -r -- "staged" > "$repo/file.txt"
  git -C "$repo" add file.txt
  print -r -- "unstaged" > "$repo/other.txt"
  local prompt_capture="$TMP_ROOT/add-context-prompt.txt"

  QUILL_STDIN_CAPTURE="$prompt_capture" PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --add --quit "$repo" >/dev/null

  assert_contains "$(<"$prompt_capture")" "Context mode: all changed files"
  assert_contains "$(<"$prompt_capture")" "Untracked files:"
  assert_contains "$(<"$prompt_capture")" "other.txt"
}

test_commit_alias_commits_with_generated_message() {
  local repo="$TMP_ROOT/commit-alias"
  make_dirty_repo "$repo"
  git -C "$repo" add file.txt
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"

  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --commit "$repo" >/dev/null

  local subject
  subject="$(git -C "$repo" log -1 --pretty=%s)"
  [[ "$subject" == "Add terminal commit message helper" ]] || fail "unexpected commit subject: $subject"
  [[ -z "$(git -C "$repo" status --short)" ]] || fail "expected repo to be clean after commit"
}

test_copy_mode_copies_without_committing() {
  local repo="$TMP_ROOT/copy"
  make_dirty_repo "$repo"
  local copy_capture="$TMP_ROOT/copied-message.txt"

  local output
  output="$(PBCOPY_CAPTURE="$copy_capture" PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --copy "$repo")"

  assert_contains "$output" "Copied commit message to clipboard"
  assert_contains "$(<"$copy_capture")" "Add terminal commit message helper"
  assert_contains "$(<"$(commit_editmsg_path "$repo")")" "Add terminal commit message helper"
  [[ -n "$(git -C "$repo" status --short)" ]] || fail "expected repo to remain dirty after copy"
}

test_copy_mode_supports_linux_clipboard_fallback() {
  local repo="$TMP_ROOT/copy-linux"
  make_dirty_repo "$repo"
  local copy_capture="$TMP_ROOT/wl-copied-message.txt"
  local fake_path="$(make_fake_bin)"
  cat > "${fake_path%%:*}/pbcopy" <<'SCRIPT'
#!/bin/zsh
exit 1
SCRIPT
  chmod +x "${fake_path%%:*}/pbcopy"

  local output
  output="$(WLCOPY_CAPTURE="$copy_capture" PATH="$fake_path" "$ROOT/quill" --copy "$repo")"

  assert_contains "$output" "Copied commit message to clipboard"
  assert_contains "$(<"$copy_capture")" "Add terminal commit message helper"
}

test_commit_push_pushes_staged_commit() {
  local repo="$TMP_ROOT/push-commit"
  local remote="$TMP_ROOT/push-commit.git"
  make_dirty_repo_with_remote "$repo" "$remote"
  git -C "$repo" add file.txt

  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --commit --push "$repo" >/dev/null

  assert_equals "$(git --git-dir "$remote" log -1 --pretty=%s)" "Add terminal commit message helper"
  [[ -z "$(git -C "$repo" status --short)" ]] || fail "expected repo to be clean after pushed commit"
}

test_yes_push_pushes_staged_commit() {
  local repo="$TMP_ROOT/yes-push"
  local remote="$TMP_ROOT/yes-push.git"
  make_dirty_repo_with_remote "$repo" "$remote"
  git -C "$repo" add file.txt

  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --yes --push "$repo" >/dev/null

  assert_equals "$(git --git-dir "$remote" log -1 --pretty=%s)" "Add terminal commit message helper"
}

test_full_stages_commits_and_pushes_all_changes() {
  local repo="$TMP_ROOT/full"
  local remote="$TMP_ROOT/full.git"
  make_dirty_repo_with_remote "$repo" "$remote"

  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --full "$repo" >/dev/null

  assert_equals "$(git --git-dir "$remote" log -1 --pretty=%s)" "Add terminal commit message helper"
  assert_equals "$(git -C "$repo" show --pretty= --name-only HEAD)" "file.txt"
  [[ -z "$(git -C "$repo" status --short)" ]] || fail "expected repo to be clean after full push"
}

test_push_does_not_run_when_commit_has_no_staged_changes() {
  local repo="$TMP_ROOT/push-no-staged"
  local remote="$TMP_ROOT/push-no-staged.git"
  make_dirty_repo_with_remote "$repo" "$remote"
  local output_file="$TMP_ROOT/push-no-staged-output.txt"

  if PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --commit --push "$repo" > "$output_file" 2>&1; then
    fail "expected commit push to fail without staged changes"
  fi

  local output
  output="$(<"$output_file")"
  assert_contains "$output" "No staged changes to commit."
  assert_not_contains "$output" "Push failed. Commit remains local."
  if git --git-dir "$remote" rev-parse --verify HEAD >/dev/null 2>&1; then
    fail "expected remote to remain without commits"
  fi
}

test_push_failure_leaves_local_commit() {
  local repo="$TMP_ROOT/push-failure"
  local remote="$TMP_ROOT/push-failure.git"
  make_dirty_repo_with_remote "$repo" "$remote"
  git -C "$repo" add file.txt
  rm -rf "$remote"
  local output_file="$TMP_ROOT/push-failure-output.txt"

  if PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --commit --push "$repo" > "$output_file" 2>&1; then
    fail "expected push failure to return nonzero"
  fi

  local output
  output="$(<"$output_file")"
  assert_contains "$output" "Push failed. Commit remains local."
  assert_equals "$(git -C "$repo" log -1 --pretty=%s)" "Add terminal commit message helper"
  [[ -z "$(git -C "$repo" status --short)" ]] || fail "expected local commit to remain clean"
}

test_interactive_push_pushes_only_after_commit_choice() {
  local repo="$TMP_ROOT/interactive-push"
  local remote="$TMP_ROOT/interactive-push.git"
  make_dirty_repo_with_remote "$repo" "$remote"
  git -C "$repo" add file.txt

  print c | PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --push "$repo" >/dev/null

  assert_equals "$(git --git-dir "$remote" log -1 --pretty=%s)" "Add terminal commit message helper"
}

test_interactive_push_does_not_push_after_quit_choice() {
  local repo="$TMP_ROOT/interactive-push-quit"
  local remote="$TMP_ROOT/interactive-push-quit.git"
  make_dirty_repo_with_remote "$repo" "$remote"
  git -C "$repo" add file.txt

  print q | PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --push "$repo" >/dev/null

  if git --git-dir "$remote" rev-parse --verify HEAD >/dev/null 2>&1; then
    fail "expected remote to remain without commits after quit"
  fi
  [[ -n "$(git -C "$repo" status --short)" ]] || fail "expected repo to remain dirty after quit"
}

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

test_install_links_quill_only() {
  local install_bin="$TMP_ROOT/install-bin"
  mkdir -p "$install_bin"
  ln -s "$ROOT/gcommit" "$install_bin/gcommit"
  ln -s "/Users/liadgoren/Repositories/quill/quill" "$install_bin/old-quill"
  ln -s "/Users/liadgoren/Repositories/quill/quill" "$install_bin/quill"

  local output
  output="$("$ROOT/install" --bin-dir "$install_bin")"

  assert_contains "$output" "Installed quill"
  assert_contains "$output" "Removed legacy gcommit"
  assert_contains "$output" "Removed stale quill symlink"
  [[ -L "$install_bin/quill" ]] || fail "expected quill symlink"
  [[ "$(readlink "$install_bin/quill")" == "$ROOT/quill" ]] || fail "unexpected quill symlink target"
  [[ ! -e "$install_bin/gcommit" ]] || fail "did not expect gcommit symlink"
  [[ -L "$install_bin/old-quill" ]] || fail "unrelated legacy-looking symlink should remain when not named quill"
}

test_clean_repo_reports_no_changes
test_codex_is_default_and_receives_git_context
test_default_prepares_and_prompts_for_action
test_prepare_mode_prepares_and_exits
test_quit_prints_without_preparing
test_staged_changes_use_staged_context_only
test_claude_provider_uses_configured_model
test_gemini_provider_uses_configured_model
test_config_overrides_default_provider_and_models
test_commits_with_generated_message
test_commits_only_staged_changes_when_staged_changes_exist
test_commit_mode_fails_cleanly_without_staged_changes
test_add_flag_stages_all_changes_before_commit
test_add_flag_generates_context_from_all_changes
test_commit_alias_commits_with_generated_message
test_copy_mode_copies_without_committing
test_copy_mode_supports_linux_clipboard_fallback
test_commit_push_pushes_staged_commit
test_yes_push_pushes_staged_commit
test_full_stages_commits_and_pushes_all_changes
test_push_does_not_run_when_commit_has_no_staged_changes
test_push_failure_leaves_local_commit
test_interactive_push_pushes_only_after_commit_choice
test_interactive_push_does_not_push_after_quit_choice
test_push_rejects_non_commit_modes_before_generation
test_full_rejects_non_commit_modes_regardless_of_order
test_readme_documents_push_and_full_flags
test_install_links_quill_only

print -- "All tests passed"
