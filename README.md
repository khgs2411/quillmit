# Quillmit

AI-assisted commits, pull requests, and linked Git worktrees from your terminal.

Quillmit uses your installed AI CLIs to write commit messages, prepare pull
requests, and propose worktree branches. Codex is the default provider. Claude
Code and Gemini CLI are also supported. Git operations run on your machine; AI
CLIs can send repository context to their provider services.

The command is:

```sh
quill
```

The project is Quillmit. The executable is `quill`.

[Install or update](#install-or-update) · [Usage](#usage) · [Worktrees](#worktrees) ·
[Configuration](#config) · [Troubleshooting](docs/troubleshooting.md) ·
[Contributing](CONTRIBUTING.md) · [Release guide](docs/releasing.md)

## Common commands

| Task | Command |
| --- | --- |
| Generate a commit message and choose an action | `quill` |
| Stage all changes, generate a message, commit, and push | `quill -f` |
| Set the Codex model and reasoning for future runs | `quill --model gpt-6-sol --reasoning high` |
| Restore the default Codex model and reasoning | `quill --model default` |
| Turn Codex fast mode on or off | `quill --fast true` / `quill --fast false` |
| Show the active provider settings | `quill --which` |
| Show commands and examples | `quill --help` |
| Select a PR target and approve the generated content | `quill pr` |
| Create a worktree from a task description | `quill worktree create "fix parser retries"` |
| Show registered worktrees and their status | `quill worktree list` |
| Remove a safe worktree and keep its branch | `quill worktree remove [branch-or-path]` |

`quill -f` commits and pushes without an approval prompt. Review your changes
before running it. PR and worktree creation show an approval preview unless you
pass `--no-preview`.

## Features

- Uses your local AI CLI subscriptions instead of a separate hosted service.
- Supports Codex, Claude Code, and Gemini CLI.
- Supports a fallback model for each provider when the primary model reaches a usage limit.
- Reads staged changes first; if nothing is staged, reads the working tree.
- Stages all changes before generation when `--add` or `--full` is passed, after validation.
- Commits only staged changes.
- Provides `-a`, `-c`, `-p`, and `-f` aliases for common commit workflows.
- Creates AI-written pull requests with searchable branch selection and approval previews.
- Prepares `.git/COMMIT_EDITMSG` by default.
- Copies messages with `pbcopy`, `wl-copy`, `xclip`, or `xsel`.
- Keeps provider transcripts hidden unless `--verbose` is enabled.
- Avoids noisy conventional commit prefixes like `feat(scope):` and `chore:`.
- Proposes worktree branches with AI and checks Git state before removal.
- Includes shell and Python tests, real terminal checks, and optional live AI smoke tests.

## Requirements

Use `zsh` and Git on macOS or Linux. For AI generation, install and authenticate
at least one provider CLI:

- Codex CLI for the default provider.
- Claude Code CLI for `--claude`.
- Gemini CLI for `--gemini`.

Quillmit does not install or authenticate provider CLIs for you. Worktree listing,
removal, and creation with `--branch` do not require an AI CLI.

The `quill pr` workflow also requires an installed and authenticated GitHub CLI
(`gh`).

Quillmit manages its own pinned [fzf](https://github.com/junegunn/fzf) dependency
for PR and worktree creation interfaces. The installer downloads the platform
binary, checks its SHA-256 checksum against `third-party/fzf.lock`, and includes it and its license
inside the installed Quillmit version. No global fzf installation is required.
Dependency downloads require `curl`, `tar`, and `sha256sum` or `shasum`.
The packaged TUI supports macOS and Linux on ARM64 and x86-64.

## Compatibility

| Platform | Status | Notes |
| --- | --- | --- |
| macOS | Supported | Uses `pbcopy` for `--copy`. |
| Linux | Tested on Ubuntu CI | Uses `wl-copy`, `xclip`, or `xsel` for `--copy`. |
| Windows | Not supported | WSL may work if provider CLIs and clipboard tools are available. |

## Demo

```text
$ quill
✦ quillmit · my-project
  Codex · gpt-6-luna · staged changes only

[11/10/2026 1:04:09 PM]: Reading Git context...
[11/10/2026 1:04:09 PM]: ✓ Git context · 0.1s
[11/10/2026 1:04:09 PM]: Generating commit message with Codex...
[11/10/2026 1:04:15 PM]: Drafting commit message [==========>-------------] 0/1 · 6.2s elapsed
[11/10/2026 1:04:18 PM]: ✓ Drafting commit message · 8.7s
[11/10/2026 1:04:18 PM]: ✓ Generated commit message with Codex · 8.8s total

── Generated commit message: ──
Add provider-aware commit message preparation

Route the current Git context through the selected AI CLI and keep provider
output quiet by default.
Prepare COMMIT_EDITMSG before prompting so normal git commit remains available.
Support commit, copy, regenerate, and quit actions from the terminal flow.
──────────────────────────────
[11/10/2026 1:04:18 PM]: Prepared commit message at /path/to/repo/.git/COMMIT_EDITMSG
[c]ommit, [e]dit, co[p]y, [r]egenerate, [q]uit:
```

## Install or update

By default, install links the Agent Guide into existing Claude Code and Codex
Global Instructions Files. Use `./install --no-agent-guide` to opt out; this
choice is remembered across reinstalls and upgrades.

Install a published version from the [releases page](https://github.com/khgs2411/quillmit/releases/latest).
For version `0.5.0`:

```sh
git clone --branch v0.5.0 --depth 1 https://github.com/khgs2411/quillmit.git
cd quillmit
./install
```

For another release, replace `v0.5.0` with its published tag.

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

### Agent Guide

Install writes a Quillmit-owned `QUILLMIT.md` next to each existing
`~/.claude/CLAUDE.md` and `${CODEX_HOME:-~/.codex}/AGENTS.md`, and appends
`@QUILLMIT.md` once. It refreshes the guide on every install, preserves the rest
of your instructions, and reports which files it linked, refreshed, or skipped.
It does not create instructions files for tools you do not use.

`./install --no-agent-guide` removes the exact link lines and the guide files,
leaving all other content, including separating blank lines, in place. The
opt-out is stored in the install root. Later plain installs leave agent files
alone; `./install --agent-guide` clears the opt-out and links the guide again.
The two flags cannot be combined.

Codex receives the link as plain text because it does not support imports.
If a non-blank `AGENTS.override.md` exists, install warns that Codex ignores
`AGENTS.md` and the guide. It never edits the override file.

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

Plain `./deploy` keeps an unpublished prepared version. If the current version
is already published or tagged remotely, it increments the patch version.
`./deploy --no-bump` requires an unpublished current version.

## Usage

```sh
quill
```

Run it from a Git repository. Quillmit reads the Git state locally, asks the
selected provider to write a medium-sized commit message from that context,
previews it, prepares Git's `COMMIT_EDITMSG` file, then asks what to do next.
Git resolves that file separately for each worktree.

If files are staged, Quillmit generates the message from staged changes only.
If nothing is staged, it generates from the changed working tree.
Commit actions only commit staged changes by default.

When the Git context exceeds the selected provider's configured prompt budget,
Quillmit groups complete file diffs into bounded batches, summarizes those
batches sequentially, and makes one final provider call to synthesize the commit
message. A single file larger than a batch is split at diff-hunk boundaries,
with a byte-bounded fallback for an individual oversized hunk.

Before measuring or batching context, Quillmit replaces valid inline Base64 data
URL payloads with placeholders retaining the media type, normalized encoded byte
count, and SHA-256 fingerprint. Filtering recognizes literal JavaScript/JSON
escapes, HTML entities, percent encoding, omitted padding, whitespace-wrapped
payloads, and concatenated string literals. Headers and URL fragments, surrounding
code, string joins, and diff markers are preserved. Bare Base64 and malformed
data URLs remain untouched. No source code is evaluated.
This only changes AI context; staged files remain untouched. Commit and PR
generation use the same filtering and sequential execution. A failed batch stops
generation before synthesis. Cancellation terminates the active provider process
group and waits for its supervisor before removing temporary files.

Status messages use local timestamps in `[DD/MM/YYYY h:mm:ss AM/PM]:` format.
The loading bar shows the active stage and elapsed time. Status output reports
the time spent preparing context, summarizing each batch, writing the final
message, and the generation total. Commit and push actions also report their duration.
Terminal output adds color and emphasizes the message title. Set `NO_COLOR` to
disable color; redirected output and `TERM=dumb` use plain, timestamped text
without the loading animation. Display formatting never enters the generated
commit message or PR description.

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

To display the generated message and commit without an approval prompt:

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
`[c]ommit`. Push failures leave the local commit in place. Quillmit uses Git's
configured push target and does not set an upstream. On a clean working tree, it exits
without pushing. To retry a failed push, use `git push`.

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

After approval, Quillmit calls `gh pr create`, assigns the pull request to your
authenticated GitHub account by default, and lets GitHub CLI push or fork the head
branch when necessary. Pass `quill pr --no-assignment` to skip assignment and assign
it yourself on GitHub later. Uncommitted changes are
not included. Provider and configuration flags remain available, for example
`quill pr --claude` or `quill pr --config /path/to/quill.config`.

### Agent PR review

Prepare a draft, read and optionally edit it with ordinary file tools, then approve
it with `--create-from`:

```sh
quill pr --prepare --base main --closes 3,4 --prompt "Explain the rollout"
# Read/edit the absolute path printed by prepare, for example:
quill pr --create-from /path/to/.git/QUILL_PR_EDITMSG
```

`--prepare` writes the same content as the preview to `QUILL_PR_EDITMSG` in Git's
metadata directory, prints its absolute path, and exits without creating a PR.
Each run overwrites the previous draft; linked worktrees get their own draft.
Provide `--base` and, with multiple remotes, `--remote` to run without a terminal
or fzf. `--prepare --no-preview` is also accepted. To decline, simply stop.
Commit-side `quill --prepare` continues to prepare `COMMIT_EDITMSG`.

The draft contains its entire target and reviewed content:

```text
From: feature
Into: owner/repo:main

Title

Markdown body
```

`--create-from <file>` uses the title and body exactly as written, without a
provider call, preview, remote selection, or fetch. It refuses a different current
branch (including detached HEAD), malformed target, missing title, or empty body.
It accepts `--no-assignment` and a repository path; target, generation, provider,
and preview flags cannot be combined with it. It does not push the branch itself;
GitHub CLI handles an unpushed head as in the existing creation flow.

`--closes 3,4` appends a separate `Closes #3` and `Closes #4` line at the end of
the generated body. GitHub needs one closing keyword per issue: `Closes #3, #4`
does not close both, and ranges are unsupported. Only positive decimal numbers
are accepted; `0`, leading zeros such as `03`, empty items, `#3`, signs, ranges,
and words are rejected before
generation. Order and duplicates are preserved. Issue numbers are not looked up
on GitHub. Closing keywords take effect only when a PR targets the default branch.

`--prompt "text"` supplies content guidance after Quillmit's output requirements,
including in the final synthesis of large changes. It cannot override the title
and body format. The provider is instructed not to write closing keywords;
deterministic closing lines come from `--closes`. Both flags also work with the
interactive preview and `--no-preview`, and closing lines survive regeneration
when another base branch is selected. They are rejected with `--create-from`,
which publishes the reviewed file without further generation or additions.

### Non-interactive use

The interactive commit prompt requires both stdin and stdout to be terminals.
Plain `quill` and `quill -a` refuse without them before staging or calling a
provider. A clean repository still prints "No changes to commit" and exits
successfully. Piping answers into the prompt is unsupported: replace `c` with
`-c`, `q` with `--quit`, and `p` with `--copy`. Editing and regeneration require
a person at a terminal.

To review a commit message before committing:

```sh
quill --prepare
# Read or edit the COMMIT_EDITMSG path printed on the last stdout line, then:
git commit -F /absolute/path/to/COMMIT_EDITMSG
```

`--prepare` keeps its human-readable "Prepared commit message at …" line and
prints the bare absolute path after it. Both `quill --prepare` and
`quill pr --prepare` report their prepared file as the last stdout line. Linked
worktrees use their own Git metadata file. When the commit repository is clean,
there is no prepared message or path; the successful no-op is reported instead.
Preparation leaves the index as it was unless you also pass `-a`.

For PRs, target selection and preview need a terminal. Provide `--base` and either
`--prepare` or `--no-preview`, plus `--remote` when there are several remotes:

```sh
quill pr --prepare --base main --remote origin
# Read or edit the QUILL_PR_EDITMSG path printed on the last stdout line, then:
quill pr --create-from /absolute/path/to/QUILL_PR_EDITMSG
```

Use `--no-preview` to create the generated PR immediately. Use the prepare and
`--create-from` loop above when review is needed.

Worktree creation from a task description needs a terminal. Agents should first
list existing worktrees and reuse a suitable one. When a new worktree is needed,
choose the branch name and skip preview:

```sh
quill worktree list
quill worktree create --branch fix/retries --no-preview
# For a local starting point without fetching:
quill worktree create --branch fix/local-retries --from HEAD --no-preview
```

Review the listed worktrees, branch name, and starting point before creation.
The default starting point is the remote's default branch.

Commit flags `-c` (also `--commit` and `--yes`), `-f`, `--prepare`, `--copy`, and
`--quit` work without a terminal. `-c` with nothing staged refuses before calling
the provider and prints a `git add` hint; use `-a -c` to stage all changes first.
`-f` stages, commits, and pushes immediately. Clipboard modes still require a
working clipboard command.

### Other commit modes

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
# From inside a linked worktree:
quill worktree remove
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
Set its own upstream when you first push it. For example, from the new worktree,
use `git push --set-upstream origin HEAD` if `origin` is the intended remote.
Quillmit prints the worktree path; use `cd` to enter it.

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

Removal accepts a branch name, directory name, or exact registered path. If you
omit the target, Quillmit selects the linked worktree that contains the current
directory. With `--repo`, it selects the linked worktree that contains that path.
The main checkout remains protected. Removal:

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

Quillmit loads the `quill.config` beside the executable until a personal config
exists at `${XDG_CONFIG_HOME:-$HOME/.config}/quillmit/quill.config`. It then loads
the personal config automatically. An installed release has its own bundled
copy; editing the source checkout does not change that copy.

Settings commands create the personal config from the bundled copy when needed
and update only the selected Codex settings. They do not run Git or an AI CLI:

```sh
quill --model gpt-6-sol --reasoning high
quill --model default              # gpt-6-luna, reasoning low
quill --fast true                  # fast service tier
quill --fast false                 # standard service tier
quill --which                      # show the settings Quillmit will use
quill --help                       # commands, options, and examples
```

`--model` alone keeps the current reasoning effort; `--reasoning` can also be
used alone. `--model default` changes the model and reasoning effort but leaves
fast mode as it was. Pass `--config /path/to/quill.config` with a settings command
to update that existing file instead. Settings flags cannot be combined with an
execution command. `--which` reads the active config and prints its path, default
provider, model, reasoning, and fast status without starting Git or an AI CLI.
Use `quill --which --config /path/to/quill.config` to inspect another file. For
Claude and Gemini, reasoning is managed by their CLI and Quillmit fast mode is
off because it applies only to Codex.

For other personal settings, edit the personal config directly. To create it
without changing a Codex setting, copy the bundled config to that path:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/quillmit"
cp quill.config "${XDG_CONFIG_HOME:-$HOME/.config}/quillmit/quill.config"
```

Run the copy command from a source checkout or extracted release. Quillmit reads
that file automatically. Do not repeat the copy when updating Quillmit, since
that would overwrite your settings.
Configuration files contain shell assignments and are executed by zsh; use files
you trust.

Example configuration:

```sh
DEFAULT_PROVIDER=codex

CODEX_MODEL=gpt-6-luna
CODEX_REASONING_EFFORT=low
CODEX_SERVICE_TIER=fast
CODEX_FALLBACK_MODEL=gpt-6-luna
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
`CODEX_FALLBACK_REASONING_EFFORT`. Codex calls also use
`CODEX_SERVICE_TIER` (`fast` by default). Fast mode uses 2.5x standard ChatGPT
credits for GPT-6 models where available. Other provider failures do not trigger
a fallback.

The byte budgets are conservative input limits that reserve context for
provider instructions and output. They can be tuned independently when using a
model with a different context window.

Use a different config file:

```sh
quill --config /path/to/quill.config
```

By default, provider output is quiet. Failures write details to:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/quill/last.log
```

If that cache directory is not writable, it falls back to:

```text
${TMPDIR:-/tmp}/quill/last.log
```

See [Troubleshooting](docs/troubleshooting.md) for recovery steps. Before sharing
logs, follow the [security guidance](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
