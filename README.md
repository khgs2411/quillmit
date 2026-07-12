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
immutable.

Make sure `~/.local/bin` is on your `PATH`.

Confirm the installed release with:

```sh
quill --version
```

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
CLAUDE_MODEL=haiku
GEMINI_MODEL=gemini-3-flash-preview

CODEX_MAX_PROMPT_BYTES=160000
CLAUDE_MAX_PROMPT_BYTES=160000
GEMINI_MAX_PROMPT_BYTES=160000
```

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
