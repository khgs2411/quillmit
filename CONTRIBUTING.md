# Contributing

Thanks for helping improve Quillmit.

## Development

Run the test suite before opening a pull request:

```sh
zsh test_quill.sh
```

The tests use fake provider CLIs, so they do not call Codex, Claude, Gemini, or
any external service.

## Pull Requests

- Keep changes focused.
- Preserve the `quill` command name.
- Do not add provider SDK dependencies unless the shell CLI path cannot support
  the feature.
- Add or update tests for behavior changes.
- Keep provider output quiet by default; verbose output belongs behind
  `--verbose`.

## Commit Messages

Quillmit intentionally avoids conventional commit prefixes such as `feat:` and
`chore:`. Prefer clear titles like:

```text
Add provider selection for Claude and Gemini
```

or typed titles when the category is obvious:

```text
Feature: Add provider selection for Claude and Gemini
Bug: Fix staged-only diff context
```
