#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quill-release-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
fail() { print -u2 -- "FAIL: $*"; exit 1; }
contains() { [[ "$1" == *"$2"* ]] || fail "expected: $2; got: $1"; }
fixture() {
  CASE="$TMP_ROOT/$1"
  mkdir -p "$CASE/repo/scripts" "$CASE/bin"
  cp "$ROOT/deploy" "$CASE/repo/deploy"
  cp "$ROOT/scripts/version" "$CASE/repo/scripts/version"
  print -- '1.2.3' > "$CASE/repo/VERSION"
  for file in test_quill.sh test_release.sh scripts/setup-deps; do
    print -r -- '#!/bin/zsh' > "$CASE/repo/$file"
  done
  : > "$CASE/repo/test_tui.py"
  cat > "$CASE/repo/quill" <<'SCRIPT'
#!/bin/zsh
set -eu
[[ "$*" == "--add --commit $PWD" ]] || exit 80
print -- commit >> "$RELEASE_CASE/events"
git add -A
git commit -qm 'Release fixture'
SCRIPT
  cat > "$CASE/repo/install" <<'SCRIPT'
#!/bin/zsh
set -eu
if [[ $# -gt 0 ]]; then
  print -- verify-package >> "$RELEASE_CASE/events"
  [[ "${FAIL_VERIFY:-0}" == 0 ]] || exit 1
  mkdir -p "$2"
  print -rl -- '#!/bin/sh' 'echo quill-fixture' > "$2/quill"
  chmod +x "$2/quill"
else
  [[ -f "$RELEASE_CASE/published" ]] || exit 81
  [[ "${FAIL_INSTALL:-0}" == 0 ]] || exit 1
  print -- install >> "$RELEASE_CASE/events"
fi
SCRIPT
  cat > "$CASE/bin/quill" <<'SCRIPT'
#!/bin/sh
exit 82
SCRIPT
  cat > "$CASE/bin/gh" <<'SCRIPT'
#!/bin/zsh
set -eu
[[ -z "${GH_REPO:-}" && "${GH_HOST:-}" == github.com ]] || exit 83
print -r -- "$*" >> "$RELEASE_CASE/gh-calls"
case "$1 $2" in
  'auth status') : ;;
  'repo view') print -- https://github.com/test/release ;;
  'api --include')
    [[ "$3" == repos/test/release/releases/tags/v* ]] || exit 84
    if [[ "${FAIL_LOOKUP:-0}" == 1 ]]; then print -- 'HTTP/2.0 403 Forbidden'; exit 1; fi
    if [[ -f "$RELEASE_CASE/published" ]]; then print -- 'HTTP/2.0 200 OK'; else print -- 'HTTP/2.0 404 Not Found'; exit 1; fi ;;
  'run list')
    [[ "$*" == *'--repo test/release'* && "$*" == *"--commit $(git rev-parse HEAD)"* && "$*" == *'--event push'* ]] || exit 85
    print -- 17 ;;
  'run watch')
    [[ "$*" == *'--repo test/release'* ]] || exit 86
    print -- ci >> "$RELEASE_CASE/events"
    [[ "${FAIL_CI:-0}" == 0 ]] || exit 1 ;;
  'release view')
    [[ "$*" == *'--repo test/release'* ]] || exit 87
    print -- false ;;
  'release create')
    [[ "$*" == *'--repo test/release'* && "$*" == *'--verify-tag'* ]] || exit 88
    [[ "$(git ls-remote origin "refs/tags/$3" | awk '{print $1}')" == "$(git rev-parse HEAD)" ]] || exit 89
    [[ "${FAIL_PUBLISH:-}" != before ]] || exit 1
    print -- publish >> "$RELEASE_CASE/events"
    touch "$RELEASE_CASE/published"
    [[ "${FAIL_PUBLISH:-}" != after ]] || exit 1 ;;
  *) exit 90 ;;
