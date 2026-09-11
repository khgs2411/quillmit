# Quillmit

Terminal-first commit message helper powered by your existing AI subscriptions.

Quillmit turns your current Git diff into a useful commit message by using the
AI CLIs you already pay for: Codex by default, with optional Claude Code and
Gemini CLI support. It stays local, dependency-light, and explicit about when it
commits.

The command is:

```sh
quill
```

The project is Quillmit. The executable is `quill`.

## Features

- Uses your local AI CLI subscriptions instead of a separate hosted service.
- Supports Codex, Claude Code, and Gemini CLI.
- Supports a fallback model for each provider when the primary model reaches a usage limit.
- Reads staged changes first; if nothing is staged, reads the working tree.
- Stages all changes immediately when `--add` or `--full` is passed.
- Commits only staged changes.
- Provides `-a`, `-c`, `-p`, and `-f` aliases for common commit workflows.
- Creates AI-written pull requests with searchable branch selection and approval previews.
- Prepares `.git/COMMIT_EDITMSG` by default.
- Copies messages with `pbcopy`, `wl-copy`, `xclip`, or `xsel`.
- Keeps provider transcripts hidden unless `--verbose` is enabled.
- Avoids noisy conventional commit prefixes like `feat(scope):` and `chore:`.
- Has a shell-only test suite with fake provider CLIs.

## Requirements

At least one provider CLI must be installed and authenticated:

- Codex CLI for the default provider.
- Claude Code CLI for `--claude`.
- Gemini CLI for `--gemini`.

Quillmit does not install or authenticate provider CLIs for you.

The `quill pr` workflow also requires an installed and authenticated GitHub CLI
(`gh`).

