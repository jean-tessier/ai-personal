---
date: 2026-07-01
decision_date: 2026-07-01
description: Declare harnesses in scripts/harnesses.json, not as branches in install.sh; a missing mapping key means "incompatible", not an error
status: accepted
---

# ADR-0003: Data-Driven Harness Manifest, With Compatibility-by-Omission

## Status

Accepted

## Context

`install.sh` (the vendor-agnostic installer built on `feature/vendor-agnostic-installer`) needs to
support multiple target harnesses (today: `claude-code`, `copilot`) that each store assets under a
different root (`.claude` vs. `.github`) and only accept some of this repo's asset categories.
Every harness/scope/asset-category combination could have been written as `if`/`case` branches
directly in `install.sh` — e.g. `if [[ "$HARNESS" == "claude-code" ]]; then ...`. That would work
for two harnesses, but adding a third harness would mean editing the script's control flow rather
than just describing the new harness.

Note: this branch has no commits yet beyond `main`'s tip (`git log` shows
`feature/vendor-agnostic-installer` and `main` both at `1763ef7`) — every file described here
(`install.sh`, `scripts/harnesses.json`) is uncommitted working-tree state at the time this ADR is
written. This decision predates any commit.

## Decision

Harnesses are declared entirely in a data file, `scripts/harnesses.json`, keyed by harness name:

```json
{
  "claude-code": {
    "label": "Claude Code",
    "scopes": { "project": ".claude", "user": "~/.claude" },
    "mapping": { "skills": "skills/{name}", "tasks": "commands/{name}.md", "workflows": "workflows/{name}" }
  },
  "copilot": {
    "label": "GitHub Copilot / VS Code",
    "scopes": { "project": ".github" },
    "mapping": { "skills": "skills/{name}" }
  }
}
```

`install.sh` never branches on a harness name. Its `_json()` dispatcher (a single python3 heredoc)
answers generic questions — `harness_exists`, `scope_root`, `mapping` — purely by looking up keys in
this file. `select_assets()` loops over asset categories and, for each one, asks `_json mapping
"$HARNESS" "$category"` for a destination template; if that lookup fails (the category key is
simply absent from that harness's `mapping` object), the category is skipped with a `_warn`, not
treated as an error. This is compatibility-by-omission: a harness's `mapping` object is a complete,
explicit list of what it accepts, and anything left out is understood as "this harness doesn't
support that asset type" — the same code path handles a not-yet-supported category and a
deliberately-unsupported one identically, with no separate "is this combination valid" table to
keep in sync.

Adding a third harness (or a new asset category) is a JSON edit to `scripts/harnesses.json`, never
a change to `install.sh`'s logic.

## Consequences

### Positive

- Adding a harness requires zero changes to `install.sh`'s control flow — only a new entry in
  `scripts/harnesses.json`. `scripts/validate.sh`'s `── harnesses ──` section structurally lints
  every entry (non-empty `label`, at least one `scopes` key, at least one `mapping` key) so a
  malformed new entry fails validation rather than failing silently at install time.
- "This harness doesn't support category X" requires no special-case code — an absent mapping key
  and a not-yet-implemented mapping key look identical to `select_assets()`, and both produce the
  same clean `_warn`-and-skip behavior instead of a crash or a silent no-op.

### Negative

- A typo'd or missing mapping key is silently interpreted as "unsupported," not flagged as a
  possible mistake — `scripts/validate.sh` only checks that `mapping` is non-empty overall, not
  that it contains every category a maintainer might have intended it to.
- All the semantics live in a JSON file with no schema enforcement beyond `scripts/validate.sh`'s
  hand-written structural checks (no JSON Schema file, no python-side validation beyond
  presence/type checks).

### Neutral

- `scope_root`/`mapping` lookups in `_json()` use plain dict `.get()` with a `None`-means-"exit 1"
  convention (see `install.sh` lines ~86–102) — the same lookup-returns-nothing-means-absent idiom
  is reused for both scopes and mappings, keeping the dispatcher's four query modes structurally
  identical.

## References

- `scripts/harnesses.json` — the manifest itself.
- `install.sh` `_json()` (the `mapping`/`scope_root`/`harness_exists` modes) and `select_assets()`
  (the `_warn`-and-skip-on-missing-mapping behavior).
- `scripts/validate.sh`'s `── harnesses ──` section — structural lint for this file.
- `handoff.md` (this branch's session record) — Task 2 ("Build `scripts/harnesses.json`") and
  Task 3 ("Build `install.sh` core").