esac
SCRIPT
  chmod +x "$CASE/repo/"{deploy,install,quill} "$CASE/bin/"{gh,quill}
  git init -q -b master "$CASE/repo"
  git -C "$CASE/repo" config user.name 'Release Test'
  git -C "$CASE/repo" config user.email test@example.com
  git -C "$CASE/repo" add -A
  git -C "$CASE/repo" commit -qm Initial
  git init -q --bare "$CASE/remote.git"
  git -C "$CASE/repo" remote add origin "$CASE/remote.git"
  git -C "$CASE/repo" push -qu origin master
  cat > "$CASE/remote.git/hooks/pre-receive" <<'SCRIPT'
#!/bin/sh
[ "${FAIL_PUSH:-0}" = 0 ]
SCRIPT
  chmod +x "$CASE/remote.git/hooks/pre-receive"
  : > "$CASE/events"
}
run_release() {
  # Invoke from outside the checkout and with a conflicting caller GH_REPO.
  (cd "$TMP_ROOT" && RELEASE_CASE="$CASE" GH_REPO=wrong/repo PATH="$CASE/bin:$PATH" "$CASE/repo/deploy" "$@") > "$CASE/output" 2>&1
}
expect_failure() {
  if run_release "$@"; then fail 'expected release failure'; fi
}
count_event() { awk -v event="$1" '$0 == event {n++} END {print n+0}' "$CASE/events"; }

fixture prepared
print -- 1.3.0 > "$CASE/repo/VERSION"
run_release || { cat "$CASE/output"; fail prepared; }
[[ "$(cat "$CASE/repo/VERSION")" == 1.3.0 ]] || fail 'prepared version bumped again'
[[ "$(cat "$CASE/events")" == $'verify-package\ncommit\nci\npublish\ninstall' ]] || fail 'incorrect release ordering'
[[ ! -f "$CASE/repo/.git/quill-release/pending" ]] || fail 'state not cleared'

fixture committed-version
print -- change > "$CASE/repo/release-change"
run_release --no-bump || { cat "$CASE/output"; fail committed-version; }
[[ "$(cat "$CASE/repo/VERSION")" == 1.2.3 ]] || fail 'explicit version bumped'
[[ "$(git --git-dir="$CASE/remote.git" rev-parse refs/tags/v1.2.3)" == "$(git -C "$CASE/repo" rev-parse HEAD)" ]] || fail 'explicit version tag mismatch'

fixture clean-committed-version
run_release --no-bump || { cat "$CASE/output"; fail clean-committed-version; }
[[ "$(count_event commit)" == 0 && "$(count_event publish)" == 1 ]] || fail 'clean committed release made a redundant commit'
[[ "$(cat "$CASE/repo/VERSION")" == 1.2.3 ]] || fail 'clean committed version bumped'

fixture preflight
FAIL_LOOKUP=1 expect_failure
[[ "$(cat "$CASE/repo/VERSION")" == 1.2.3 ]] || fail 'preflight changed VERSION'
[[ ! -f "$CASE/repo/.git/quill-release/pending" ]] || fail 'preflight created pending release'
contains "$(cat "$CASE/output")" 'Could not determine'

fixture verification
FAIL_VERIFY=1 expect_failure
[[ "$(count_event commit)" == 0 && "$(count_event install)" == 0 ]] || fail 'verification failure changed live state'
expect_failure
contains "$(cat "$CASE/output")" '--resume'
run_release --resume || { cat "$CASE/output"; fail verification-resume; }
[[ "$(cat "$CASE/repo/VERSION")" == 1.2.4 ]] || fail 'resume bumped version'

fixture push
FAIL_PUSH=1 expect_failure
release_head="$(git -C "$CASE/repo" rev-parse HEAD)"
[[ "$(count_event commit)" == 1 && "$(count_event install)" == 0 ]] || fail 'push failure boundary'
run_release --resume || { cat "$CASE/output"; fail push-resume; }
[[ "$(git -C "$CASE/repo" rev-parse HEAD)" == "$release_head" && "$(count_event commit)" == 1 ]] || fail 'push resume made another commit'

