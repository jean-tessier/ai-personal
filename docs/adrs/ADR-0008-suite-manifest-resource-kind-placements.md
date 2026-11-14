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

ADR-0006 (since superseded by ADR-0007 for the copilot-suites premise below) gave multi-harness suites a shape — canonical docs at the suite root, one subdirectory per
harness variant named by that harness's `scripts/harnesses.json` key — but accepted two tradeoffs
alongside it, using `suites/tier-layered-teams` (the first and, so far, only suite in this shape) as
the concrete case:

- `install.sh --harness claude-code --assets suites` copies the entire suite directory verbatim,
  including sibling-harness subdirectories nothing on the current harness reads — "documented dead
  weight" rather than fixed, since excluding it would mean `install.sh` branching on suite-internal
  structure.
- `copilot`'s `harnesses.json` entry now has a `suites` mapping (ADR-0007), but `select_assets()`
  only routes `pluginShaped` suites (a root `.claude-plugin/plugin.json`) through
  `translate_to_copilot()`. `tier-layered-teams/copilot/` is a drop-in payload, not a plugin, so it
  stays a manual `cp -R suites/tier-layered-teams/copilot/. <target>/` even though `install.sh`
  supports the copilot harness for other suites.

Underlying both gaps: `harnesses.json`'s `suites` mapping is a single destination template per
harness (`"suites/{name}"`), too coarse to say "copy only this subtree" or "this harness's variant
isn't a rename-copy at all — parts of it are individual role prompts, parts are a payload that
overlays onto the target repo's own root (`Makefile`, `.vscode/`, an always-on instructions file)."
Both a `tier-layered-teams` walkthrough and a design discussion converged on a colocated manifest,
peer to ADR-0009's `dependencies.json`, that declares this per suite without `install.sh` ever
branching on a suite's name — preserving ADR-0003's data-driven, compatibility-by-omission design.

## Decision

**A colocated `manifest.json` per multi-harness suite**, sibling to ADR-0009's `dependencies.json`.
A suite with no `manifest.json` keeps today's flat wholesale-copy behavior unchanged — single-harness
suites (`handoff-workflow`, `hub-and-spoke-orchestration`, `tiered-team-orchestration`,
`tiered-escalation-suite`) are unaffected.

**Precedence.** When `manifest.json` is present it replaces `mapping.suites` and ADR-0007's
`translate_to_copilot()` path for every harness it keys. Three cases, one outcome each:

- A harness the manifest keys: install exactly its placements.
- A harness the manifest omits: skipped with a one-line notice, even if its `mapping.suites` exists
  (compatibility by omission, as in ADR-0003).
- A `pluginShaped` suite that also has a manifest: the manifest wins and no translation runs. The
  claude-code example therefore places `claude-code/.claude-plugin` so the install stays a plugin;
  copilot content comes from its own placements, never from translated `agents/*.md`.

**Keyed by harness name**, matching `scripts/harnesses.json`'s own keys — that file remains the
naming authority (same principle ADR-0006 already established for variant subdirectory names). Each
harness's value is a list of **placements**:

```json
{
  "claude-code": [
    { "kind": "agents", "src": "claude-code/agents",         "mode": "copy" },
    { "kind": "config", "src": "claude-code/.claude-plugin", "mode": "copy" }
  ],
  "copilot": [
    { "kind": "agents",       "src": "copilot/.github/agents",                  "mode": "copy"  },
    { "kind": "skills",       "src": "copilot/.github/skills",                  "mode": "copy"  },
    { "kind": "instructions", "src": "copilot/.github/copilot-instructions.md", "mode": "merge" },
    { "kind": "hooks",        "src": "copilot/.github/hooks",                  "mode": "copy"  },
    { "kind": "config",       "src": "copilot/.vscode",                        "mode": "merge" },
    { "kind": "config",       "src": "copilot/Makefile",                       "mode": "merge" },
    { "kind": "config",       "src": "copilot/scripts",                        "mode": "merge" },
    { "kind": "config",       "src": "copilot/.gitignore",                     "mode": "merge" },
    { "kind": "config",       "src": "copilot/scratch",                        "mode": "merge" }
  ]
}
```

A placement is three fields:

