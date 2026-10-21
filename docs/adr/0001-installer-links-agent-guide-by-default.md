# Installer links the Agent Guide by default

Every `install` writes the Agent Guide to `QUILLMIT.md` next to each existing Global Instructions File (Claude Code and Codex) and adds a guide link once: `@QUILLMIT.md` for Claude Code and an absolute `@/path/to/QUILLMIT.md` for Codex. Existing relative Codex links are migrated during installation. Agents then hand commit messages and PRs to Quillmit's cheap provider instead of spending their own tokens. It is on by default because an opt-in that users have to discover would rarely get used. `--no-agent-guide` removes it and remembers the opt-out, so later installs and releases leave the agent files alone. `--agent-guide` opts back in.

## Considered Options

- **Opt-in flag.** Rejected: the guide only pays off if agents see it, and an opt-in nobody discovers changes nothing.
- **Inline marked block instead of a link.** It would load in every CLI, but rejected in favor of matching RTK's one-line link, which keeps the user's file untouched apart from that line.

## Consequences

- Codex has no import mechanism ([research](../research/agent-instruction-files.md)), so for Codex the absolute guide link reaches the model as a path to read rather than automatically loading the guide. The absolute path allows agents to resolve it from any checkout.
- Codex reads a non-empty `AGENTS.override.md` instead of `AGENTS.md`, so install warns when one exists and does not write to it.
- Gemini CLI is out of scope.
