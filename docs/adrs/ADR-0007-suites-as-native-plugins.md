---
date: 2026-07-13
decision_date: 2026-07-13
description: Plugin-shaped suites/skills get .claude-plugin manifests; install.sh translates them for Copilot and resolves deps
status: accepted
---

# ADR-0007: Suites and Skills as Native Claude Code/Copilot Plugins

## Status

Accepted

## Context

Two gaps existed in this repo's asset model:

1. `install.sh` had no way to express that a suite depends on a standalone skill. In
   practice, `suites/handoff-workflow/README.md` already documents that its
   `ingest-handoff` component dispatches to the shared `skills/create-adr` and
   `skills/yaml-frontmatter` — "shared rather than forked here" — but that dependency
   existed only in prose. Installing `handoff-workflow` never pulled in the skills it
   actually needs.
2. `suites/{name}/` and `skills/{name}/` had no relationship to Claude Code's or GitHub
   Copilot/VS Code's own native "plugin" concept, even though both ecosystems now ship
   one. `install.sh` copied every suite directory wholesale (`cp -R`), with no awareness
   of a suite's internal `agents/`/`skills/` structure.

Research (an Opus-led team of Sonnet researchers, independently cross-checked, plus
direct verification against `code.claude.com/docs/en/plugins-reference`,
`.../plugin-dependencies`, `.../plugin-marketplaces`, and GitHub's own
`about-plugins.md`/`about-cli-plugins`) found:

- Claude Code has a real, versioned plugin system: `.claude-plugin/plugin.json` (a
  `name`, component paths like `skills`/`agents`/`hooks`, and a `dependencies` array of
  plugin names with optional semver ranges) plus `.claude-plugin/marketplace.json` (a
  catalog of plugin entries with `source` paths). Claude Code auto-resolves, installs,
  and dedups a plugin's declared `dependencies` — the closest prior art to what this
  repo needed, because it's the same ecosystem this repo targets, and it isn't a soft
  "recommended" tier the way apt's `Recommends` is — dependencies are always installed.
  That's an acceptable fit here: every dependency this repo declares (`create-adr`,
  `yaml-frontmatter` for `handoff-workflow`) is already a genuine hard requirement in
  practice.
