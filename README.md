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

## Install

Clone the repository and run the installer:

```sh
git clone https://github.com/khgs2411/quillmit.git
cd quillmit
./install
```

The installer copies the release into
`~/.local/share/quillmit/versions/<version>/` and writes an owned launcher at
`~/.local/bin/quill`. It does not create a symlink or keep the command coupled
to the checkout. Re-running the installer repairs the launcher; installing
different bytes under an existing version is refused so releases remain
immutable. After the launcher switches successfully, the installer removes all
older recognized Quillmit version directories. Unrecognized content in a
custom install root is preserved with a warning rather than deleted.

Make sure `~/.local/bin` is on your `PATH`.

Confirm the installed release with:

```sh
quill --version
```

## Versioning And Deployment

Versioning, installation, and deployment are separate operations:

- `scripts/version` changes the repository's `VERSION` only.
- `install` installs exactly the declared `VERSION` locally and never changes it.
- `deploy` coordinates a version bump, verification, local installation,
  Quillmit commit/push, GitHub Actions, and the matching GitHub release.

The version script defaults to a patch increment:

```sh
./scripts/version          # 0.3.0 -> 0.3.1
./scripts/version --patch  # 0.3.0 -> 0.3.1
./scripts/version --minor  # 0.3.0 -> 0.4.0
./scripts/version --major  # 0.3.0 -> 1.0.0
```

To version and install a local build without publishing it:

```sh
./scripts/version  # or --minor / --major
./install
quill --version
```

Deployment uses the same version script and also defaults to a patch release:

```sh
./deploy          # patch release
./deploy --patch
./deploy --minor
./deploy --major
```

Deployments must run from `master` while it matches `origin/master`. The deploy
script publishes every working-tree change, so review the complete diff first.
It requires authenticated `gh` and the selected provider CLI. It stops before
creating the GitHub release if local verification, push, or GitHub Actions
fails.

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
quill --commit
quill --commit --push
```

`--yes` is still accepted as an alias.

To stage all changes before committing:

```sh
quill --add --commit
quill --add --commit --push
quill --full
```

`quill --add` stages everything before generating the commit message, even in
interactive or non-commit modes. `quill --full` is equivalent to `quill --add
--commit --push`.

`--push` runs `git push` only after a successful local commit. In interactive
mode, `quill --push` pushes only if you choose `[c]ommit`. Push failures leave the local commit in place.

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

## Config

Edit `quill.config`:

```sh
DEFAULT_PROVIDER=codex

CODEX_MODEL=gpt-5.3-codex-spark
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
the primary model disables the retry. The Codex fallback call also uses
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

## Development

```sh
zsh test_quill.sh
```

The tests use fake provider CLIs and do not call real AI services.

## License

MIT. See [LICENSE](LICENSE).

## Local Install From This Checkout

If you are developing Quillmit locally:

```sh
./install --bin-dir /path/on/PATH --install-root /path/for/versioned/packages
```