Quillmit manages its own pinned [fzf](https://github.com/junegunn/fzf) dependency
for the PR interface. The installer downloads the platform binary, checks its
SHA-256 checksum against `third-party/fzf.lock`, and includes it and its license
inside the installed Quillmit version. No global fzf installation is required.
Dependency downloads require `curl`, `tar`, and `sha256sum` or `shasum`.
The packaged TUI supports macOS and Linux on ARM64 and x86-64.

## Compatibility

| Platform | Status | Notes |
| --- | --- | --- |
| macOS | Supported | Uses `pbcopy` for `--copy`. |
| Linux | Best effort | Uses `wl-copy`, `xclip`, or `xsel` for `--copy`. |
| Windows | Not supported | WSL may work if provider CLIs and clipboard tools are available. |

## Demo

```text
$ quill
Generating commit message with Codex |
Generated commit message with Codex.

Generated commit message:
-------------------------
Add provider-aware commit message preparation

Route the current Git context through the selected AI CLI and keep provider
output quiet by default.
Prepare COMMIT_EDITMSG before prompting so normal git commit remains available.
Support commit, copy, regenerate, and quit actions from the terminal flow.
-------------------------
Prepared commit message at /path/to/repo/.git/COMMIT_EDITMSG
[c]ommit, [e]dit, co[p]y, [r]egenerate, [q]uit:
```

## Install or update

Install a published version from the [releases page](https://github.com/khgs2411/quillmit/releases/latest).
Choose its tag, then replace `vX.Y.Z` below with that tag:

```sh
git clone --branch vX.Y.Z --depth 1 https://github.com/khgs2411/quillmit.git
cd quillmit
./install
```

You can also download and extract **Source code (tar.gz)** from that release,
then run `./install` in the extracted directory. GitHub releases provide source
archives; the installer downloads the pinned fzf binary for your platform.
You need `zsh`, `git`, `curl`, `tar`, and `sha256sum` or `shasum`.

The installer creates a private package at
`${XDG_DATA_HOME:-~/.local/share}/quillmit/versions/<version>/` and a launcher at
`~/.local/bin/quill`. The command works independently of the source checkout.
Add the launcher directory to your shell's `PATH` if needed:

```sh
export PATH="$HOME/.local/bin:$PATH"
quill --version
```

Put the `export` line in `~/.zshrc` to keep it for future zsh sessions.

To update, download or clone the new release into a new directory and run its
installer. The installer verifies the dependency checksum before it switches
the launcher. It then removes older recognized Quillmit packages. It preserves
unrecognized directories. Keep personal configuration outside the packages;
see [Configuration](#config).

Reinstalling the same release repairs its launcher. If installed files differ,
the installer stops instead of overwriting them. Every install currently needs
network access for dependency verification, including a reinstall.

Custom locations, including relative paths, are supported:

```sh
./install --bin-dir /path/on/PATH --install-root /path/for/quillmit-packages
```

The installer refuses to replace a command that it does not recognize as a
Quillmit launcher. Resolve that conflict before installing. A failed install
leaves the existing launcher in place; fix the reported cause and run it again.

## Uninstall or return to an older release

For the default locations, first confirm that the following paths contain your
Quillmit launcher and packages. Then remove them:

```sh
rm "$HOME/.local/bin/quill"
rm -r "${XDG_DATA_HOME:-$HOME/.local/share}/quillmit"
```

For a custom installation, use the paths passed to `--bin-dir` and
`--install-root`. Personal configuration and logs are separate and remain in
place. Remove any shell alias you created for Quillmit.

To return to an older release, download that release and run its installer.
Older installers may have different dependency requirements. The current
installer does not retain previous packages for offline rollback.

## Development and releases

Use `./quill` to run the source checkout. Changes in the checkout do not update
an installed copy. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and checks.

Maintainers use `./deploy` to commit and publish all working-tree changes.
It runs all tests, including live AI smoke tests, verifies an isolated install,
waits for CI, publishes the release, then
updates the local installation. `./deploy --resume` continues a failed release.
See the [release guide](docs/releasing.md) for version selection, prerequisites,
publication boundaries, and recovery.

Plain `./deploy` keeps a prepared version, including a committed version with no
remote tag or GitHub release. `./deploy --no-bump` requires the current version. See [the release guide](docs/releasing.md) for version selection and recovery.

## Usage

```sh
quill
```

Run it from a Git repository. Quillmit reads the Git state locally, asks the
selected provider to write a medium-sized commit message from that context,
previews it, prepares `.git/COMMIT_EDITMSG`, then asks what to do next.

If files are staged, Quillmit generates the message from staged changes only.
If nothing is staged, it generates from the changed working tree.
Commit actions only commit staged changes by default.

When the Git context exceeds the selected provider's configured prompt budget,
Quillmit groups complete file diffs into bounded batches, summarizes those
batches in parallel, and makes one final provider call to synthesize the commit
message. A single file larger than a batch is split at diff-hunk boundaries,
with a byte-bounded fallback for an individual oversized hunk.

By default it uses Codex. Other providers:

```sh
quill --claude
quill --gemini
quill --provider codex
```

For a specific repo:

```sh
quill /absolute/path/to/repo
```

For non-interactive commit after preview:

```sh
quill -c
quill -c -p
```

`--commit`, `--push`, and `--yes` remain accepted for compatibility and scripts.

To stage all changes before committing:

```sh
quill -a -c
quill -a -c -p
quill -f
```

`-a` is the short form of `--add`. It stages everything before generating the
commit message, even in interactive or non-commit modes. `-f` is the short form
of `--full`; both are equivalent to `quill --add --commit --push`.

`-p` is the short form of `--push`. It runs `git push` only after a successful
local commit. In interactive mode, `quill -p` pushes only if you choose
`[c]ommit`. Push failures leave the local commit in place.

The equivalent long-form commands remain available:

```sh
quill --commit --push
quill --add --commit --push
quill --full
```

To create a pull request:

```sh
quill pr
```

Quillmit fetches the selected remote and opens a searchable base-branch list.
Type to filter the branches. Use the arrow keys or click to select a branch,
then press Enter or double-click to continue. Press Esc to cancel.

Quillmit generates a title and Markdown description from the committed
`base...HEAD` changes, then shows a scrollable preview with the source and target.
Use the arrow keys, Page Up/Page Down, or the mouse wheel to scroll. Press Enter
to approve and create the PR. Press Esc to choose another branch and generate
new content. Press Ctrl-C to cancel. This workflow requires an interactive
terminal when selection or approval is needed. Piped numeric selections are
not supported.

For scripted use, provide the target and explicitly skip approval:

```sh
quill pr --remote origin --base master --no-preview
```

`--base` skips branch selection. `--remote` skips remote selection; it is optional
when the repository has only one remote. `--no-preview` approves PR creation
without displaying the preview. Omit it to review the generated content in the
TUI. Fully scripted use does not require a terminal or fzf. The branch must exist
on the selected remote and have commits to compare with the current branch.
If you press Esc from a preview, branch selection opens even when `--base` was
provided. Provider flags and the optional repository path work in both modes.

After approval, Quillmit calls `gh pr create`, assigns the pull request to you, and lets
GitHub CLI push or fork the head branch when necessary. Uncommitted changes are
not included. Provider and configuration flags remain available, for example
`quill pr --claude` or `quill pr --config /path/to/quill.config`.

To generate, preview, copy the message, and exit without committing:

```sh
quill --copy
```

`--copy` also prepares `.git/COMMIT_EDITMSG`.

To prepare and exit immediately:

```sh
quill --prepare
```

To print only and skip preparing:

```sh
quill --quit
```

To show the provider transcript while debugging:

```sh
quill --verbose
```

## Worktrees

Describe the task to create a linked worktree:

```sh
quill worktree create "fix retries when PR creation fails"
quill worktree list
quill worktree remove fix/pr-retries
```

Quillmit asks your configured AI provider to propose a branch name and explain
its choice. It supplies branch names, registered worktrees, and the first 120
lines of the main root's `AGENTS.md`, when present. Ignored file contents are not
collected. If an existing linked worktree looks relevant, the preview offers
**Use existing worktree** and prints its path without changing it.

The preview shows the proposed branch, exact starting commit, and destination.
Use arrows or a mouse click to select an action, then Enter to approve it.
Esc edits the task description. Regenerate requests another proposal. Ctrl-C or
Cancel stops without changing `.gitignore` or creating a branch or worktree.
Provider options such as `--claude`, `--provider`, and `--config` also apply.

New worktrees live at `<main-worktree>/.worktrees/<branch>`. A branch such as
`fix/retries` uses nested directories. Calls from a linked worktree still use
the main checkout's directory. On creation, Quillmit adds `/.worktrees/` to the
main root's `.gitignore`, creating that file when needed. Existing contents are
preserved. The change is not staged or committed. Git manages all worktree links.
The worktree starts with committed files; local edits and ignored files are not copied.

By default, Quillmit fetches the remote's default branch and starts from that
commit. It uses `origin`, or the only remote. If there are several remotes and no
`origin`, specify `--remote name`. The new branch does not track the base branch.
Set its own upstream when you first push it.

For an explicit starting point or a repository without remotes:

```sh
quill worktree create "fix local import" --from HEAD
quill worktree create "extend parser" --from feature/parser
```

`--from` resolves an existing local ref or commit without fetching it. The
repository must have at least one commit. Bare repository layouts are not supported.

For scripted creation, supply the branch name and approve with `--no-preview`:

```sh
quill worktree create --branch fix/import --from HEAD --no-preview
quill worktree list --repo /path/to/project
```

`--branch` bypasses AI naming. `--no-preview` skips interactive approval; it can
also be used with an AI task description. `--repo` selects the repository.
List and remove do not require AI or fzf. List shows cached push status; it does
not fetch. Use Git to create a worktree for an existing branch; Quillmit creation
requires a new branch and an unused destination.

Removal accepts a branch name, directory name, or exact registered path. It:

- Refuses the main worktree, foreign worktrees, locked worktrees, and detached HEAD.
- Refuses staged, unstaged, untracked, and ignored files, and active Git operations.
- Fetches and verifies the branch's remote upstream when any remote is configured.
  A missing upstream, missing remote branch, failed fetch, or unpushed commit blocks removal.
- Allows removal without a remote when the worktree is clean and attached to a local branch.
- Uses `git worktree remove` and preserves the local branch and its commits.

Ignored files can include `.env` and build directories. Quillmit lists blocking
paths without reading their contents. Preserve or remove those files explicitly
before retrying. AI does not override these checks. There is no force-removal flag.
If you remove the worktree you are currently in, change your shell directory to
the main checkout afterward; Quillmit cannot change its parent shell's directory.

## Config

Quillmit loads the `quill.config` beside the executable. An installed release
has its own copy. Editing the source checkout does not change that copy.

For personal settings, copy the configuration outside the release package and
pass its path explicitly:

```sh
mkdir -p "$HOME/.config/quillmit"
cp quill.config "$HOME/.config/quillmit/quill.config"
quill --config "$HOME/.config/quillmit/quill.config"
```

Run the copy command from a source checkout or extracted release. Edit the
personal file after copying it. Do not repeat the copy when updating Quillmit,
since that would overwrite your settings. Configuration files contain shell
assignments and are executed by zsh; use files you trust.

Example configuration:

```sh
DEFAULT_PROVIDER=codex

CODEX_MODEL=gpt-5.3-codex-spark
CODEX_REASONING_EFFORT=low
CODEX_FALLBACK_MODEL=gpt-5.6-luna
CODEX_FALLBACK_REASONING_EFFORT=low
CLAUDE_MODEL=haiku
CLAUDE_FALLBACK_MODEL=haiku
GEMINI_MODEL=gemini-3-flash-preview
GEMINI_FALLBACK_MODEL=gemini-3-flash-preview

CODEX_MAX_PROMPT_BYTES=160000
CLAUDE_MAX_PROMPT_BYTES=160000
GEMINI_MAX_PROMPT_BYTES=160000
```

If a primary model reports a usage limit, Quillmit retries the same request once
with that provider's fallback model. A fallback value that is empty or equal to
the primary model disables the retry. The Codex primary call uses
`CODEX_REASONING_EFFORT`, and the fallback call uses
`CODEX_FALLBACK_REASONING_EFFORT`. Other provider failures do not trigger a
fallback.

The byte budgets are conservative input limits that reserve context for
provider instructions and output. They can be tuned independently when using a
model with a different context window.

Use a different config file:

```sh
quill --config /path/to/quill.config
```

By default, provider output is quiet. Failures write details to:

```sh
~/.cache/quill/last.log
```

If that cache directory is not writable, it falls back to:

```sh
$TMPDIR/quill/last.log
```

## License

MIT. See [LICENSE](LICENSE).
