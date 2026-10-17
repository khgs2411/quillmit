# Global agent instruction files: Codex CLI, Gemini CLI, Claude Code

Research date: 2026-10-17. Purpose: decide how the Quillmit installer adds a
short instructions block to each CLI's global instruction file — an inline
marked block (`<!-- quillmit:start -->…<!-- quillmit:end -->`) or a single
import line pointing at a `QUILL.md`.

Sources checked:

| CLI | Source | Version |
| - | - | - |
| Codex CLI | [openai/codex](https://github.com/openai/codex) source | `master` @ [`ce0323f`](https://github.com/openai/codex/tree/ce0323f2f2d3b25e82806cd555237da3db4e1897) (2026-10-17); loader cross-checked at tag [`rust-v0.163.0`](https://github.com/openai/codex/tree/rust-v0.163.0) (`8308618`), the locally installed `codex-cli 0.163.0` |
| Codex CLI | [AGENTS.md guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md) (redirect target of `developers.openai.com/codex/guides/agents-md`) | live, 2026-10-17 |
| Gemini CLI | [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) source and `docs/` | `main` @ [`ed96fae`](https://github.com/google-gemini/gemini-cli/tree/ed96faedfd5571f055c44f2c9509d62321d1138d) (0.66.0-nightly); import logic cross-checked at tag [`v0.46.0`](https://github.com/google-gemini/gemini-cli/tree/v0.46.0) (`85b0c55`), the locally installed version |
| Claude Code | [Memory docs](https://code.claude.com/docs/en/memory), [env-vars docs](https://code.claude.com/docs/en/env-vars) | live, 2026-10-17; installed `2.1.292`. Claude Code is closed source, so claims rest on docs only |

Short links used below:

- `CX` = `https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs`
- `GM` = `https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d`

## 1. Codex CLI: no import mechanism

**Verdict: Codex has no `@path` import or any include mechanism, in the global
file or in project files.** File contents go to the model verbatim; an
`@./QUILL.md` line would reach the model as literal text and nothing would be
loaded.

Evidence:

- The global loader, `CodexHomeUserInstructionsProvider::load_from_codex_home`,
  reads the file bytes, decodes them lossily as UTF-8, `trim()`s them and
  returns the text. No parsing step follows.
  ([`CX/codex-home/src/instructions/mod.rs` L40–83](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/codex-home/src/instructions/mod.rs#L40-L83))
- The project loader, `read_agents_md`, reads each discovered file, truncates
  it to the remaining byte budget and pushes the raw text.
  ([`CX/core/src/agents_md.rs` L121–180](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/core/src/agents_md.rs#L121-L180))
- Assembly (`legacy_text`) only joins entries with `\n\n` and a
  `--- project-doc ---` separator.
  ([`CX/core/src/agents_md.rs`](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/core/src/agents_md.rs))
- The official guide documents discovery, override and fallback names, and
  never mentions imports or includes.
  ([AGENTS.md guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md))
- The same global loader exists unchanged at `rust-v0.163.0`.
  ([tag source](https://github.com/openai/codex/blob/rust-v0.163.0/codex-rs/codex-home/src/instructions/mod.rs))

The only "indirection" Codex offers is `project_doc_fallback_filenames`, which
adds alternative filenames for **project** discovery. Bare filenames only:
entries containing `/` are ignored.
([`CX/core/src/agents_md.rs` `candidate_filenames`](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/core/src/agents_md.rs);
[`CX/config/src/config_toml.rs` L338–340](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/config/src/config_toml.rs#L338-L340))
The global loader does not use the fallback list; it only checks the two fixed
names. ([`mod.rs` L43](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/codex-home/src/instructions/mod.rs#L43))

### Codex: `AGENTS.override.md` replaces, it does not merge

At the global level Codex checks `AGENTS.override.md` first, then `AGENTS.md`,
and **returns the first non-empty file**. A non-empty override means
`AGENTS.md` is not read at all. An empty or whitespace-only override, or one
that is a directory, falls through to `AGENTS.md`.
([`mod.rs` L43–76](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/codex-home/src/instructions/mod.rs#L43-L76);
tests in [`instructions/tests.rs`](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/codex-home/src/instructions/tests.rs);
guide: "uses only the first non-empty file at this level")

Consequence for Quillmit: a block appended to `~/.codex/AGENTS.md` is invisible
while a non-empty `~/.codex/AGENTS.override.md` exists.

## 2. Gemini CLI: imports supported, but sandboxed

**Verdict: `~/.gemini/GEMINI.md` supports `@path` imports, but the imported file
must resolve inside the importing file's "project root", which for the global
file is normally `~/.gemini/` itself.**

### Syntax and parsing

- Documented as `@file.md`, relative (`@./x.md`, `@../x.md`) or absolute
  (`@/abs/x.md`).
  ([`GM/docs/reference/memport.md`](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/docs/reference/memport.md);
  [`GM/docs/cli/gemini-md.md`](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/docs/cli/gemini-md.md))
- `findImports` treats `@` as an import only when preceded by whitespace (or at
  file start) and when the path's first character is `.`, `/` or a letter. The
  path ends at the next whitespace. **`@~/…` is not recognised** (`~` is none of
  those). ([`GM/packages/core/src/utils/memoryImportProcessor.ts` L103–153](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryImportProcessor.ts#L103-L153))
- Imports inside fenced code or inline code spans are skipped.
  ([`memoryImportProcessor.ts` `findCodeRegions`](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryImportProcessor.ts#L167))
- Relative paths resolve against the importing file's directory
  (`path.resolve(basePath, importPath)`, with `basePath = path.dirname(filePath)`).
  ([`memoryImportProcessor.ts` L339](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryImportProcessor.ts#L339);
  [`GM/packages/core/src/utils/memoryDiscovery.ts` L226–234](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryDiscovery.ts#L226-L234))

### Restrictions

- **Allowed directory.** Every import is checked by
  `validateImportPath(importPath, basePath, [projectRoot])`, which rejects URLs,
  resolves symlinks (`resolveToRealPath`) and requires the real path to be a
  subpath of the real `projectRoot`. A failure emits
  `<!-- Import failed: … - Path traversal attempt -->` instead of the content.
  ([`memoryImportProcessor.ts` L334–337, L390–420](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryImportProcessor.ts#L390-L420))
- **What `projectRoot` is for the global file.** `readGeminiMdFiles` passes no
  `projectRoot`, so `processImports` calls `findProjectRoot(dirname(file),
  boundaryMarkers)`: it walks up from `~/.gemini` looking for a marker
  (default `.git`, configurable via `context.memoryBoundaryMarkers`) and **falls
  back to the start directory, `~/.gemini`, if none is found**.
  ([`memoryImportProcessor.ts` L51–85, L203–205](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryImportProcessor.ts#L51-L85))
  So `@./QUILL.md` next to `GEMINI.md` works; an import pointing at, say,
  `~/.config/quillmit/QUILL.md` fails unless `$HOME` (or an ancestor) is itself
  a git repo. Symlinking `~/.gemini/QUILL.md` to a file outside does not help,
  because the check uses the resolved real path. (Inferred from the code above;
  not run.)
- **Depth.** `maxDepth: 5` by default; hard-coded in the default `importState`,
  not exposed as a setting.
  ([`memoryImportProcessor.ts` L193–215](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryImportProcessor.ts#L193-L215); docs say "configurable … default: 5 levels", but no setting for it was found in [`settingsSchema.ts`](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/cli/src/config/settingsSchema.ts#L1395-L1445))
- **Cycles.** A file already in the import chain is replaced by
  `<!-- File already processed: … -->`. ([`memoryImportProcessor.ts` L340–343](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryImportProcessor.ts#L340))
- **Missing file.** Replaced by an `<!-- Import failed: … -->` comment; loading
  continues. ([`memoryImportProcessor.ts` L366–375](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryImportProcessor.ts#L366))
- **Output shape.** Default `importFormat` `tree` inlines the content wrapped in
  `<!-- Imported from: … -->` comments; `flat` concatenates files with
  `--- File: … ---` headers. (`context.importFormat`;
  [`memoryImportProcessor.ts` L220–316](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryImportProcessor.ts#L220))
- The same `maxDepth`, `findProjectRoot` fallback and `validateImportPath` call
  exist at tag `v0.46.0`.
  ([tag source](https://github.com/google-gemini/gemini-cli/blob/v0.46.0/packages/core/src/utils/memoryImportProcessor.ts))

### Other filenames

`context.fileName` (string or string array) replaces the default `GEMINI.md`.
([`settingsSchema.ts` L1395–1404](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/cli/src/config/settingsSchema.ts#L1395-L1404);
[`GM/docs/cli/gemini-md.md`](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/docs/cli/gemini-md.md))
The global lookup iterates over **every** configured name in `~/.gemini/`, so
with `["AGENTS.md","GEMINI.md"]` both `~/.gemini/AGENTS.md` and
`~/.gemini/GEMINI.md` load.
([`memoryDiscovery.ts` `getGlobalMemoryPaths` L317–340](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryDiscovery.ts#L317-L340);
default name `DEFAULT_CONTEXT_FILENAME = 'GEMINI.md'` in
[`GM/packages/core/src/tools/memoryTool.ts` L11](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/tools/memoryTool.ts#L11))
Gemini never reads `~/.codex/AGENTS.md` or `~/.claude/CLAUDE.md`.

Note: Gemini's memory guidance tells the model to save cross-project
preferences to the global memory file (`globalMemoryPath`), so the agent itself
may edit `~/.gemini/GEMINI.md`.
([`GM/packages/core/src/prompts/snippets.ts` ~L863](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/prompts/snippets.ts#L863);
`getGlobalMemoryFilePath` in [`memoryTool.ts` L90](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/tools/memoryTool.ts#L90))

## 3. Claude Code: imports confirmed

From [Memory docs, "Import additional files"](https://code.claude.com/docs/en/memory#import-additional-files):

- `@path/to/import` works in any CLAUDE.md, including `~/.claude/CLAUDE.md`.
  Relative and absolute paths are allowed; `@~/…` is shown in a doc example.
- **Relative paths resolve relative to the file containing the import**, not
  the working directory.
- **Maximum depth: four hops** of recursive imports.
- Paths end at the first unescaped space; quoted paths are not imported.
  Imports inside code spans and fenced blocks are skipped.
- **Approval prompt:** external imports (outside the working directory) in
  *project-level* files trigger a one-time approval dialog. User-scope files
  (`~/.claude/CLAUDE.md`, `~/.claude/rules/`) load their imports **without the
  dialog** — except in Cowork desktop sessions, which **skip** any user-scope
  import resolving outside the session's working directory (and skip a
  `~/.claude/CLAUDE.md` that is itself a symlink).
- Imports do not save context: imported files load at launch.

Also relevant ([Memory docs, "How CLAUDE.md files load"](https://code.claude.com/docs/en/memory#how-claude-md-files-load)):

- **Block-level HTML comments are stripped** before injection. Quillmit's
  `<!-- quillmit:start/end -->` markers would cost no context and are invisible
  to the model; the content between them is kept.
- `~/.claude/rules/*.md` are loaded for every project
  ([User-level rules](https://code.claude.com/docs/en/memory#user-level-rules)).
  A drop-in `~/.claude/rules/quillmit.md` would need no edit to `CLAUDE.md` at
  all.

## 4. Locations, relocation, precedence and size limits

| | Codex CLI | Gemini CLI | Claude Code |
| - | - | - | - |
| Global file(s) | `$CODEX_HOME/AGENTS.override.md`, else `$CODEX_HOME/AGENTS.md` (first non-empty wins) [src](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/codex-home/src/instructions/mod.rs#L43) | `$GEMINI_CLI_HOME/.gemini/<name>` for each name in `context.fileName` (default `GEMINI.md`); all that exist load [src](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/memoryDiscovery.ts#L317-L340) | `~/.claude/CLAUDE.md`, plus `~/.claude/rules/*.md` [docs](https://code.claude.com/docs/en/memory#choose-where-to-put-claude-md-files) |
| Relocation env var | `CODEX_HOME` (default `~/.codex`; if set, must exist and be a directory, else error) [src](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/utils/home-dir/src/lib.rs#L4-L45) | `GEMINI_CLI_HOME` replaces the *home* dir; `.gemini` is appended under it [src](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/utils/paths.ts#L18-L28), [docs](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/docs/reference/configuration.md) | `CLAUDE_CONFIG_DIR` (default `~/.claude`; "All settings, session history, and plugins") [docs](https://code.claude.com/docs/en/env-vars). **Unverified** whether user `CLAUDE.md`/`rules/` move with it: docs do not say |
| Precedence / merge | Global first, then project files root→cwd, joined with `--- project-doc ---` separator; later = closer = wins by position. One file per directory (`AGENTS.override.md` > `AGENTS.md` > fallbacks) [src](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/core/src/agents_md.rs), [guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md) | Separate tiers wrapped as `<global_context>`, `<extension_context>`, `<project_context>`; system prompt states priority project > extension > global [src](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/core/src/prompts/snippets.ts#L553-L714) | Concatenated, not overriding: managed → user → project → local, root→cwd; later = read last. User rules load before project rules [docs](https://code.claude.com/docs/en/memory#how-claude-md-files-load) |
| Size limits | `project_doc_max_bytes` (default 32 KiB) caps **project** docs only; the global file is loaded separately and is not counted against it [src: manager calls `load_project_instructions(config, None, …)` then attaches user text](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/core/src/agents_md_manager.rs), [default](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/config/src/config_toml.rs#L75-L83). No cap on the global file found in the loader; a downstream cap is **unverified** | No byte cap on memory content found in the discovery or import code; `context.discoveryMaxDirs` (default 200) bounds directory scanning only [src](https://github.com/google-gemini/gemini-cli/blob/ed96faedfd5571f055c44f2c9509d62321d1138d/packages/cli/src/config/settingsSchema.ts#L1424-L1432) | Target under 200 lines per file (startup warning above it); a file over 4 MiB is skipped; each import counts as a separate file toward a combined warning [docs](https://code.claude.com/docs/en/memory#my-claude-md-is-too-large) |

Local state on this machine (2026-10-17): `~/.claude/CLAUDE.md` (8.2 KB) and
`~/.codex/AGENTS.md` (12.8 KB) exist; `~/.gemini/GEMINI.md` does not.

## Recommendation

| CLI | Target file | Approach | Why |
| - | - | - | - |
| Codex CLI | The file Codex actually loads: `$CODEX_HOME/AGENTS.override.md` if non-empty, else `$CODEX_HOME/AGENTS.md` | **Inline marked block** | No import mechanism exists; an import line would be literal text. Writing only to `AGENTS.md` silently does nothing when a non-empty override exists. Global file is outside the 32 KiB project budget, so a short block is safe. |
| Gemini CLI | `$GEMINI_CLI_HOME/.gemini/GEMINI.md` (or each existing name from `context.fileName`) | **Inline marked block** (import viable only with `QUILL.md` inside `~/.gemini/`) | Imports work, but only within `~/.gemini/` (or a git-root ancestor); `@~/` is not parsed; failures degrade to an HTML comment silently. An inline block has no path rules. The agent may itself edit this file, and a marked block survives that as well as an import line does. |
| Claude Code | `~/.claude/CLAUDE.md` | **Inline marked block** (an `@QUILL.md` import with `QUILL.md` in `~/.claude/` also works in the terminal CLI) | Imports from user scope load without a prompt, resolve relative to the file, and allow 4 hops, so an import is sound in the CLI. But Cowork desktop sessions skip user-scope imports outside the session's working directory, so `@QUILL.md` would silently drop there while an inline block still loads. Markers are stripped from context, so the inline block costs nothing extra. A `~/.claude/rules/quillmit.md` drop-in avoids editing `CLAUDE.md` entirely (not checked how Cowork treats a non-symlinked user rule file). |

**Inline marked block** is the only approach that works in all three, and the
recommended default for each. Open questions for the product lead: whether Codex's
`AGENTS.override.md` should get the block (it is described as a temporary
override), and whether Claude Code should use the `rules/` drop-in instead of
editing `CLAUDE.md`.
