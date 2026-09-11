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
prompt_capture_dir="\${QUILL_PROMPT_CAPTURE_DIR:-}"
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
if [[ -n "\$prompt_capture_dir" ]]; then
  mkdir -p "\$prompt_capture_dir"
  cat > "\$(mktemp "\$prompt_capture_dir/prompt.XXXXXX")"
elif [[ -n "\$stdin_capture" ]]; then
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
  cat > "$bin/gh" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail

if [[ "${1:-}" == "repo" && "${2:-}" == "view" ]]; then
  print -- "${GH_REPO_NAME:-test/repo}"
  exit 0
fi

if [[ "${1:-}" != "pr" || "${2:-}" != "create" ]]; then
  print -u2 -- "Unsupported fake gh command: $*"
  exit 1
fi

if [[ -n "${GH_ARGS_CAPTURE:-}" ]]; then
  print -r -- "$*" > "$GH_ARGS_CAPTURE"
fi

body_file=""
shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --body-file)
      body_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "${GH_BODY_CAPTURE:-}" ]]; then
  cp "$body_file" "$GH_BODY_CAPTURE"
fi
if [[ "${GH_SIMULATE_PUSH:-0}" -eq 1 ]]; then
  git -C "${GH_REPO_PATH:?GH_REPO_PATH is required}" push --set-upstream origin HEAD >/dev/null
fi
print -- "https://github.com/test/repo/pull/1"
SCRIPT
  chmod +x "$bin/gh"
  print -r -- "$bin:$PATH"
}

make_dirty_repo() {
  local repo="$1"
  git init -q "$repo"
  print -r -- "hello" > "$repo/file.txt"
}

