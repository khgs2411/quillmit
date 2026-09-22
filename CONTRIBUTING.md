# Contributing

## Run from source

Use zsh, Git, Python 3.9 or later, curl, tar, and a SHA-256 tool (`sha256sum` or
`shasum`). AI commands also need an authenticated provider CLI; PR creation needs
an authenticated GitHub CLI. Deterministic tests supply fake provider and GitHub
commands.

Clone the repository and prepare its private TUI dependency:

```sh
git clone https://github.com/khgs2411/quillmit.git
cd quillmit
```

Use `./quill` to run this checkout. Before using interactive PR or worktree
creation, run:

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
./scripts/check
```

This runs syntax checks, the CLI and release suites, PR and worktree contracts,
and real fzf terminal tests. It downloads the pinned private fzf binary. It needs
Python 3.9 or later and pseudo-terminal access. AI and GitHub commands are fake in these
suites; Git repositories, worktrees, and local bare remotes are real.

For the complete release gate, including real AI usage:

```sh
./scripts/check --live
```

The live smoke test uses the checked-out `quill.config` and installed provider CLI.
It incurs model usage and requires authentication. The current configuration uses
`gpt-6-luna` with low reasoning and Fast mode. The fallback remains `gpt-6-luna`
with low reasoning, so no alternate model retry occurs. It tests a
real AI-generated branch and worktree, remote-default selection, links, listing,
local removal, pending and ignored files, locks, active Git operations, upstream
checks, unpushed commits, and remote failure. Its repositories and remotes are
temporary. It never pushes to GitHub. It does not force a real provider failure;
deterministic tests cover fallback and invalid responses.

To also create a live smoke worktree in this checkout:

```sh
python3 test_worktree_live.py --checkout
```

This command first runs the isolated live smoke test. It then creates one new
AI-named worktree here. It checks the links and removal guards, then removes only
that test's clean worktree and unchanged branch. It leaves the main `.gitignore`
rule visible. Existing branches and worktrees are not removed. If unexpected work
appears in the smoke worktree, cleanup stops for inspection.

`deploy` always runs `./scripts/check --live`, including on `--resume`, before
its isolated install, commit, push, tag, publication, or normal installation.
A failure stops deployment. Public CI runs `./scripts/check` without live AI;
contributors do not need provider credentials to run the deterministic suites.

Individual suites remain available. Run `./scripts/setup-deps` before the real
terminal suite (`test_tui_real.py`):

```sh
zsh test_quill.sh
zsh test_release.sh
python3 test_tui.py
python3 test_worktree.py
python3 test_tui_real.py
python3 test_worktree_live.py
```

The worktree failure tests cover concurrent file and commit changes during fetch,
diverged history, active Git operations with clean files, and setup failures.
Also check layout in your own terminal when changing the TUI. Terminal smoke tests
do not prove visual quality in every terminal.

To check a package without replacing your normal installation:

```sh
./install --bin-dir ./tmp/install/bin --install-root ./tmp/install/packages
./tmp/install/bin/quill --version
```

This downloads the pinned dependency. `tmp/` is ignored. Reusing a version with
different bytes is refused; remove only this disposable installation before
repeating the check with changed code. The end-user installer does not run tests
or require AI authentication; maintainers must pass the release gate first.

## Dependencies

To update fzf, change its version and platform checksums in
`third-party/fzf.lock`, review its license, and run dependency setup again.
Verify the supported macOS and Linux platforms before claiming compatibility.
Keep the downloaded binary out of Git. Commit the lock file and license.

## Repository layout

| Path | Responsibility |
| --- | --- |
| `quill` | CLI parsing, provider calls, commit and PR workflows |
| `scripts/worktree` | Worktree creation, inspection, and removal checks |
| `quill.config` | Packaged provider defaults |
| `scripts/setup-deps`, `third-party/` | Pinned TUI binary and license |
| `scripts/check`, `test_*` | Verification entry point and suites |
| `install`, `deploy`, `scripts/version` | Installation, publication, and version selection |
| `.github/workflows/test.yml` | Deterministic and terminal checks on macOS and Ubuntu |

## Pull requests

- Keep changes focused and preserve the `quill` command name.
- Add or update tests for behavior changes.
- Keep provider output quiet unless `--verbose` is enabled.
- Update command help and documentation with public behavior changes.

## Commit messages

Use clear titles such as `Add provider selection for Claude and Gemini`.
Quillmit intentionally avoids conventional prefixes such as `feat:` and `chore:`.

## Maintainer releases

For command use and recovery, see the [README](README.md) and
[troubleshooting guide](docs/troubleshooting.md). Report security concerns as
described in [SECURITY.md](SECURITY.md).

Follow [docs/releasing.md](docs/releasing.md). Installation, source development,
and GitHub publication are separate actions. Running the tests does not publish.
