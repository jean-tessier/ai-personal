---
date: 2026-07-09
decision_date: 2026-07-09
description: Multi-harness suites get per-harness subdirs named by harnesses.json keys; shared canonical docs stay at the suite root
status: superseded
superseded_by: ADR-0007
---

# ADR-0006: Harness-Variant Subdirectories Within a Suite

## Status

Superseded (2026-07-13) — `copilot`'s `harnesses.json` mapping now has a `suites` key
(see [ADR-0007](ADR-0007-suites-as-native-plugins.md)), which this ADR's Context and
Decision sections state does not exist. The structural decision itself — harness-variant
subdirectories named by `harnesses.json` keys, shared canonical docs at the suite root,
provenance headers on mirrored sections — is untouched and still in effect; only the
copilot-mapping premise below is outdated. `suites/tier-layered-teams/copilot/` remains a
manual `cp -R` payload either way, now because it isn't plugin-shaped rather than because
no mapping exists for `copilot` at all.

## Context

Every suite in `suites/` has, until now, targeted exactly one harness: `hub-and-spoke-orchestration`
and `tiered-team-orchestration` are Claude Code agent-prompt sets, `tiered-escalation-suite` is a
GitHub Copilot/VS Code drop-in payload, `handoff-workflow` is a Claude Code skill-set.
`suites/README.md` documents two shapes for a suite's contents — a numbered `agents/` prompt group,
or one subdirectory per component skill — but both assume a single target harness per suite.

`suites/tier-layered-teams/` breaks that assumption: it needs to ship both a Claude Code-native form
(numbered role-prompt files under `agents/`) and a Copilot-native form (a drop-in payload mirroring a
target repo's root — `.github/`, `.vscode/`, `Makefile`, `scripts/`) from the same suite, because the
pattern itself (a two-axis model-cost/tool-escalation lattice) is harness-agnostic even though its two
implementations are not. The installer only maps `suites` for `claude-code` — the `copilot` entry in
`scripts/harnesses.json` has no `suites` key (see ADR-0003's compatibility-by-omission decision) — so
a Copilot-native variant inside a suite can never be placed by `install.sh`; it's always a manual
`cp -R`, same as `tiered-escalation-suite`.

Without a documented convention, each multi-harness suite would invent its own split between
harness-agnostic and harness-native content, and any shared "must not drift between variants" rules
(e.g. tool-escalation tiers meaning the same thing in both the Claude Code and Copilot forms) would
have no single home.

## Decision

A suite that ships multiple harness-native variants follows this shape:

1. Harness-agnostic canonical docs live at the suite root: `README.md` (the pattern), `USAGE.md`
   (per-variant invocation), and optionally `PROTOCOL.md` (shared must-not-drift semantics).
2. One subdirectory per harness variant, named *exactly* by that harness's key in
   `scripts/harnesses.json` (e.g. `claude-code/`, `copilot/`) — the harness manifest is the naming
   authority, not suite-local judgment.
3. Each variant subdirectory contains the harness-native tree verbatim: for `claude-code`, an
   `agents/` directory of numbered role-prompt files; for `copilot`, a drop-in payload mirroring a
   target repo's root (`.github/`, `.vscode/`, `Makefile`, `scripts/`, …).
4. Shared must-not-drift semantics live once at the suite root (`PROTOCOL.md`); each variant embeds
   a runtime mirror marked with a provenance header ("Canonical source: `<relative path>` — edit
   there first, then mirror here"). Runtime copies are forced — Copilot payloads are copied away from
   this repo entirely, so they can't reference the root file at runtime — so the duplication is
   explicit and marked, not silent.
5. No tooling changes. `scripts/validate.sh`'s existing suite checks (a `README.md` at the suite
   root, at least one `.md` inside a component subdirectory) already pass on this shape unmodified.
   Copilot-native variants remain manual `cp -R` payloads — same precedent as
   `tiered-escalation-suite` — since the `copilot` harness mapping in `harnesses.json` deliberately
   has no `suites` key. `install.sh`'s `claude-code` `suites` mapping copies the entire suite
   directory verbatim, so it copies the `copilot/` sibling too — accepted as documented dead weight
   rather than special-cased away.
6. Single-harness suites are unaffected. Variant subdirectories are optional structure that only
   applies once a suite ships more than one harness-native form.

## Consequences

### Positive

- Drift between the shared pattern and its harness-native forms is contained: `PROTOCOL.md` is the
  one place semantics are edited, and the provenance header on each mirror makes staleness a visible,
  greppable fact instead of a silent two-copies-diverging risk.
- Adding a harness variant to an existing multi-harness suite is "add one subdirectory named by that
  harness's `scripts/harnesses.json` key" — no change to `install.sh`, `scripts/validate.sh`, or
  `scripts/catalog.sh`.
- The naming authority for variant subdirectories is external and already-maintained
  (`scripts/harnesses.json`), so there's no separate vocabulary to keep in sync.

### Negative

- `install.sh --harness claude-code --assets suites` copies a suite's `copilot/` subdirectory too,
  even though nothing on the Claude Code side reads it — inert bytes land in the target project's
  `.claude/suites/{name}/copilot/`. Accepted rather than fixed, since excluding it would mean
  `install.sh` branching on suite-internal structure, which the installer's data-driven design
  (ADR-0003) deliberately avoids.
- The provenance header is a convention, not an enforced check — nothing currently fails
  `scripts/validate.sh` if a variant's mirrored section is edited without updating the canonical
  `PROTOCOL.md` first, or vice versa.

### Neutral

- Copilot-native variants inside a multi-harness suite remain permanently manual (`cp -R`), just like
  the existing single-harness `tiered-escalation-suite` — this decision doesn't change how Copilot
  payloads get delivered, only where they live inside a suite that also has a Claude Code form.

## References

- `scripts/harnesses.json` — naming authority for variant subdirectory names.
- ADR-0003 (`docs/adrs/ADR-0003-data-driven-harness-manifest.md`) — compatibility-by-omission; why
  `copilot`'s mapping has no `suites` key.
- `suites/README.md` — documents this shape alongside the existing single-harness suite shapes.
- `suites/tiered-escalation-suite/` — precedent for a manual `cp -R` Copilot-native payload.
- `suites/tier-layered-teams/` — first suite to use this shape.
