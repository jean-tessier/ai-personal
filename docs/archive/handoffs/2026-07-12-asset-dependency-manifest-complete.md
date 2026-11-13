---
date: 2026-07-12
description: Built a colocated dependencies.json mechanism so install.sh resolves and installs asset dependencies to a fixed point
status: active
tags: [handoff, archive]
scope: archive.handoffs
---

# Handoff

## What was completed this session

**Task 6 — Docs: ADR-0007 + `docs/memory/vendor-agnostic-installer.md` (final task — overall goal met)**

## Completed work

**Files table**

| File | What it contains |
|---|---|
| `docs/adrs/ADR-0007-colocated-dependency-manifest.md` (new) | ADR recording the colocated-`dependencies.json` decision, mirroring ADR-0003's structure (`Status`/`Context`/`Decision`/`Consequences` with `Positive`/`Negative`/`Neutral`/`References`). Frontmatter: `date: 2026-07-12`, `decision_date: 2026-07-12`, `description` (119 chars, ≤120), `status: accepted`. `Context` notes it was written on `feature/asset-dependency-manifest` after Task 5's commit `e05db75`. `Decision` covers: colocated flat-array `dependencies.json` per asset; `catalog.sh`'s always-present `"dependencies"` field (`[]` default); `validate.sh`'s `_fail`-severity JSON/shape/dangling-path checks; `install.sh`'s `resolve_dependencies()` fixed-point loop with `--yes-deps`/`--no-deps`/prompt/fail-closed-including-under-`--dry-run`; the generic any-category-depends-on-any-category design. `Consequences.Negative` notes no explicit cycle detection (the fixed-point loop still terminates regardless) and no way to express optional/harness-conditional deps. `Consequences.Neutral` documents the bash 3.2 empty-array finding. |
| `docs/adrs/INDEX.md` (modified) | Added one row for ADR-0007, same table shape as the existing 6 rows. |
| `docs/memory/vendor-agnostic-installer.md` (modified, extended in place) | Added: (1) a "Dependency manifest" row under "Where things live", linking to ADR-0007; (2) an expanded "How to validate" paragraph naming `test_deps_*`'s 4 cases; (3) a new bullet in "macOS bash/awk gotchas discovered building this script" for the bash 3.2 empty-array-under-`set -u` issue and why `resolve_dependencies()` uses `$WORK`-scoped temp files instead of arrays; (4) a new `**2026-07-12 update**:` trailing paragraph (matching the file's existing two dated-update-paragraph pattern) summarizing the dependency-resolution feature landing, linking to ADR-0007. No unrelated rewrites — every edit is additive within existing sections/style. |
| `docs/memory/INDEX.md` (modified) | Bumped the `vendor-agnostic-installer.md` row's "Updated" date to 2026-07-12. |

**Key design decisions honored**
- Matched ADR-0003's exact section structure (`Status`/`Context`/`Decision`/`Consequences`/`References`) — no invented shape.
- `docs/memory/vendor-agnostic-installer.md` extended, not rewritten — confirmed via `git diff --stat` before commit: 22 insertions, 3 deletions (deletions are the two "Updated"-date lines being edited inline), no section reordering.
- Absolute date `2026-07-12` used everywhere (frontmatter `date`/`decision_date`, the new trailing-update paragraph, both `INDEX.md` date bumps) — no relative dates.
- Both `INDEX.md` files updated, per repo convention that every new/changed doc is indexed.
- ADR description initially drafted at 132 chars (over the 120-char CLAUDE.md limit); caught by an explicit `python3 -c len(...)` check before commit and shortened to 119 chars.
- Confirmed `0007` was free before creating the file (`ls docs/adrs/` showed ADR-0001 through ADR-0006 only).
- No changes to `install.sh`, `scripts/catalog.sh`, `scripts/validate.sh`, or `scripts/test-install.sh` — diff scoped to the 4 doc files only (confirmed via `git status --porcelain` / `git diff --stat` before staging: exactly `docs/adrs/ADR-0007-*.md` (new), `docs/adrs/INDEX.md`, `docs/memory/vendor-agnostic-installer.md`, `docs/memory/INDEX.md`).

