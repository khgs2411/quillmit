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
  print -r -- "$bin:$PATH"
}

make_dirty_repo() {
  local repo="$1"
  git init "$repo" >/dev/null
  print -r -- "hello" > "$repo/file.txt"
}

commit_editmsg_path() {
  local repo="$1"
  git -C "$repo" rev-parse --path-format=absolute --git-path COMMIT_EDITMSG
}

test_clean_repo_reports_no_changes() {
  local repo="$TMP_ROOT/clean"
  git init "$repo" >/dev/null

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
  git init "$repo" >/dev/null
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
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"

  PATH="$(make_fake_bin):$PATH" "$ROOT/quill" --yes "$repo" >/dev/null

  local subject
  subject="$(git -C "$repo" log -1 --pretty=%s)"
  [[ "$subject" == "Add terminal commit message helper" ]] || fail "unexpected commit subject: $subject"
  [[ -z "$(git -C "$repo" status --short)" ]] || fail "expected repo to be clean after commit"
}

test_commit_alias_commits_with_generated_message() {
  local repo="$TMP_ROOT/commit-alias"
  make_dirty_repo "$repo"
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
test_commit_alias_commits_with_generated_message
test_copy_mode_copies_without_committing
test_install_links_quill_only

print -- "All tests passed"
