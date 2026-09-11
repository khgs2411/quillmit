# Troubleshooting Quillmit

Start with the version and executable your shell uses:

```sh
command -v quill
quill --version
```

An installed package is separate from a source checkout. Use `./quill --version`
inside the checkout to check its version. See [installation instructions](../README.md#install-or-update).

## Command or TUI dependency is missing

If the default launcher is outside `PATH`, add its directory:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Keep that line in your shell configuration. Check old aliases if your shell
still runs another copy.

For a source checkout, run `./scripts/setup-deps` before interactive PR or
worktree creation. For an installed release, rerun its installer. Quillmit uses
its private fzf binary; installing a global fzf does not repair the package.
If dependency download or checksum verification fails, check network access and
use an unchanged published release. Do not bypass the checksum check.

If the installer reports an unrecognized launcher, inspect that file before
moving or removing it. If it reports modified package files, preserve your edits
and configuration before resolving the conflict. It does not overwrite them.

## Provider generation fails

Run the selected provider CLI directly to check authentication and model access.
Confirm the configuration with `--config /absolute/path/to/quill.config`.
Source and installed configurations are separate copies.

Use `quill --verbose` to show provider output. The error message gives the log
path. Logs normally use `${XDG_CACHE_HOME:-$HOME/.cache}/quill/last.log`, with
`${TMPDIR:-/tmp}/quill/last.log` as the fallback. Preserve relevant diagnostics
before another invocation replaces them. Redact logs before sharing them.

A usage-limit response can trigger the configured fallback model. Other provider
failures do not trigger fallback. See [configuration](../README.md#config).

## A commit succeeds but push fails

The local commit remains. Inspect the branch and intended remote:

```sh
git status -sb
git remote -v
```

After resolving access or network errors, retry with `git push`. If this is a new
branch without an upstream, select the intended remote and set its upstream;
for example, `git push --set-upstream origin HEAD`.

`quill -f` does not push existing commits from a clean working tree. It pushes
only after creating a new commit.

## PR creation requires a terminal

Interactive selection and approval need terminal input and output. For scripted
use, supply the remote and base, then explicitly skip approval:

```sh
quill pr --remote origin --base master --no-preview
```

Replace `master` with a branch on the selected remote. Authenticate GitHub CLI
with access to the repository. The PR includes committed `base...HEAD` changes;
uncommitted files do not appear in it. Esc from the preview returns to branch
selection. Ctrl-C cancels.

## Worktree creation stops

- Without a remote, supply `--from HEAD` or another local commit reference.
  A repository needs an initial commit first.
- If several remotes exist without `origin`, select one with `--remote name`.
- If AI returns an invalid proposal, retry or supply `--branch name`.
- If the branch or destination already exists, inspect `quill worktree list`.
  Creation requires a new branch and unused destination.
- If `.worktrees` or the root `.gitignore` fails validation, inspect the reported
  path. Quillmit refuses unsafe layouts such as a symlink at either location.

Example with an explicit branch and starting point:

```sh
quill worktree create --branch fix/parser --from HEAD --no-preview
```

Creation adds the main checkout's ignore rule without staging it. Review and
commit that `.gitignore` change through your normal workflow.

## Worktree removal stops

Run `quill worktree list` and inspect the reported blocking paths. Commit or
preserve pending work. Ignored files, including `.env` and build output, also
block removal. Copy valuable files elsewhere before removing them deliberately.

Without a branch or path, `quill worktree remove` selects the linked worktree
that contains the current directory. From the main checkout, it stops because
the main worktree cannot be removed. Use an explicit branch or path to remove a
different linked worktree.

Complete or resolve active Git operations. Inspect a lock before unlocking it.
Quillmit does not remove the main checkout or a detached worktree.

When any remote exists, the branch needs a remote upstream. Removal fetches that
upstream and requires every local commit to be reachable from it. Fix access,
missing upstream, or unpushed history before retrying. The list command shows
cached status; removal checks the remote again.

In a repository without remotes, a clean worktree attached to a local branch can
be removed. Removal preserves that branch and its commits. Do not remove a remote
just to bypass a failed push check. There is no force-removal option.

## Deployment stops

If a pending release exists, fix the reported cause and run `./deploy --resume`.
Do not run another version bump. Resume reruns the full test gate, including
real AI usage. After the release commit exists, resume requires a clean checkout
at that commit.

Use the [release recovery guide](releasing.md#recover-a-failed-release) for CI,
tag conflicts, locks, uncertain publication, and installation failures.