fixture ci
FAIL_CI=1 expect_failure
[[ "$(count_event publish)" == 0 && "$(count_event install)" == 0 ]] || fail 'CI failure published or installed'
[[ -z "$(git --git-dir="$CASE/remote.git" tag)" ]] || fail 'CI failure created tag'
print -- changed > "$CASE/repo/new-file"
expect_failure --resume
contains "$(cat "$CASE/output")" 'clean checkout'
rm "$CASE/repo/new-file"
run_release --resume || { cat "$CASE/output"; fail ci-resume; }
[[ "$(count_event commit)" == 1 ]] || fail 'CI resume made another commit'

fixture publication
FAIL_PUBLISH=after expect_failure
[[ "$(count_event install)" == 0 ]] || fail 'uncertain publication installed locally'
run_release --resume || { cat "$CASE/output"; fail publication-resume; }
[[ "$(count_event publish)" == 1 && "$(count_event install)" == 1 ]] || fail 'publication repeated on resume'

fixture installation
FAIL_INSTALL=1 expect_failure
run_release --resume || { cat "$CASE/output"; fail installation-resume; }
[[ "$(count_event publish)" == 1 && "$(count_event commit)" == 1 ]] || fail 'install resume repeated publication'

fixture interrupted-commit
FAIL_PUSH=1 expect_failure
# Simulate interruption after Git committed but before the commit ID was saved.
state="$CASE/repo/.git/quill-release/pending"
awk 'NR == 3 { print ""; next } {print}' "$state" > "$state.tmp"
mv "$state.tmp" "$state"
run_release --resume || { cat "$CASE/output"; fail interrupted-commit-resume; }
[[ "$(count_event commit)" == 1 ]] || fail 'interrupted commit duplicated'

fixture publication-before
FAIL_PUBLISH=before expect_failure
run_release --resume || { cat "$CASE/output"; fail publication-before-resume; }
[[ "$(count_event publish)" == 1 && "$(count_event commit)" == 1 ]] || fail 'tag recovery duplicated release'

fixture tag-conflict
FAIL_CI=1 expect_failure
base="$(git -C "$CASE/repo" rev-parse HEAD^)"
git --git-dir="$CASE/remote.git" update-ref refs/tags/v1.2.4 "$base"
expect_failure --resume
contains "$(cat "$CASE/output")" 'does not match'
[[ "$(count_event publish)" == 0 ]] || fail 'mismatched tag published'


fixture changed-target
FAIL_PUSH=1 expect_failure
before="$(git -C "$CASE/repo" rev-parse HEAD)"
git clone -q --bare "$CASE/remote.git" "$CASE/other.git"
git -C "$CASE/repo" remote set-url origin "$CASE/other.git"
expect_failure --resume
contains "$(cat "$CASE/output")" 'Pending release target differs'
[[ "$(git -C "$CASE/repo" rev-parse HEAD)" == "$before" && "$(count_event publish)" == 0 ]] || fail 'changed target accepted'

fixture changed-commit
FAIL_PUSH=1 expect_failure
print -- additional > "$CASE/repo/additional"
git -C "$CASE/repo" add additional
git -C "$CASE/repo" commit -qm Additional
before="$(git -C "$CASE/repo" rev-parse HEAD)"
expect_failure --resume
contains "$(cat "$CASE/output")" 'Resume requires a clean checkout'
[[ "$(git -C "$CASE/repo" rev-parse HEAD)" == "$before" && "$(count_event publish)" == 0 ]] || fail 'changed commit accepted'

fixture locked
mkdir -p "$CASE/repo/.git/quill-release/lock"
expect_failure
contains "$(cat "$CASE/output")" 'Another deploy may be running'
[[ -d "$CASE/repo/.git/quill-release/lock" && ! -s "$CASE/events" ]] || fail 'competing release changed state'
[[ "$(cat "$CASE/repo/VERSION")" == 1.2.3 ]] || fail 'competing release bumped version'

print -- 'All release tests passed'
