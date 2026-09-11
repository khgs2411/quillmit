# Contributing

## Run from source

Clone the repository and use `./quill` from the checkout. Before using its
interactive PR interface, prepare the private dependency:

```sh
./scripts/setup-deps
./quill pr
```

`setup-deps` downloads the version pinned in `third-party/fzf.lock`, verifies its
SHA-256 checksum, and writes the binary and license to the ignored `.deps/`
directory. Quillmit does not use a global fzf binary. The normal installer
performs dependency setup inside its release staging directory.

## Verify changes

```sh
zsh -n quill
zsh -n install
zsh -n deploy
zsh -n scripts/setup-deps
zsh test_quill.sh
zsh test_release.sh
python3 test_tui.py
```

These checks need Python 3 in addition to the installation tools. The suites use
temporary repositories and fake provider, download, and GitHub commands. They do not call AI services, download dependencies, publish to GitHub,
or change your normal installation. Release tests use local bare Git remotes.

The failure tests check provider fallback, empty output, batch completeness,
installation recovery, and release resume boundaries. PR tests preserve Markdown
and shell literals and check that creation requires approval.

Run the real fzf smoke tests separately:

```sh
./scripts/setup-deps
python3 test_tui_real.py
```

This suite requires pseudo-terminal access. It uses the private fzf binary with
fake AI and GitHub commands. It checks keyboard filtering, mouse selection,
approval, and cancellation. Dependency setup downloads the pinned binary.

Also check TUI changes in a real terminal. Verify filtering, keyboard and mouse
selection, preview scrolling, Esc navigation, and explicit approval. Automated
boundary tests do not prove the visual layout works in every terminal.

To check a real package without replacing your normal installation:

```sh
./install --bin-dir ./tmp/install/bin --install-root ./tmp/install/packages
./tmp/install/bin/quill --version
```

This check downloads the pinned dependency. `tmp/` is ignored. Reusing a version
with different bytes is refused; remove only this disposable installation before
repeating the check with changed code.

## Dependencies

To update fzf, change its version and platform checksums in
`third-party/fzf.lock`, review its license, and run dependency setup again.
Verify the supported macOS and Linux platforms before claiming compatibility.
Keep the downloaded binary out of Git. Commit the lock file and license.

## Pull requests

- Keep changes focused and preserve the `quill` command name.
- Add or update tests for behavior changes.
- Keep provider output quiet unless `--verbose` is enabled.
- Update command help and documentation with public behavior changes.

## Commit messages

Use clear titles such as `Add provider selection for Claude and Gemini`.
Quillmit intentionally avoids conventional prefixes such as `feat:` and `chore:`.

## Maintainer releases

Follow [docs/releasing.md](docs/releasing.md). Installation, source development,
and GitHub publication are separate actions. Running the tests does not publish.
