# Security

Quillmit runs local Git and installed AI CLIs. It does not collect API keys or
manage provider credentials. Provider CLIs can send repository context to their
services. Quillmit does not redact that context.

## Report a vulnerability

Report security concerns privately to the repository owner, `khgs2411`, before
opening a public issue. Include the Quillmit version, operating system, affected
command, expected behavior, and reproduction steps with synthetic data. Do not
include credentials, private repository contents, or unredacted provider logs.

## Repository context and logs

- Commit generation sends selected Git diff context to the configured provider.
- PR generation sends committed changes between the selected base and HEAD.
- AI worktree naming sends the task, starting point, local branch names, registered
  worktree paths, and up to 120 lines of the main root's `AGENTS.md`.
- Worktree listing, removal, and creation with `--branch` do not call AI.
- Ignored file contents are not collected for worktree naming. Ignore rules do not
  protect secrets that are already tracked in Git.
- Provider logs can contain repository or generated content. Review and redact
  them before sharing. See [log locations](README.md#config).

The selected provider's settings and permissions also apply. Quillmit requests
Codex's read-only sandbox. Do not assume all provider CLIs have identical access
controls.

## Approval and file safety

Review changes before `quill -f`: it stages all changes and commits and pushes
without an approval prompt. PR and worktree creation require approval unless
`--no-preview` is supplied. AI suggestions do not override worktree removal
checks. See [worktree safety rules](README.md#worktrees).

Configuration files are sourced as zsh code. Use trusted configuration files and
keep personal settings outside versioned installation packages.

## Downloaded dependencies

The installer downloads Quillmit's pinned fzf binary and checks its SHA-256
checksum against `third-party/fzf.lock`. It includes the dependency license.
Install from a trusted [published release](https://github.com/khgs2411/quillmit/releases).
Checksums verify the downloaded bytes against the repository's lock file; they
do not replace trust in the release source.
