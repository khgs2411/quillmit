# Large PRs draft from commit messages, not diff batches

When a PR's Git context exceeds the provider's prompt budget, `quill pr` writes the draft in one provider call from the branch's commit messages and diffstat, without the diff. It no longer splits the diff into batches, because a 109-commit branch took N+1 sequential calls and many minutes to re-summarize diffs whose commit messages Quillmit had already summarized. Commit messages carry the intent a PR description needs, and the diffstat lets the model check them against what the branch actually changed.

## Considered Options

- **Keep diff batching for PRs.** Rejected: on a large branch it's the slowest path, and the output is no better than a summary of the existing commit messages.
- **Subjects only.** Rejected as the primary input: titles lose the "why" that the commit bodies hold. Kept only as the fallback when the full messages don't fit.
- **Opt-in flag.** Rejected: the slow path would stay the default, and nobody would remember the flag.

## Consequences

- A large PR's draft is only as good as its commit history. A branch of "wip" commits gets a weak description, and work that no commit message mentions won't appear in it.
- Commit generation keeps diff batching, because a commit has no history to draw on.
- PRs that fit the budget are unchanged: they still send the full diff.
