# Releasing Quillmit

## Commands and responsibilities

| Command | Effect |
| --- | --- |
| `./scripts/version [--patch\|--minor\|--major]` | Changes `VERSION` only. Defaults to patch. |
| `./install` | Installs the declared version locally. Does not commit or publish. |
| `./deploy [--patch\|--minor\|--major]` | Verifies, commits all changes, pushes, publishes, then installs locally. |
| `./deploy --no-bump` | Publishes the current VERSION; uses HEAD directly if the checkout is clean. |
| `./deploy --resume` | Continues the pending release with the same version and commit. |

A release is a GitHub release and a tag pointing to the commit that passed CI.
GitHub provides source archives. There are no uploaded platform packages;
installation downloads the pinned fzf binary and checks its recorded checksum.

## Before starting

- Use `master`, with its HEAD equal to `origin/master`.
- Review every staged, unstaged, and untracked file. Deployment includes all of them
  except ignored files. Use `git status --short` and `git diff HEAD`.
- Authenticate `gh` for the GitHub.com repository configured as `origin`.
  Fetch and push URLs for `origin` must match.
- Install and authenticate the configured AI CLI. The checkout's `./quill`
  generates the release commit message; a global `quill` is not required.
- Ensure the normal install paths are writable and there is network access.
- Install Python 3.9 or later and provide pseudo-terminal access for terminal tests.
- Provide zsh, Git, curl, tar, and `sha256sum` or `shasum` for package setup.
- Verify the feature manually where automated checks are insufficient.

## Select the version once

If `VERSION` is already committed but has no remote tag or GitHub release,
`./deploy` keeps it. A clean checkout releases HEAD directly.
If that version already has a remote tag or release, `./deploy` increments the patch version.
Use `--minor` or `--major` for a different increment.

If you already changed `VERSION` to a newer version, run `./deploy` without a
bump flag. It uses that prepared version. A bump flag with an already changed
`VERSION` is rejected. For example, a checkout prepared as `0.5.0` remains
`0.5.0`; deployment does not increment it again.

```sh
./deploy
# Or, when VERSION has not already changed:
./deploy --minor
```

To require the current version explicitly, use `--no-bump`:

```sh
./deploy --no-bump
```

This publishes the current `VERSION` only when it has no remote tag or release.
Version `0.5.0` is already published. From that release, plain `./deploy` selects
`0.5.1`; `./deploy --no-bump` stops because `v0.5.0` already exists.
If the checkout is clean, it releases HEAD without an extra commit.
If there are changes, it commits them after verification.
An existing remote tag or release still blocks a new release attempt.
After a failed attempt, use `--resume` without `--no-bump`.

## Execution order

1. Verify the branch, remote identity, remote HEAD, tag, and release availability.
2. Record the selected version and base commit under `.git/quill-release/pending`.
3. Write `VERSION` and run `./scripts/check --live`: syntax, all deterministic
   suites, real fzf terminal tests, and real AI worktree smoke tests. Then verify
   an isolated installation. Any failure stops before the normal launcher changes.
4. Use the checkout's `./quill --add --commit` to commit all working-tree changes.
   For an unpublished prepared version and a clean checkout, reuse HEAD.
5. Push that commit explicitly to `origin/master`.
6. Wait for the `test.yml` push workflow for that exact commit to pass. CI also
   downloads the private dependency and runs the real terminal tests.
7. Create the remote tag if absent. Verify that its resolved commit matches the
   release commit, including annotated tags.
8. Publish with an explicit repository and `--verify-tag`.
9. Install the published version locally and clear the pending record.

The installer verifies the dependency before switching the launcher. It removes
previous recognized packages after switching. Publication stays successful if
local installation fails; resume completes that installation.

## Recover a failed release

Fix the reported cause, then use:

```sh
./deploy --resume
```

Resume rechecks the target, full test gate (including paid AI usage), package,
and CI. It does not bump the version or make another release commit. Before a
release commit exists, you can fix working-tree files and resume. After it exists, the checkout must be clean at that commit.
An interruption immediately after the commit can be recovered when HEAD is the
single clean child of the recorded base commit.

| Failure | Recovery |
| --- | --- |
| Preflight/authentication/network | Fix access and retry the original command if no pending record exists. |
| Syntax, tests, isolated install, or AI generation | Fix the cause and use `--resume`. Preserve the selected VERSION. |
| Push | Fix Git access and use `--resume`; the release commit remains local. |
| CI unavailable or failed | Inspect the run. Rerun a transient CI failure, then resume. Code changes require a new release attempt. |
| Tag points to another commit | Stop and inspect the remote tag. Deployment will not move it. |
| Publication response is uncertain | Resume checks the release and tag before creating anything again. |
| Existing draft release | Resolve the draft deliberately, then resume. Deployment does not overwrite it. |
| Local install after publication | Fix the install error and resume. The published release remains valid. |
| Remote master advanced | Inspect both commits. Deployment will not force-push or select a different commit. |

The pending file contains five lines: version, base commit, release commit
(empty before commit), origin URL, and GitHub repository. It is local Git metadata
and is never included in a commit. Do not edit it to bypass a target mismatch.

To abandon an attempt, first stop any running deploy process and inspect the
checkout, remote branch, tag, and GitHub release. Then remove only the pending
record using the path from:

```sh
git rev-parse --path-format=absolute --git-path quill-release/pending
```

Removing that record does not undo a commit, push, tag, publication, or install.
Preserve existing work. If a release was already published, use a new version for
further changes. If a commit was never pushed, resolve that local/remote difference
before starting again. Never reuse a tag for different release contents.

If the process was killed and left a lock, confirm that no deploy process remains.
Then remove the empty lock directory at the path reported by:

```sh
git rev-parse --path-format=absolute --git-path quill-release/lock
```

Normal exits remove this lock automatically. Do not remove a live process's lock.

## Confirm completion

```sh
quill --version
git status --short
```

Check that the command reports the published version and the checkout is clean.
Inspect the release and its tag on GitHub. Deployment verifies that the tag points
to the exact commit that passed CI before publication.

For installation and command failures, see [Troubleshooting](troubleshooting.md).
For test setup, see [Contributing](../CONTRIBUTING.md).
