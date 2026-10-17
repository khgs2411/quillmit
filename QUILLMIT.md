# Quillmit

Use `quill` for commits and PRs instead of writing messages yourself.

- Commit: stage what you want, then `quill -c`. `quill -a -c` stages everything first.
- Push: add `-p`. `quill -f` stages all, commits and pushes. Push only when your other instructions allow it.
- `-p` only pushes a commit quill just made. To push existing commits, run `git push` (when allowed).
- PR: `quill pr --base <branch> --no-preview`. Add `--closes 12,13` to close issues and `--prompt "<focus>"` to steer the description. Add `--remote <name>` if the repo has several remotes.
- Never run plain `quill` or `quill pr` without these flags: they wait for a terminal prompt.
