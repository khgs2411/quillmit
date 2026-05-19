# Push and Full Flags Design

## Source

- Issue: [TOP-550](/TOP/issues/TOP-550) asks for `--push`, which runs `git push`, and `--full`, equivalent to `quill --add --commit --push`.
- Design gate issue: [TOP-551](/TOP/issues/TOP-551) asks for a repository-grounded design covering CLI surface, execution order, failure behavior, push guardrails, tests, and verification.
- Existing implementation: `quill` is a single zsh executable with one argument parser (`quill:26-80`), one `MODE` variable (`quill:14`), an `ADD_ALL` modifier (`quill:17`), staged/all-changes context selection (`quill:142-148`), and focused helper functions for provider execution, preparation, copying, and committing (`quill:267-364`).
- Existing commit behavior: `commit_message` stages only when `ADD_ALL=1`, fails clearly when no staged changes exist, and commits with `git -C "$REPO" commit -F "$MESSAGE_FILE"` (`quill:323-335`).
- Existing tests: `test_quill.sh` is a shell-only suite built around temporary Git repositories and fake provider CLIs (`test_quill.sh:25-107`), with coverage for staged-only commits, clean commit failure, `--add --commit`, copy behavior, and README-visible workflows (`test_quill.sh:249-383`).
- README contract: Quillmit is local, dependency-light, and explicit about when it commits (`README.md:3-8`); it documents staged-first generation and commit-only-staged behavior unless `--add` is present (`README.md:92-125`).
- Git history: `581896c Commit only staged changes by default and add explicit --add behavior` established the current staged-first workflow and added tests for it.
- Style guidance: llm-wiki `code-style` pages `false-seams-and-wrapper-noise`, `type-and-interface-boundaries`, `controller-boundaries`, `lifecycle-and-runtime-state`, and `repositories-and-helpers` recommend the smallest honest shape, avoiding wrapper-only helpers, keeping side-effect ownership near the lifecycle owner, and testing input validation, side-effect guardrails, failure sequencing, and concrete workflow behavior.

## Problem

Quillmit already supports generating a commit message, optionally staging all changes with `--add`, committing with `--commit` or interactive `[c]ommit`, copying, preparing, and quitting. It does not yet push commits. The requested `--full` command should provide a one-command path for the existing "stage everything, generate, commit" workflow plus a push.

The design must preserve the current staged-first behavior from the latest commit: commit actions commit only staged files unless `--add` is present, while `--add` expands both generation context and commit staging to all changed files.

## Assumptions

Assumption: `--push` is a post-commit modifier, not a standalone `git push` shortcut -- chosen because `--full` is defined as `--add --commit --push`, and current Quillmit modes revolve around generating and optionally committing a message; revisit if Vesta or the source issue requires `quill --push` to push an already-clean repository without generating or committing.

Assumption: `git push` should use Git's default push target with no extra arguments -- chosen because the issue only asks to run `git push`, and adding remote/branch/upstream flags would broaden side effects; revisit if users need first-push upstream setup.

Assumption: a successful local commit must not be rolled back when push fails -- chosen because Git push can fail for remote/network/policy reasons after a valid local commit, and automatic rollback would be a larger destructive behavior; revisit only if product policy requires all-or-nothing commit/push semantics.

## Approaches Considered

### Recommended: `--push` as a Commit Modifier

Add a `PUSH_AFTER_COMMIT=0` flag beside `ADD_ALL`. Parse `--push` as `PUSH_AFTER_COMMIT=1`, and parse `--full` as `ADD_ALL=1`, `MODE="commit"`, and `PUSH_AFTER_COMMIT=1`. Keep `commit_message` as the side-effect owner: it stages when `ADD_ALL=1`, validates staged changes, commits, and then calls a small `push_commits` helper only after `git commit` succeeds.

This is the smallest change that matches the current structure. It keeps the push lifecycle next to the existing commit side effect and leaves provider generation, prepare, copy, and quit behavior untouched.

### Alternative: Add a Separate Push Mode

Treat `--push` like `--copy` or `--quit` by setting `MODE="push"`. This makes `quill --push` push directly, but it does not compose cleanly with `--commit`; in the current parser, modes are mutually overwriting. Supporting `quill --commit --push` would require a larger mode/action refactor and would make `--full` less naturally equivalent to the requested flag combination.

### Alternative: Refactor Into an Action Pipeline

Replace `MODE` with an ordered action list such as `generate`, `prepare`, `commit`, `push`, `copy`. This would model composition cleanly, but it is too broad for two flags in a dependency-light shell script. It introduces abstraction before there is enough repeated complexity.

## CLI Surface

Update usage text to include:

```text
Usage: quill [--codex|--claude|--gemini|--provider name] [--config file] [--prepare|--commit|--copy|--quit|--add|--push|--full|--verbose] [repo]
```

Add parser cases:

- `--push`: set `PUSH_AFTER_COMMIT=1`.
- `--full`: set `ADD_ALL=1`, `MODE="commit"`, and `PUSH_AFTER_COMMIT=1`.

Document:

- `quill --commit --push`: generate a message, commit staged changes, then run `git push`.
- `quill --add --commit --push`: generate from all changed files, stage all changes, commit, then run `git push`.
- `quill --full`: alias for `quill --add --commit --push`.
- `quill --push` in default interactive mode: generate and prepare as usual, then push only if the user chooses `[c]ommit`.

