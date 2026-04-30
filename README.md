# Quillmit

Terminal-first commit message helper powered by headless AI CLIs.

## Usage

```sh
quill
```

Run it from a Git repository. Quillmit reads the Git state locally, asks the
selected provider to write a medium-sized commit message from that context,
previews it, prepares `.git/COMMIT_EDITMSG`, then asks what to do next.

If files are staged, Quillmit generates the message from staged changes only.
If nothing is staged, it generates from the changed working tree.

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
```

`--yes` is still accepted as an alias.

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

CODEX_MODEL=gpt-5.3-codex
CLAUDE_MODEL=haiku
GEMINI_MODEL=gemini-3-flash-preview
```

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

## Install

```sh
/Users/liadgoren/Repositories/quillmit/install
```

This links `quill` into `~/.local/bin`.
It also removes legacy Quillmit-related symlinks installed by earlier local
versions, such as `gcommit` and stale `quill` links pointing at old project
folders.

To install somewhere else:

```sh
/Users/liadgoren/Repositories/quillmit/install --bin-dir /path/on/PATH
```
