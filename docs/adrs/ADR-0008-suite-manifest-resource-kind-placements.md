---
date: 2026-07-16
decision_date: 2026-07-16
description: Colocated manifest.json declares per-harness placements (kind, src, mode); harnesses.json owns per-kind destinations
status: accepted
---

# ADR-0008: Suite Manifest Schema — Harness-Keyed Resource-Kind Placements

## Status

Accepted. This ADR locks in schema shape and vocabulary only — `scripts/catalog.sh`,
`scripts/validate.sh`, and `install.sh` do not yet read, validate, or consume `manifest.json`, and
`suites/tier-layered-teams` has not yet been migrated to use it. Implementation is deferred future
work, not part of this decision.

## Context

ADR-0006 gave multi-harness suites a shape — canonical docs at the suite root, one subdirectory per
harness variant named by that harness's `scripts/harnesses.json` key — but accepted two tradeoffs
alongside it, using `suites/tier-layered-teams` (the first and, so far, only suite in this shape) as
the concrete case:

- `install.sh --harness claude-code --assets suites` copies the entire suite directory verbatim,
  including sibling-harness subdirectories nothing on the current harness reads — "documented dead
  weight" rather than fixed, since excluding it would mean `install.sh` branching on suite-internal
  structure.
- `copilot`'s entry in `harnesses.json` has no `suites` key at all, so a suite's `copilot/` variant
  can never be placed by `install.sh` regardless of suite shape — always a manual `cp -R`. This is a
  category-level, all-or-nothing gap: no suite can offer `install.sh` support for the `copilot`
  harness, even one whose `copilot/` variant would install cleanly today (e.g. `tier-layered-teams`'s
  `.github/agents/*.agent.md` files, which are safe per-item copies, same shape as
  `tiered-escalation-suite`'s manual precedent).

Underlying both gaps: `harnesses.json`'s `suites` mapping is a single destination template per
harness (`"suites/{name}"`), too coarse to say "copy only this subtree" or "this harness's variant
isn't a rename-copy at all — parts of it are individual role prompts, parts are a payload that
overlays onto the target repo's own root (`Makefile`, `.vscode/`, an always-on instructions file)."
Both a `tier-layered-teams` walkthrough and a design discussion converged on a colocated manifest,
peer to ADR-0007's `dependencies.json`, that declares this per suite without `install.sh` ever
branching on a suite's name — preserving ADR-0003's data-driven, compatibility-by-omission design.

## Decision

**A colocated `manifest.json` per multi-harness suite**, sibling to ADR-0007's `dependencies.json`.
A suite with no `manifest.json` keeps today's flat wholesale-copy behavior unchanged — single-harness
suites (`handoff-workflow`, `hub-and-spoke-orchestration`, `tiered-team-orchestration`,
`tiered-escalation-suite`) are unaffected.

**Keyed by harness name**, matching `scripts/harnesses.json`'s own keys — that file remains the
naming authority (same principle ADR-0006 already established for variant subdirectory names). Each
harness's value is a list of **placements**:

```json
{
  "claude-code": [
    { "kind": "agents", "src": "claude-code/agents", "mode": "copy" }
  ],
  "copilot": [
    { "kind": "agents",       "src": "copilot/.github/agents",                  "mode": "copy"  },
    { "kind": "skills",       "src": "copilot/.github/skills",                  "mode": "copy"  },
    { "kind": "instructions", "src": "copilot/.github/copilot-instructions.md", "mode": "merge" },
    { "kind": "config",       "src": "copilot/.vscode",                        "mode": "merge" },
    { "kind": "config",       "src": "copilot/Makefile",                       "mode": "merge" },
    { "kind": "config",       "src": "copilot/scripts",                        "mode": "merge" }
  ]
}
```

A placement is three fields:

1. **`kind`** — a small, harness-agnostic vocabulary for what a resource *is*, not where it goes.
   Four kinds, each with a concrete referent in `tier-layered-teams` today — the vocabulary is not
   speculative:
   - `agents` — one-file-per-role prompts (claude-code `agents/`, copilot `.github/agents/*.agent.md`)
   - `skills` — skill directories nested inside a suite variant (copilot's `.github/skills/*`),
     same shape as the top-level `skills` category
   - `instructions` — a singleton always-on context file (`copilot-instructions.md`); no per-item
     name, exactly one destination regardless of the suite's own name
   - `config` — repo-root passthrough that mirrors the target repo's own conventions
     (`Makefile`, `.vscode/`, `scripts/`)
2. **`src`** — a suite-relative path (directory or single file) to place. Every item under a
   directory `src` inherits that placement's `kind`/`mode`; nothing is enumerated by filename.
3. **`mode`** — `"copy"` places fresh content (today's create-only behavior); `"merge"` overlays
   onto a path that may already exist in the target repo without clobbering it. This ADR fixes the
   vocabulary and which placements need which mode; it does not specify merge's conflict-resolution
   behavior — that is implementation, deferred (see Consequences).

**Destination paths per kind live in `scripts/harnesses.json`, not in the suite's manifest** — a new
`resourceKinds` map alongside the existing `mapping`, e.g.:

```json
"copilot": {
  "mapping": { "skills": "skills/{name}" },
  "resourceKinds": {
    "agents":       ".github/agents/{basename}",
    "skills":       ".github/skills/{basename}",
    "instructions": ".github/copilot-instructions.md",
    "config":       "{basename}"
  }
}
```

A `{basename}` placeholder preserves the source item's own filename (directory placements fan out
per item); a template with no placeholder (`instructions`) is a fixed singleton destination. This
split is what makes the schema extend to a future harness without touching any existing suite's
manifest: a new harness needs only its own `resourceKinds` map; a suite opts in by adding one
manifest entry using the existing kind vocabulary.

**Suite-root shared docs (`README.md`, `USAGE.md`, `PROTOCOL.md`) get no kind and are never
installed.** They stay repo-only reference material describing the harness-agnostic pattern; only
harness-native content under a variant subdirectory is ever placed at a target repo. This reverses
today's incidental behavior, where the flat wholesale copy installs them by accident.

**Tagging is at directory/file granularity, never per-item.** No manifest enumerates individual
agent or skill filenames — that would be a second listing that has to stay in sync with the
filesystem, the same drift ADR-0006 already fought once with `PROTOCOL.md`'s mirrored copies.

## Consequences

### Positive

- A claude-code install of a multi-harness suite stops dragging in inert sibling-harness bytes —
  fixes ADR-0006's accepted "documented dead weight" tradeoff.
- `copilot` (and any future harness) becomes installable per suite, per kind, instead of the current
  categorical all-or-nothing gap — a suite manifest can offer `copilot` support even though
  `harnesses.json`'s `copilot.mapping` still has no `suites` key.
- Adding a harness is additive (give it a `resourceKinds` map); adding a suite variant is additive
  (tag its subtrees with the existing kind vocabulary). Neither requires an `install.sh` code change
  — preserves ADR-0003's no-branching-on-harness-name design.
- Manifest stays small and low-drift: directory/file-level tagging, not per-item enumeration.

### Negative

- `merge` mode's actual placement semantics (what happens when the target repo already has a
  `Makefile`, `.vscode/`, or `copilot-instructions.md`) are undecided by this ADR. `install.sh` has
  no merge capability today, so a manifest that declares `mode: "merge"` currently describes intent
  nothing executes — real conflict-resolution behavior is deferred implementation work.
- The kind vocabulary (`agents`/`skills`/`instructions`/`config`) is derived from the one existing
  multi-harness suite. A future suite or harness may need a kind this list doesn't cover; growing the
  vocabulary is additive, not breaking, but is a real open edge, not a closed one.
- Suites now have two optional colocated JSON files (`dependencies.json` from ADR-0007,
  `manifest.json` from this ADR) — both small and both "colocated over centralized," but a suite
  author now has two conventions to know about instead of one.

### Neutral

- No code exists yet. `scripts/catalog.sh`, `scripts/validate.sh`, and `install.sh` need to read,
  validate, and consume `manifest.json`; `scripts/harnesses.json` needs its `resourceKinds` maps;
  `suites/tier-layered-teams` needs migrating to declare one. None of that is scoped by this ADR.

## References

- ADR-0003 (`docs/adrs/ADR-0003-data-driven-harness-manifest.md`) — data-driven harness manifest and
  compatibility-by-omission; the no-suite-name-branching principle this schema preserves.
- ADR-0006 (`docs/adrs/ADR-0006-harness-variant-subdirectories-in-suites.md`) — harness-variant
  subdirectory convention; the "documented dead weight" and categorical copilot-suites gap this ADR
  addresses.
- ADR-0007 (`docs/adrs/ADR-0007-colocated-dependency-manifest.md`) — colocated
  `{category}/{name}/dependencies.json`; the sibling per-asset JSON file convention `manifest.json`
  reuses.
- `scripts/harnesses.json` — gains a `resourceKinds` map per harness (not yet implemented).
- `suites/tier-layered-teams/` — the suite this schema was designed against; not yet migrated.