**Test counts / verification**
- `make check` (validate.sh + `node --test scripts/*.test.ts` + `npx tsc --noEmit`): **all passed, exit 0**. `validate.sh`: "All checks passed." (including the pre-existing `suites/handoff-workflow/dependencies.json -> skills/create-adr` / `-> skills/yaml-frontmatter` `ok` lines from Task 3, unaffected by this session's docs-only changes). Node tests: 12/12 pass. `tsc --noEmit`: no output (clean).
- No code files touched this session, so no code-level tests were re-run beyond `make check`'s existing coverage.

## Phase state

| Task | Status | Notes |
|---|---|---|
| Task 1 — Design the dependency mechanism | ✅ Done (prior session) | Colocated `dependencies.json` manifest; now recorded in ADR-0007 |
| Task 2 — `catalog.sh`: `dependencies` field | ✅ Done (prior session) | Additive-only; `make check` green |
| Task 3 — `validate.sh`: structural checks | ✅ Done (prior session) | JSON validity + flat-array shape + dangling-path, all `_fail` severity; `make check` green |
| Task 4 — `install.sh`: `resolve_dependencies()` + flags | ✅ Done (prior session) | Fixed-point transitive resolution + `--yes-deps`/`--no-deps`; `make check` green |
| Task 5 — `scripts/test-install.sh`: new test cases | ✅ Done (prior session) | 4 required `test_deps_*` cases, 45/45 passing; optional 5th not added (see Open items) |
| Task 6 — Docs: ADR-0007 + `docs/memory/vendor-agnostic-installer.md` | ✅ Done this session | ADR-0007 created, both `INDEX.md` files updated, memory doc extended in place; `make check` green; committed as `d4cdbec` |

**All 6 tasks are complete. The overall goal is met**: `install.sh` now has a generic, colocated
dependency-manifest mechanism — installing `suites/handoff-workflow` automatically resolves and
offers/adds its dependencies (`skills/create-adr`, `skills/yaml-frontmatter`) via `catalog.sh`
surfacing them, `validate.sh` structurally checking them, and `install.sh`'s
`resolve_dependencies()` acting on them (`--yes-deps`/`--no-deps`/interactive-prompt/fail-closed),
with test coverage (`scripts/test-install.sh`'s `test_deps_*`, 4 cases) and durable documentation
(ADR-0007, `docs/memory/vendor-agnostic-installer.md`) recording the design. No further tasks are
planned on this branch.

## Open items

| # | Item | Status |
|---|---|---|
| 1 | `test_deps_unsupported_category_warns` (optional 5th test case from Task 5) | Open, non-blocking — never added; Task 4 already verified the path manually (unsupported-category dependency → `_warn` + exit 0, not a hard failure). Documented as a known gap in this session's memory-doc update. Captured in `docs/memory/deferred-items.md` (item 9). |
| 2 | Interactive-prompt UX for dependency resolution (single batched `Add them? [Y/n]`) | ✅ Resolved (Task 4) — not exercised by an automated test (no TTY available in this environment); not required by any task's Definition of Done. No action needed. |
| 3 | Whether/when to merge `feature/asset-dependency-manifest` into `main` | Open, out of scope for this handoff loop entirely — no task in the original 6-task plan addressed merging, and this session was not instructed to open a PR. Captured in `docs/memory/deferred-items.md` (item 10). Left for the user to decide separately. |

## Decisions from upfront clarification (for record — loop is now closed)

1. **Commit policy honored throughout**: one commit per task, Conventional Commits format. Task 6 committed as `d4cdbec docs: record dependency-manifest decision (ADR-0007) and update installer memory doc` — doc files only (`docs/adrs/ADR-0007-*.md`, `docs/adrs/INDEX.md`, `docs/memory/vendor-agnostic-installer.md`, `docs/memory/INDEX.md`); this `handoff.md` left uncommitted for the orchestrator, matching every prior task's pattern.
2. No push to any remote occurred at any point in this effort. Local commits only.
3. Branch `feature/asset-dependency-manifest` was used throughout — no new branch created, no switch.
4. Task 1's design decisions were honored as final in every subsequent task and are now the durable record in ADR-0007.

## Standing notes (loop terminates here)

This was the last task in the original 6-task plan. `ingest-handoff` was **not** invoked by this
session, per the explicit override in this run's instructions — that is the top-level
orchestrator's job to run once, after this session, with full cross-session context across all 6
tasks. This `handoff.md` is intentionally left uncommitted so the orchestrator can read it before
deciding next steps (ingest, archive, or otherwise close out the effort).