write_large_file() {
  local path="$1"
  local prefix="$2"
  local lines="$3"
  local index
  {
    for ((index = 1; index <= lines; index++)); do
      print -r -- "$prefix line $index with enough repeated content to exercise prompt batching"
    done
  } > "$path"
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

make_pr_repo() {
  local repo="$1"
  local remote="$2"
  git init --bare -q "$remote"
  git --git-dir "$remote" symbolic-ref HEAD refs/heads/main
  git init -q "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  git -C "$repo" branch -M main
  git -C "$repo" remote add origin "$remote"
  print -r -- "base" > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -m "Initial" >/dev/null
  git -C "$repo" push -u origin main >/dev/null
  git -C "$repo" switch -q -c develop
  print -r -- "develop" > "$repo/develop.txt"
  git -C "$repo" add develop.txt
  git -C "$repo" commit -m "Add develop work" >/dev/null
  git -C "$repo" push -u origin develop >/dev/null
  git -C "$repo" switch -q main
  git -C "$repo" switch -q -c feature
  print -r -- "feature" > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -m "Add feature work" >/dev/null
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
  local configured_model="$(source "$ROOT/quill.config"; print -r -- "$CODEX_MODEL")"
  assert_contains "$(<"$args_capture")" "-m $configured_model"
  assert_contains "$(<"$args_capture")" "model_reasoning_effort=low"
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

test_large_context_uses_parallel_batches_and_synthesis() {
  local repo="$TMP_ROOT/batched"
  git init -q "$repo"
  write_large_file "$repo/one.txt" "one" 220
  write_large_file "$repo/two.txt" "two" 220
  write_large_file "$repo/three.txt" "three" 220
  git -C "$repo" add one.txt two.txt three.txt

  local config="$TMP_ROOT/batched.config"
  print -r -- "CODEX_MAX_PROMPT_BYTES=30000" > "$config"
  local captures="$TMP_ROOT/batched-prompts"
  local output
  output="$(QUILL_PROMPT_CAPTURE_DIR="$captures" PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --config "$config" --quit "$repo")"

  assert_contains "$output" "Large change detected: 3 files"
  assert_contains "$output" "parallel batches"
  assert_contains "$output" "Add terminal commit message helper"
  assert_not_contains "$output" "diff_bytes="
  local summary_count
  summary_count="$(grep -l "Summarize this portion" "$captures"/* | wc -l | tr -d ' ')"
  [[ "$summary_count" -gt 1 ]] || fail "expected multiple summary invocations"
  assert_equals "$(grep -l "Generate one git commit message from summaries" "$captures"/* | wc -l | tr -d ' ')" "1"
}

test_single_oversized_file_splits_across_batches() {
  local repo="$TMP_ROOT/oversized-file"
  git init -q "$repo"
  write_large_file "$repo/large.txt" "oversized" 700
  git -C "$repo" add large.txt

  local config="$TMP_ROOT/oversized-file.config"
  print -r -- "CODEX_MAX_PROMPT_BYTES=20000" > "$config"
  local captures="$TMP_ROOT/oversized-file-prompts"
  local output
  output="$(QUILL_PROMPT_CAPTURE_DIR="$captures" PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --config "$config" --quit "$repo")"

  assert_contains "$output" "Large change detected: 1 file"
  assert_not_contains "$output" "diff_bytes="
  local summary_count
  summary_count="$(grep -l "Summarize this portion" "$captures"/* | wc -l | tr -d ' ')"
  [[ "$summary_count" -gt 1 ]] || fail "expected one oversized file to span multiple summary invocations"
  grep -q "File: large.txt (part" "$captures"/* || fail "expected oversized file parts in summary prompts"
  python3 - "$captures" "$repo" <<'CHECK'
import pathlib, re, subprocess, sys
parts = {}
for prompt in pathlib.Path(sys.argv[1]).glob('*'):
    text = prompt.read_text()
    if not text.startswith('Summarize this portion'):
        continue
    for match in re.finditer(r'--- File: large.txt \(part (\d+)\) ---\n(.*?)(?=\n--- File:|\Z)', text, re.S):
        payload = match[2]
        # Each part repeats the Git file header. Keep the hunk bytes only.
        payload = payload.split('+++ b/large.txt\n', 1)[1]
        parts[int(match[1])] = payload
original = subprocess.check_output(['git', '-C', sys.argv[2], 'diff', '--cached', '--', 'large.txt']).decode()
expected = original.split('+++ b/large.txt\n', 1)[1]
assert ''.join(parts[key] for key in sorted(parts)) == expected, 'batch content differs from the source diff'
CHECK
}

test_batch_budget_is_selected_per_provider() {
  local repo="$TMP_ROOT/provider-budget"
  git init -q "$repo"
  write_large_file "$repo/large.txt" "provider" 500
  git -C "$repo" add large.txt

  local config="$TMP_ROOT/provider-budget.config"
  cat > "$config" <<'CONFIG'
CODEX_MAX_PROMPT_BYTES=100000
CLAUDE_MAX_PROMPT_BYTES=20000
GEMINI_MAX_PROMPT_BYTES=20000
CONFIG

  local claude_output
  claude_output="$(PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --config "$config" --claude --quit "$repo")"
  assert_contains "$claude_output" "Large change detected"
  assert_not_contains "$claude_output" "diff_bytes="

  local gemini_output
  gemini_output="$(PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --config "$config" --gemini --quit "$repo")"
  assert_contains "$gemini_output" "Large change detected"
  assert_not_contains "$gemini_output" "diff_bytes="

  local codex_output
  codex_output="$(PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --config "$config" --codex --quit "$repo")"
  assert_not_contains "$codex_output" "Large change detected"
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

test_add_flag_stages_before_generation() {
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

  assert_contains "$(<"$prompt_capture")" "Context mode: staged changes only"
  assert_contains "$(<"$prompt_capture")" "Staged files:"
  assert_contains "$(<"$prompt_capture")" "other.txt"
  assert_equals "$(git -C "$repo" diff --cached --name-only | sort | tr '\n' ' ')" "file.txt other.txt "
  assert_equals "$(git -C "$repo" diff --name-only)" ""
}

test_add_flag_stages_before_provider_check() {
  local repo="$TMP_ROOT/add-before-provider"
  make_dirty_repo "$repo"
  local output_file="$TMP_ROOT/add-before-provider-output.txt"

  if PATH="/usr/bin:/bin" "$ROOT/quill" --add --quit "$repo" > "$output_file" 2>&1; then
    fail "expected missing provider to fail"
  fi

  local output
  output="$(<"$output_file")"
  assert_contains "$output" "Codex CLI not found in PATH: codex"
  assert_equals "$(git -C "$repo" diff --cached --name-only)" "file.txt"
  assert_equals "$(git -C "$repo" diff --name-only)" ""
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

test_short_flags_match_long_workflows() {
  local commit_repo="$TMP_ROOT/short-commit"
  make_dirty_repo "$commit_repo"
  git -C "$commit_repo" config user.email "test@example.com"
  git -C "$commit_repo" config user.name "Test User"
  git -C "$commit_repo" add file.txt
  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" -c "$commit_repo" >/dev/null
  assert_equals "$(git -C "$commit_repo" log -1 --pretty=%s)" "Add terminal commit message helper"

  local add_repo="$TMP_ROOT/short-add"
  make_dirty_repo "$add_repo"
  git -C "$add_repo" config user.email "test@example.com"
  git -C "$add_repo" config user.name "Test User"
  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" -a -c "$add_repo" >/dev/null
  assert_equals "$(git -C "$add_repo" show --pretty= --name-only HEAD)" "file.txt"

  local push_repo="$TMP_ROOT/short-push"
  local push_remote="$TMP_ROOT/short-push.git"
  make_dirty_repo_with_remote "$push_repo" "$push_remote"
  git -C "$push_repo" add file.txt
  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" -c -p "$push_repo" >/dev/null
  assert_equals "$(git --git-dir "$push_remote" log -1 --pretty=%s)" "Add terminal commit message helper"

  local full_repo="$TMP_ROOT/short-full"
  local full_remote="$TMP_ROOT/short-full.git"
  make_dirty_repo_with_remote "$full_repo" "$full_remote"
  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" -f "$full_repo" >/dev/null
  assert_equals "$(git --git-dir "$full_remote" log -1 --pretty=%s)" "Add terminal commit message helper"
}

test_pr_flow_uses_selected_base_and_generated_content() {
  local repo="$TMP_ROOT/pr-flow"
  local remote="$TMP_ROOT/pr-flow.git"
  make_pr_repo "$repo" "$remote"
  print -r -- "not committed" > "$repo/uncommitted.txt"

  local prompt_capture="$TMP_ROOT/pr-prompt.txt"
  local gh_args_capture="$TMP_ROOT/pr-gh-args.txt"
  local gh_body_capture="$TMP_ROOT/pr-gh-body.md"
  local output
  output="$(
    QUILL_STDIN_CAPTURE="$prompt_capture" \
      GH_ARGS_CAPTURE="$gh_args_capture" \
      GH_BODY_CAPTURE="$gh_body_capture" \
      GH_SIMULATE_PUSH=1 \
      GH_REPO_PATH="$repo" \
      PATH="$(make_fake_bin):$PATH" \
      "$ROOT/quill" pr --remote origin --base develop --no-preview "$repo"
  )"

  assert_not_contains "$output" "Select the pull request base branch"
  assert_contains "$output" "Creating pull request from feature into test/repo:develop"
  assert_contains "$output" "https://github.com/test/repo/pull/1"
  assert_not_contains "$output" "Generated pull request"

  local prompt
  prompt="$(<"$prompt_capture")"
  assert_contains "$prompt" "Generate a pull request title and description"
  assert_contains "$prompt" "Base branch: origin/develop"
  assert_contains "$prompt" "Head branch: feature"
  assert_contains "$prompt" "feature.txt"
  assert_not_contains "$prompt" "uncommitted.txt"

  local gh_args
  gh_args="$(<"$gh_args_capture")"
  assert_contains "$gh_args" "pr create"
  assert_contains "$gh_args" "--base develop"
  assert_contains "$gh_args" "--assignee @me"
  assert_contains "$gh_args" "--title Add terminal commit message helper"
  assert_contains "$(<"$gh_body_capture")" "Reads the current Git state"
  assert_equals "$(git --git-dir "$remote" rev-parse refs/heads/feature)" "$(git -C "$repo" rev-parse HEAD)"
}

test_pr_rejects_commit_workflow_flags() {
  local repo="$TMP_ROOT/pr-invalid"
  git init -q "$repo"
  local output_file="$TMP_ROOT/pr-invalid-output.txt"

  if PATH="$(make_fake_bin):$PATH" "$ROOT/quill" pr -c "$repo" > "$output_file" 2>&1; then
    fail "expected quill pr to reject commit workflow flags"
  fi

  assert_contains "$(<"$output_file")" "Commit workflow flags cannot be combined with quill pr."
  assert_not_contains "$(<"$output_file")" "Generating"
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
  assert_contains "$readme" "quill -c -p"
  assert_contains "$readme" "quill -f"
  assert_contains "$readme" "quill pr"
  assert_contains "$readme" "Push failures leave the local commit in place."
}

# Exercise dependency packaging without downloading or trusting a host fzf.
make_install_source() {
  local source="$1"
  mkdir -p "$source/scripts" "$source/third-party" "$source/fake-bin" "$source/archive"
  cp "$ROOT/quill" "$ROOT/quill.config" "$ROOT/VERSION" "$ROOT/install" "$source/"
  cp "$ROOT/scripts/setup-deps" "$source/scripts/"
  cp "$ROOT/third-party/fzf.LICENSE" "$source/third-party/"
  print -rl -- '#!/bin/sh' 'echo fixture-fzf' > "$source/archive/fzf"
  chmod +x "$source/archive/fzf"
  tar -czf "$source/fzf.tar.gz" -C "$source/archive" fzf
  local checksum="$(shasum -a 256 "$source/fzf.tar.gz")"
  {
    print -- 'version 0.74.3'
    local target
    for target in darwin_arm64 darwin_amd64 linux_arm64 linux_amd64; do
      print -- "${checksum%% *}  fzf-0.74.3-$target.tar.gz"
    done
  } > "$source/third-party/fzf.lock"
  cat > "$source/fake-bin/curl" <<'SCRIPT'
#!/bin/zsh
set -eu
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --output ]]; then cp "${0:A:h:h}/fzf.tar.gz" "$2"; exit 0; fi
  shift
done
exit 1
SCRIPT
  chmod +x "$source/fake-bin/curl"
}

test_pr_scripted_validation() {
  local repo="$TMP_ROOT/pr-validation"
  make_pr_repo "$repo" "$TMP_ROOT/pr-validation.git"
  local bin="$(make_fake_bin)" output
  for invalid in remote base; do
    if output="$(PATH="$bin" "$ROOT/quill" pr --remote origin --base develop --no-preview --$invalid missing "$repo" 2>&1)"; then
      fail "expected invalid PR $invalid to fail"
    fi
    assert_contains "$output" "Unknown"
  done
  if output="$(PATH="$bin" "$ROOT/quill" pr --base develop "$repo" 2>&1)"; then
    fail "expected approval to require a terminal"
  fi
  assert_contains "$output" "--no-preview"
  git -C "$repo" remote add second "$TMP_ROOT/pr-validation.git"
  if output="$(PATH="$bin" "$ROOT/quill" pr --base develop --no-preview "$repo" 2>&1)"; then
    fail "expected ambiguous remote to require selection"
  fi
  assert_contains "$output" "--remote"
  for invalid in --base --remote; do
    if "$ROOT/quill" pr "$invalid" > /dev/null 2>&1; then fail "expected missing argument rejection"; fi
  done
  if "$ROOT/quill" --no-preview "$repo" >/dev/null 2>&1; then fail "expected PR-only flag rejection"; fi
}

test_install_copies_versioned_quill_package() {
  local source="$TMP_ROOT/install-source"
  make_install_source "$source"
  local ROOT="$source"
  local -x PATH="$source/fake-bin:$PATH"
  local install_bin="$TMP_ROOT/install-bin"
  local install_root="$TMP_ROOT/install root"
  mkdir -p "$install_bin"
  mkdir -p "$install_root/versions/0.2.9" "$install_root/versions/notes"
  print -r -- "old" > "$install_root/versions/0.2.9/quill"
  print -r -- "old" > "$install_root/versions/0.2.9/quill.config"
  print -r -- "0.2.9" > "$install_root/versions/0.2.9/VERSION"
  print -r -- "keep" > "$install_root/versions/notes/README"
  ln -s "$ROOT/gcommit" "$install_bin/gcommit"
  ln -s "/Users/liadgoren/Repositories/quill/quill" "$install_bin/old-quill"
  ln -s "/Users/liadgoren/Repositories/quill/quill" "$install_bin/quill"

  local output
  output="$("$ROOT/install" --bin-dir "$install_bin" --install-root "$install_root" 2>&1)" || fail "$output"

  local version
  version="$(<"$ROOT/VERSION")"
  local version_dir="$install_root/versions/$version"
  assert_contains "$output" "Installed Quillmit $version"
  assert_contains "$output" "Installed quill launcher"
  assert_contains "$output" "Removed legacy gcommit"
  assert_contains "$output" "Removed legacy quill symlink"
  assert_contains "$output" "Removed Quillmit 0.2.9"
  assert_contains "$output" "Preserved unrecognized install artifact"
  [[ -f "$install_bin/quill" && ! -L "$install_bin/quill" ]] || fail "expected a copied quill launcher"
  [[ -x "$install_bin/quill" ]] || fail "expected executable quill launcher"
  assert_equals "$("$install_bin/quill" --version)" "quill $version"
  cmp -s "$ROOT/quill" "$version_dir/quill" || fail "installed quill differs from release source"
  cmp -s "$ROOT/quill.config" "$version_dir/quill.config" || fail "installed config differs from release source"
  cmp -s "$ROOT/VERSION" "$version_dir/VERSION" || fail "installed version differs from release source"
  [[ ! -e "$install_root/versions/0.2.9" ]] || fail "expected old Quillmit version to be removed"
  [[ -f "$install_root/versions/notes/README" ]] || fail "expected unrecognized install artifact to be preserved"
  [[ ! -e "$install_bin/gcommit" ]] || fail "did not expect gcommit symlink"
  [[ -L "$install_bin/old-quill" ]] || fail "unrelated legacy-looking symlink should remain when not named quill"

  "$ROOT/install" --bin-dir "$install_bin" --install-root "$install_root" >/dev/null 2>&1
  print -r -- "changed" >> "$version_dir/quill"
  local failure="$TMP_ROOT/install-version-mismatch.txt"
  if "$ROOT/install" --bin-dir "$install_bin" --install-root "$install_root" > "$failure" 2>&1; then
    fail "expected changed bytes for an installed version to be refused"
  fi
  assert_contains "$(<"$failure")" "Bump VERSION before installing changed release bytes"
  local relative="$TMP_ROOT/relative-install"
  mkdir -p "$relative"
  mkdir -p "$relative/bin"
  ln -s "$relative/unrelated-command" "$relative/bin/gcommit"
  (cd "$relative" && "$ROOT/install" --bin-dir bin --install-root packages) >/dev/null 2>&1
  [[ -L "$relative/bin/gcommit" ]] || fail "unowned gcommit was removed"
  assert_equals "$(cd / && "$relative/bin/quill" --version)" "quill $version"
  # Reject an unowned launcher before downloading or creating a release package.
  mkdir -p "$TMP_ROOT/unowned/bin"
  print -- keep > "$TMP_ROOT/unowned/bin/quill"
  if "$ROOT/install" --bin-dir "$TMP_ROOT/unowned/bin" --install-root "$TMP_ROOT/unowned/packages" >/dev/null 2>&1; then
    fail "expected unowned launcher rejection"
  fi
  [[ ! -e "$TMP_ROOT/unowned/packages" ]] || fail "unowned launcher caused package writes"
  assert_equals "$(cat "$TMP_ROOT/unowned/bin/quill")" keep
  # A failed download checksum must not switch the current launcher.
  print -- corrupted > "$source/fzf.tar.gz"
  if "$ROOT/install" --bin-dir "$relative/bin" --install-root "$relative/packages" >/dev/null 2>&1; then
    fail "expected checksum failure"
  fi
  assert_equals "$(cd / && "$relative/bin/quill" --version)" "quill $version"
}


test_version_script_supports_semantic_bumps() {
  local sandbox="$TMP_ROOT/version-script"
  mkdir -p "$sandbox/scripts"
  cp "$ROOT/scripts/version" "$sandbox/scripts/version"
  print -r -- "2.4.9" > "$sandbox/VERSION"

  local output
  output="$("$sandbox/scripts/version")"
  assert_contains "$output" "2.4.9 -> 2.4.10 (patch)"
  assert_equals "$(<"$sandbox/VERSION")" "2.4.10"

  output="$("$sandbox/scripts/version" --minor)"
  assert_contains "$output" "2.4.10 -> 2.5.0 (minor)"
  assert_equals "$(<"$sandbox/VERSION")" "2.5.0"

  output="$("$sandbox/scripts/version" --major)"
  assert_contains "$output" "2.5.0 -> 3.0.0 (major)"
  assert_equals "$(<"$sandbox/VERSION")" "3.0.0"
}

test_version_and_deploy_reject_multiple_bump_flags() {
  local sandbox="$TMP_ROOT/version-invalid"
  mkdir -p "$sandbox/scripts"
  cp "$ROOT/scripts/version" "$sandbox/scripts/version"
  print -r -- "1.0.0" > "$sandbox/VERSION"

  local failure="$TMP_ROOT/version-multiple-flags.txt"
  if "$sandbox/scripts/version" --patch --minor > "$failure" 2>&1; then
    fail "expected version to reject multiple bump flags"
  fi
  assert_contains "$(<"$failure")" "Choose exactly one"
  assert_equals "$(<"$sandbox/VERSION")" "1.0.0"

  failure="$TMP_ROOT/deploy-multiple-flags.txt"
  if "$ROOT/deploy" --minor --major > "$failure" 2>&1; then
    fail "expected deploy to reject multiple bump flags"
  fi
  assert_contains "$(<"$failure")" "Choose exactly one"
}

test_deploy_help_documents_release_boundary() {
  local output
  output="$("$ROOT/deploy" --help)"
  assert_contains "$output" "default: patch"
  assert_contains "$output" "All working-tree changes are included"
  assert_contains "$output" "create the matching GitHub release"
}


# Provider failures must preserve the index and history. A usage-limit failure
# permits one configured fallback; ordinary failures and empty output do not.
test_provider_failure_contracts() {
  local bin="$TMP_ROOT/provider-bin" config="$TMP_ROOT/provider.config"
  mkdir -p "$bin"
  cat > "$bin/codex" <<'SCRIPT'
#!/bin/zsh
set -eu
model='' out=''
while (( $# )); do
  case "$1" in
    -m) model="$2"; shift 2 ;;
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
prompt="$(cat)"
print -r -- "$model" >> "$CALLS"
case "$BEHAVIOR" in
  error) print -u2 -- 'connection failed'; exit 1 ;;
  empty) : > "$out"; exit 0 ;;
  limit|fallback-error)
    if [[ "$model" == primary ]]; then
      print -u2 -- "ERROR: You've hit your usage limit for primary"; exit 1
    fi
    [[ "$BEHAVIOR" != fallback-error ]] || exit 1 ;;
  batch-error)
    [[ "$prompt" != *'Generate one git commit message from summaries'* ]] || touch "$SYNTHESIS"
    [[ "$prompt" != *'Summarize this portion'* ]] || exit 1 ;;
esac
print -r -- 'Successful generated message' > "$out"
SCRIPT
  chmod +x "$bin/codex"
  local scenario fallback repo before index calls
  for scenario in error empty limit fallback-error batch-error success; do
    for fallback in '' secondary; do
      repo="$TMP_ROOT/provider-$scenario-${fallback:-none}"
      make_pr_repo "$repo" "$repo.git"
      print -- pending > "$repo/pending"
      if [[ "$scenario" == batch-error ]]; then
        write_large_file "$repo/large" 'batch data' 700
      fi
      git -C "$repo" add -A
      before="$(git -C "$repo" rev-parse HEAD)"
      index="$(git -C "$repo" write-tree)"
      print -rl -- 'CODEX_MODEL=primary' "CODEX_FALLBACK_MODEL=$fallback" 'CODEX_MAX_PROMPT_BYTES=20000' > "$config"
      calls="$repo.calls"
      if BEHAVIOR="$scenario" CALLS="$calls" SYNTHESIS="$repo.synthesis" PATH="$bin:$PATH" \
        "$ROOT/quill" --config "$config" --commit "$repo" > "$repo.output" 2>&1; then
        [[ "$scenario" == success || ( "$scenario" == limit && -n "$fallback" ) ]] || fail "unexpected provider success: $scenario"
        assert_equals "$(git -C "$repo" log -1 --pretty=%s)" 'Successful generated message'
      else
        [[ "$scenario" != success && ! ( "$scenario" == limit && -n "$fallback" ) ]] || fail "unexpected provider failure: $scenario"
        assert_equals "$(git -C "$repo" rev-parse HEAD)" "$before"
        assert_equals "$(git -C "$repo" write-tree)" "$index"
      fi
      [[ ! -e "$repo.synthesis" ]] || fail 'failed batches reached synthesis'
      if [[ "$scenario" != batch-error ]]; then
        local expected=primary
        if [[ ( "$scenario" == limit || "$scenario" == fallback-error ) && -n "$fallback" ]]; then
          expected=$'primary\nsecondary'
        fi
        assert_equals "$(cat "$calls")" "$expected"
      fi
    done
  done
}

test_dependency_failures_preserve_installation() {
  local source="$TMP_ROOT/dependency-source" target="$TMP_ROOT/dependency-target"
  make_install_source "$source"
  local -x PATH="$source/fake-bin:$PATH"
  "$source/install" --bin-dir "$target/bin" --install-root "$target/packages" >/dev/null
  local launcher="$(cat "$target/bin/quill")" version="$("$target/bin/quill" --version)"
  cp "$source/fzf.tar.gz" "$source/good.tar.gz"
  cp "$source/third-party/fzf.lock" "$source/good.lock"
  print -- '99.0.0' > "$source/VERSION"
  local failure
  for failure in download checksum archive; do
    cp "$source/good.tar.gz" "$source/fzf.tar.gz"
    cp "$source/good.lock" "$source/third-party/fzf.lock"
    case "$failure" in
      download) rm "$source/fzf.tar.gz" ;;
      checksum) print -- corrupted > "$source/fzf.tar.gz" ;;
      archive)
        print -- 'not an archive' > "$source/fzf.tar.gz"
        local checksum="$(shasum -a 256 "$source/fzf.tar.gz")"
        awk -v sum="${checksum%% *}" 'NR == 1 {print; next} {$1=sum; print}' "$source/good.lock" > "$source/third-party/fzf.lock" ;;
    esac
    if "$source/install" --bin-dir "$target/bin" --install-root "$target/packages" > "$target/output" 2>&1; then
      fail "accepted $failure failure"
    fi
    assert_equals "$(cat "$target/bin/quill")" "$launcher"
    assert_equals "$(cd / && "$target/bin/quill" --version)" "$version"
    [[ ! -d "$target/packages/versions/99.0.0" ]] || fail 'failed dependency installed a release'
  done
}

test_git_paths_and_change_types() {
  local repo="$TMP_ROOT/path repo" capture="$TMP_ROOT/path-prompt"
  make_pr_repo "$repo" "$TMP_ROOT/path-remote.git"
  git -C "$repo" mv file.txt 'renamed file.txt'
  rm "$repo/feature.txt"
  print -- 'unicode content marker' > "$repo/café notes.txt"
  printf '\000\001\002' > "$repo/binary.dat"
  local output
  output="$(QUILL_STDIN_CAPTURE="$capture" PATH="$(make_fake_bin)" "$ROOT/quill" --add --commit "$repo")"
  assert_contains "$(cat "$capture")" 'unicode content marker'
  assert_contains "$(cat "$capture")" 'renamed file.txt'
  assert_contains "$(cat "$capture")" 'binary.dat'
  assert_equals "$(git -C "$repo" status --porcelain)" ''
  [[ -f "$repo/café notes.txt" && -f "$repo/renamed file.txt" && ! -f "$repo/feature.txt" ]] || fail 'incorrect committed file set'
}

test_provider_failure_contracts
test_dependency_failures_preserve_installation
test_git_paths_and_change_types

test_clean_repo_reports_no_changes
test_codex_is_default_and_receives_git_context
test_default_prepares_and_prompts_for_action
test_prepare_mode_prepares_and_exits
test_quit_prints_without_preparing
test_staged_changes_use_staged_context_only
test_claude_provider_uses_configured_model
test_gemini_provider_uses_configured_model
test_config_overrides_default_provider_and_models
test_large_context_uses_parallel_batches_and_synthesis
test_single_oversized_file_splits_across_batches
test_batch_budget_is_selected_per_provider
test_commits_with_generated_message
test_commits_only_staged_changes_when_staged_changes_exist
test_commit_mode_fails_cleanly_without_staged_changes
test_add_flag_stages_all_changes_before_commit
test_add_flag_stages_before_generation
test_add_flag_stages_before_provider_check
test_commit_alias_commits_with_generated_message
test_copy_mode_copies_without_committing
test_copy_mode_supports_linux_clipboard_fallback
test_commit_push_pushes_staged_commit
test_yes_push_pushes_staged_commit
test_full_stages_commits_and_pushes_all_changes
test_short_flags_match_long_workflows
test_pr_flow_uses_selected_base_and_generated_content
test_pr_rejects_commit_workflow_flags
test_pr_scripted_validation
test_push_does_not_run_when_commit_has_no_staged_changes
test_push_failure_leaves_local_commit
test_interactive_push_pushes_only_after_commit_choice
test_interactive_push_does_not_push_after_quit_choice
test_push_rejects_non_commit_modes_before_generation
test_full_rejects_non_commit_modes_regardless_of_order
test_readme_documents_push_and_full_flags
test_install_copies_versioned_quill_package
test_version_script_supports_semantic_bumps
test_version_and_deploy_reject_multiple_bump_flags
test_deploy_help_documents_release_boundary

print -- "All tests passed"
