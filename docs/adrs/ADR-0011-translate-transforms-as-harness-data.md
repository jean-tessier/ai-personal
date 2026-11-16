---
date: 2026-11-15
decision_date: 2026-11-15
description: Per-harness translate transforms live in harnesses.json; ineligible items and dependencies are warned and skipped
status: accepted
---

# ADR-0011: Per-Harness `translate` Transforms as Data

## Status

Accepted — partially supersedes [ADR-0007](ADR-0007-suites-as-native-plugins.md) (the gate that
decides when the Copilot translation runs) and reconciles
[ADR-0003](ADR-0003-data-driven-harness-manifest.md).

## Context

ADR-0007 made `install.sh` translate plugin-shaped suites for Copilot after copying them. The
decision to run that translation was a hardcoded helper, `is_copilot_suite_category()`
(`[[ "$HARNESS" == "copilot" && "$category" == "suites" ]]`), originally called from three places
(one, `plan_item()`, by the time of this change). That put a
harness name back into `install.sh`'s control flow, which ADR-0003 was written to prevent
(deferred item #9).

Separately, `resolve_dependencies()` once checked only `mapping` for a dependency and skipped the
plugin-shaped filter that requested items got. That was fixed before this change (#15), and both
paths now go through `plan_item()` (#21), so a dependency on a non-plugin-shaped suite is already
warned and skipped for `--harness copilot`.

## Decision

**A harness may declare an optional `translate` object in `scripts/harnesses.json`: category →
transform name**, a sibling of `mapping`. `mapping` values stay plain strings.

```json
"copilot": {
  "mapping":   { "skills": "skills/{name}", "suites": "suites/{name}" },
  "translate": { "suites": "copilot-plugin" }
}
```

`install.sh` holds a small registry keyed by **transform name, never harness name**:
`transform_eligible <transform> <name>` (0 eligible, 1 not eligible, 2 unknown transform) and
`transform_apply <transform> <dest>`. `plan_item()` asks `_json translate "$HARNESS" "$category"`.
If a transform is set and the item is not eligible, `plan_item()` warns and skips it; otherwise the
selection row carries the transform name and `apply_selection()` calls `transform_apply` after the
copy. `is_copilot_suite_category()` and every harness-name literal in control flow are removed.

An unknown transform name warns and skips the item. `validate.sh` catches it earlier: `translate`
categories must be keys of the same harness's `mapping`, and values must be known transform names
(currently `copilot-plugin`).

**Ineligible items are warned and skipped, including dependencies.** A suite that is not
plugin-shaped is skipped for a harness whose `translate` covers its category, whether it was
requested or pulled in as a dependency. This is the same degrade-gracefully behaviour ADR-0009
already gives a dependency in an unmapped category.

## Consequences

### Positive

- ADR-0003's rule holds again: `install.sh` never branches on a harness name.
- A harness that reuses an existing transform needs only a JSON edit.
- One place (`plan_item()`) applies the rule to requested items and dependencies alike.

### Negative

- A *new kind of transform* is not a JSON-only change: it needs a case in `transform_eligible`
  and `transform_apply`, plus the name added to `validate.sh`'s known list. ADR-0003's "adding a
  harness is a JSON edit" is true only for harnesses that reuse an existing transform.
- The transform names are a second vocabulary to keep in sync between `install.sh` and
  `validate.sh`.

### Neutral

- Installed files are byte-identical for every existing run. Two notes changed text: the dry-run
  annotation, from `(copilot-translated)` to `(translated: <transform>)`, and the
  not-plugin-shaped skip note, from `no Copilot translation available` to
  `no '<transform>' translation available`.
- The rest of ADR-0007 (plugin-shaped suites, the Copilot translation itself, `pluginShaped` in the
  catalog) is unaffected. Its dependency half stays superseded by ADR-0009; ADR-0009 is not
  superseded by this one.

## References

- `scripts/harnesses.json` — the `translate` key.
- `install.sh` — `plan_item()`, `transform_eligible()`, `transform_apply()`,
  `translate_to_copilot()`.
- `scripts/validate.sh` — harness vocabulary lint; `scripts/test-install.sh` —
  `test_translate_lint_rejects_bad_key`.
- `docs/memory/deferred-items.md` — item 9, resolved by this change.