- GitHub Copilot CLI / VS Code "Agent Plugins" (Preview) explicitly describe a schema
  "shared between VS Code, GitHub Copilot CLI, and Claude Code": the same `agents/*.md`
  frontmatter shape and the same `skills/{name}/SKILL.md` shape. Confirmed concrete
  differences: Copilot's hook config lives at `hooks.json` (vs. Claude's
  `hooks/hooks.json`), Copilot has no `${CLAUDE_PLUGIN_ROOT}` token, and this repo's own
  pre-existing hand-authored Copilot payloads already use a `*.agent.md` filename
  convention (vs. Claude's plain `*.md`). One detail is unresolved across sources —
  GitHub's own docs put `plugin.json` at the plugin root, while a third-party blog
  describes a `.github/`-nested path as a current preview-implementation quirk. This
  decision follows GitHub's own docs (root `plugin.json`) as authoritative; see
  Consequences for how that risk is contained.
- A direct survey of this repo's own `suites/` found the split described below was
  already latent in the file shapes: `hub-and-spoke-orchestration/` and
  `tiered-team-orchestration/`'s `agents/*.md` files already carry full
  plugin-compatible frontmatter; `handoff-workflow/`'s per-skill directories already
  match the plugin schema's "a `skills` path pointing directly at a `SKILL.md` dir"
  case; but `tiered-escalation-suite/` and `tier-layered-teams/copilot/` are full
  drop-in project payloads (`.github/`, `.vscode/tasks.json`, a `Makefile`,
  `scripts/*.sh`) meant to be copied into a *different* repository's root and run
  there, with hooks in a bespoke pre-plugin format tied to that payload's own build —
  not something a plugin cache install model fits.

## Decision

**A suite becomes a real plugin only when its shape already fits — nothing is force-fit
to gain the label.**

Gets a `.claude-plugin/plugin.json` and a `.claude-plugin/marketplace.json` entry at
repo root (`plugins[]`, `source` pointing at its directory):

- `skills/{name}` (all of them) — a lone `SKILL.md` at plugin root already auto-loads as
  a single-skill plugin; no manifest needed per skill.
- `suites/handoff-workflow` — declares `dependencies: ["create-adr", "yaml-frontmatter"]`.
- `suites/hub-and-spoke-orchestration`, `suites/tiered-team-orchestration` — plain
  `agents/` sets, already plugin-shaped as-is.
- `suites/tier-layered-teams/claude-code/` only — its `copilot/` sibling is unaffected
  (see ADR-0006); it already ships its own hand-mirrored Copilot-native form.

Stays a manual drop-in payload, deliberately not converted:

- `suites/tiered-escalation-suite/`
- `suites/tier-layered-teams/copilot/`

`catalog.sh` surfaces this per suite as `pluginShaped` (has a root
`.claude-plugin/plugin.json`) and `dependencies` (that manifest's `dependencies` array,
`[]` if absent). This is the single source of truth both `install.sh` and
`claude plugin install` (if a user adds this repo as a marketplace directly) read from.

`install.sh` changes to use it:

- **Dependency auto-include**: selecting a suite also selects its declared skill
  dependencies (deduped against anything already selected), with a one-line notice —
  mirrors Claude Code's own plugin installer. `--no-deps` is a single global opt-out, not
  a per-dependency flag: Homebrew shipped exactly that (`:optional`/`:recommended`
  generating `--with-`/`--without-` flags) and removed it in 2.0 for being
  combinatorially untestable across per-user variation.
- **Copilot translation**: for a `pluginShaped` suite only, `translate_to_copilot()`
  renames `agents/*.md` → `agents/*.agent.md` and relocates
  `.claude-plugin/plugin.json` to a root `plugin.json` — a narrow, mechanical rewrite,
  not a general-purpose hook/MCP translator, since the one hook format actually present
  in this repo (the drop-in payloads') is explicitly out of scope. Non-`pluginShaped`
  suites are skipped for `copilot` with a one-line notice (`copilot`'s `harnesses.json`
  mapping now has a `suites` key, but `install.sh`'s per-item filter still leaves the two
  drop-in payloads unreachable through it — same compatibility-by-omission spirit as
  ADR-0003, applied at item granularity instead of category granularity).

`install.sh` still just copies files into a harness's existing directory tree — it does
not shell out to `claude plugin install` or try to emulate its cache/version machinery.
The new `.claude-plugin/marketplace.json` is additive: this repo is also directly usable
via `/plugin marketplace add jean-tessier/ai-personal`, alongside `install.sh`, not
instead of it.

## Consequences

### Positive

- `handoff-workflow`'s dependency on `create-adr`/`yaml-frontmatter` is now a fact a
  machine can act on, not just prose in a README — closing the original gap.
- The repo is a spec-valid Claude Code plugin marketplace as a side effect, usable via
  the native `/plugin` flow with zero extra authoring.
- The Copilot translation is small and mechanical (two operations: a rename, a file
  move) precisely because the eligible suites were chosen for already fitting the
  schema — no hook/MCP translator was needed or written.

### Negative

- The exact Copilot manifest root (`plugin.json` at plugin root) rests on GitHub's docs
  over a conflicting third-party account of current preview behavior. If GitHub's actual
  implementation differs, the fix is confined to `translate_to_copilot()` in
  `install.sh` — a few lines — not a repo-wide restructure, but it's still an assumption
  this decision leans on for a Preview-status feature.
- Claude Code's `dependencies` field has no soft/optional tier — a suite dependency is
  always installed, same as the plugin ecosystem itself. That's accepted as correct for
  every dependency this repo currently declares, but it means this repo has no way to
  express a genuinely optional "nice to have alongside this suite" relationship if one
  arises later; it would need its own mechanism.
- `tiered-escalation-suite` and `tier-layered-teams/copilot/` remain permanently outside
  the plugin/marketplace model — unchanged from before this decision, but now a more
  visible asymmetry since most of `suites/` did convert.

### Neutral

- `install.sh`'s dependency resolution and Copilot translation both read
  `catalog.sh`'s `pluginShaped`/`dependencies` fields rather than parsing
  `.claude-plugin/plugin.json` directly — same "single source of truth in the catalog,
  not re-derived per consumer" pattern `install.sh` already used for `mapping`/`items`.

## References

- `.claude-plugin/marketplace.json`, `suites/{name}/.claude-plugin/plugin.json` — the
  manifests themselves.
- `scripts/catalog.sh` — `pluginShaped`/`dependencies` fields per suite.
- `install.sh`'s `resolve_dependencies()` and `translate_to_copilot()`.
- `scripts/validate.sh`'s `── marketplace ──` section and per-suite plugin.json checks.
- ADR-0003 (compatibility-by-omission) — extended, not superseded: its general principle
  (a harness's `mapping` lists only what survives an unmodified copy or translation) still
  holds.
- ADR-0006 (harness-variant subdirectories) — its structural decision is unaffected and
  still in effect, but this ADR supersedes its stated premise that `copilot`'s
  `harnesses.json` mapping has no `suites` key at all; see ADR-0006's own amended
  `## Status` section.
- `docs/memory/vendor-agnostic-installer.md` — updated with this decision's operational
  notes.