Guard invalid combinations before generation:

- `--push --prepare`, `--push --copy`, and `--push --quit` should exit nonzero with a clear message because no commit action will run.
- `--full` should not be combined with `--prepare`, `--copy`, or `--quit`; if this is detected, exit nonzero with a clear message instead of silently ignoring flags.
- Existing `--yes` remains an alias for `--commit`, and therefore supports `--yes --push`.

Keep positional repo handling unchanged: the final non-flag argument is still treated as `REPO_INPUT`.

## Execution Order

For ordinary modes without push, behavior stays the same.

For `quill --commit --push`:

1. Parse flags and repo argument.
2. Resolve config and provider.
3. Resolve `REPO` with `git -C "$REPO_INPUT" rev-parse --show-toplevel`.
4. Preserve the current early clean-repo exit: if there are no changes, print `No changes to commit in $REPO` and exit 0 without pushing.
5. Select generation context using the current `ADD_ALL` and staged-first rules.
6. Generate and show the commit message.
7. Run `commit_message`.
8. Inside `commit_message`, stage with `git -C "$REPO" add -A` only when `ADD_ALL=1`.
9. If no staged files remain, print the existing clean failure and return nonzero without pushing.
10. Run `git -C "$REPO" commit -F "$MESSAGE_FILE"`.
11. Only if commit succeeds and `PUSH_AFTER_COMMIT=1`, run `git -C "$REPO" push`.

For `quill --full`, the order is the same as `quill --add --commit --push`. Generation context must be `all changed files`, matching the existing `--add` behavior.

For default interactive mode with `--push`, generation and preparation occur as they do today. The push runs only if the user chooses `c` or `commit`; edit, copy, regenerate, quit, and empty input do not push.

## Failure Behavior

Provider generation failure remains unchanged: report the provider log path and exit nonzero before any commit or push.

Commit failure remains the boundary before push. If `git commit` fails, return nonzero and do not run `git push`.

Push failure should:

- let `git push` write its normal stdout/stderr so users see the remote/upstream/network error;
- print one concise follow-up line such as `Push failed. Commit remains local.`;
- return nonzero from `commit_message`, which makes non-interactive `--commit --push` and `--full` exit nonzero;
- leave the local commit intact.

Clean-repo behavior remains unchanged. Because `--push` is a post-commit modifier under this design, `quill --push` or `quill --commit --push` on a clean working tree exits with the existing no-changes message and does not push.

## Git Push Guardrails

The implementation must not:

- run `git push` before a successful `git commit`;
- run `git push` for `--prepare`, `--copy`, `--quit`, or non-commit interactive choices;
- auto-stage files unless `--add` or `--full` is present;
- pass `--force`, `--force-with-lease`, `--tags`, `--set-upstream`, a remote, or a branch to `git push`;
- retry push failures;
- suppress Git's own push diagnostics;
- roll back successful local commits after push failure.

The implementation may print a short progress/status line before pushing, but it should avoid hiding Git output behind the existing provider spinner or log file. Push is a direct Git side effect, not provider output.

## Implementation Shape

Make the change in `quill` only:

- add `PUSH_AFTER_COMMIT=0` near `ADD_ALL=0`;
- parse `--push` and `--full`;
- add early validation for contradictory push/full combinations;
- add a focused `push_commits` helper that owns exactly `git -C "$REPO" push` plus the failure message;
- call `push_commits` from `commit_message` after `git commit -F "$MESSAGE_FILE"` succeeds.

Avoid broad refactors. Do not split the script, introduce an action framework, or change provider handling. Keep README changes limited to usage and examples for the new flags.

## Test Design

Extend `test_quill.sh` with temporary repositories and fake provider CLIs, matching the existing suite style.

Add tests for:

- `--commit --push` commits staged changes and pushes the resulting commit to a bare remote.
- `--full` stages an unstaged change, commits it, and pushes it to a bare remote.
- `--push` does not run when commit mode fails because there are no staged changes.
- a push failure after a successful commit exits nonzero, leaves the commit local, and reports that the commit remains local.
- interactive `quill --push` pushes only after the user selects `c`, and does not push when the user chooses `q`.
- invalid combinations such as `--copy --push` and `--full --quit` fail before provider generation with a clear message.
- README-visible usage includes `--push` and `--full`.

The bare-remote tests should configure `user.email`, `user.name`, a branch, and a local remote in the temp repo. They should inspect the bare remote with `git --git-dir "$remote" log -1 --pretty=%s` or equivalent, avoiding any network dependency.

## Verification

Minimum verification for implementation:

```sh
zsh test_quill.sh
```

Targeted manual smoke checks after the test suite:

```sh
tmp="$(mktemp -d)"
git init --bare "$tmp/remote.git"
git clone "$tmp/remote.git" "$tmp/work"
cd "$tmp/work"
git config user.email test@example.com
git config user.name "Test User"
print -r -- hello > file.txt
quill --full
git --git-dir "$tmp/remote.git" log -1 --pretty=%s
```

The smoke should show the generated commit subject in the bare remote. It should not require a real provider in automated tests because the test suite uses fake provider CLIs.

## Out Of Scope

- Setting upstream branches automatically.
- Supporting push arguments, remote selection, branch selection, tags, or force pushes.
- Reworking all modes into a generalized action pipeline.
- Changing commit message generation prompts.
- Changing the staged-first semantics introduced by the latest commit.