1. **`kind`** — a small, harness-agnostic vocabulary for what a resource *is*, not where it goes.
   Five kinds, each with a concrete referent in `tier-layered-teams` today — the vocabulary is not
   speculative:
   - `agents` — one-file-per-role prompts (claude-code `agents/`, copilot `.github/agents/*.agent.md`)
   - `skills` — skill directories nested inside a suite variant (copilot's `.github/skills/*`),
     same shape as the top-level `skills` category
   - `instructions` — a singleton always-on context file (`copilot-instructions.md`); no per-item
     name, exactly one destination regardless of the suite's own name
   - `hooks` — agent-hook definitions (copilot `.github/hooks/*.json`), including the gate that
     blocks `--apply` until `./scratch/handoff/pending.diff` exists
   - `config` — variant-root passthrough placed at its own relative path (`{relpath}`): copilot's
     `Makefile`, `.vscode/`, `scripts/`, `.gitignore`, `scratch/`; claude-code's `.claude-plugin/`
2. **`src`** — a suite-relative path (directory or single file) to place. Every item under a
   directory `src` inherits that placement's `kind`/`mode`; nothing is enumerated by filename.
3. **`mode`** — `"copy"` places fresh content (today's create-only behavior); `"merge"` overlays
   onto a path that may already exist in the target repo without clobbering it. This ADR fixes the
   vocabulary and which placements need which mode; it does not specify merge's conflict-resolution
   behavior — that is implementation, deferred (see Consequences).

**Destination paths per kind live in `scripts/harnesses.json`, not in the suite's manifest** — a new
`resourceKinds` map alongside the existing `mapping`, e.g.:

```json
"claude-code": {
  "mapping": { "skills": "skills/{name}", "suites": "suites/{name}" },
  "resourceKinds": {
    "project": {
      "agents": ".claude/suites/{suite}/agents/{basename}",
      "config": ".claude/suites/{suite}/{relpath}"
    },
    "user": {
      "agents": "~/.claude/suites/{suite}/agents/{basename}",
      "config": "~/.claude/suites/{suite}/{relpath}"
    }
  }
},
"copilot": {
  "mapping": { "skills": "skills/{name}", "suites": "suites/{name}" },
  "resourceKinds": {
    "project": {
      "agents":       ".github/agents/{basename}",
      "skills":       ".github/skills/{basename}",
      "hooks":        ".github/hooks/{basename}",
      "instructions": ".github/copilot-instructions.md",
      "config":       "{relpath}"
    }
  }
}
```

**Resolution rules.** `resourceKinds` is keyed per scope, and its templates resolve as `resolve_root()`
in `install.sh` resolves paths: a relative template against the target **project root** (`$PWD`),
a `~/` template against `$HOME`, not against the scope root that `mapping` templates use
(copilot's `.github`); a kind missing for the chosen scope is skipped by omission, as in ADR-0003.
Placeholders:

- `{suite}` — the suite's directory name.
- `{basename}` — for `agents`, `skills`, and `hooks`, the item is each immediate child of the
  directory `src` (a file, or a skill directory copied whole); `{basename}` is that child's name.
- `{relpath}` — for `config`, the item is `src` itself (file or directory, copied recursively);
  `{relpath}` is its path relative to `dirname(src)`, so `copilot/.vscode` becomes `.vscode` (keeping
  `.vscode/settings.json`), `copilot/Makefile` becomes `Makefile`, and `copilot/scripts` becomes
  `scripts`.

A template with no placeholder (`instructions`) is a fixed singleton destination. Traced through
these rules, every copilot placement lands where `cp -R suites/tier-layered-teams/copilot/. <target>/`
puts it today. In the claude-code example the plugin shape is preserved under
`.claude/suites/{suite}/`, so `claude-code/agents/00-escalation-protocol.md` (no agent frontmatter,
linked relatively from 01-04) stays beside its siblings as it does today rather than landing in
`.claude/agents/`. This split is what makes the schema extend to a future harness without touching
any existing suite's manifest: a new harness needs only its own `resourceKinds` map; a suite opts in
by adding one manifest entry using the existing kind vocabulary.

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
- `copilot` (and any future harness) becomes installable per suite, per kind, instead of
  `mapping.suites`' all-or-nothing, plugin-shaped-only reach — a drop-in payload like
  `tier-layered-teams/copilot/` can be installed without becoming a plugin.
- Adding a harness is additive (give it a `resourceKinds` map); adding a suite variant is additive
  (tag its subtrees with the existing kind vocabulary). Neither requires an `install.sh` code change
  — preserves ADR-0003's no-branching-on-harness-name design.
- Manifest stays small and low-drift: directory/file-level tagging, not per-item enumeration.

### Negative

- `merge` mode's actual placement semantics (what happens when the target repo already has a
  `Makefile`, `.vscode/`, or `copilot-instructions.md`) are undecided by this ADR. `install.sh` has
  no merge capability today, so a manifest that declares `mode: "merge"` currently describes intent
  nothing executes — real conflict-resolution behavior is deferred implementation work.
- The kind vocabulary (`agents`/`skills`/`instructions`/`hooks`/`config`) is derived from the one existing
  multi-harness suite. A future suite or harness may need a kind this list doesn't cover; growing the
  vocabulary is additive, not breaking, but is a real open edge, not a closed one.
- Suites now have two optional colocated JSON files (`dependencies.json` from ADR-0009,
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
  subdirectory convention (superseded by ADR-0007 for its copilot-suites premise); the "documented dead
  weight" tradeoff this ADR addresses.
- ADR-0007 (`docs/adrs/ADR-0007-suites-as-native-plugins.md`) — suites as native plugins; added
  copilot's `suites` mapping and the `pluginShaped`/`translate_to_copilot()` path the manifest
  precedence rule overrides.
- ADR-0009 (`docs/adrs/ADR-0009-colocated-dependency-manifest.md`) — colocated
  `{category}/{name}/dependencies.json`; the sibling per-asset JSON file convention `manifest.json`
  reuses.
- `scripts/harnesses.json` — gains a `resourceKinds` map per harness (not yet implemented).
- `suites/tier-layered-teams/` — the suite this schema was designed against; not yet migrated.
