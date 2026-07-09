---
name: handoff-document
description: Use when completing a working session with multi-session tasks remaining — write or update handoff.md at the project root before ending the conversation so the next session can pick up immediately without re-reading design docs.
---

# Handoff Document

## Overview

Write `handoff.md` at the project root to carry session context forward. The test: the next session should be able to start the next task with zero additional orientation — no doc re-reads, no codebase exploration.

## Required Sections

### 1. Session header

What completed, what's next. One line each.

```markdown
# Handoff

## What was completed this session

**Task N — Name**
```

### 2. Completed work

For each task done this session:

**Files table** — every file created or meaningfully modified, one line of "what it contains/exports":

| File | What it contains |
|---|---|
| `src/foo/bar.ts` | `barFn(x, y)` → `Promise<Z>`; `BarSchema` Zod schema |

**Key design decisions** — non-obvious invariants enforced, constraints satisfied.

**Test counts** — if tests were written, a per-file breakdown table and total. State `npx tsc --noEmit` result for TypeScript projects.

### 3. Phase state table

Every task in the current phase, not just recent ones. Use emoji status:

| Task | Status | Notes |
|---|---|---|
| Task 1 — Name | ✅ Done (prior session) | one-line note |
| Task 2 — Name | ✅ Done this session | one-line note |
| Task 3 — Name | 🔜 Next | Depends on Tasks 1 + 2 — now unblocked |
| Task 4 — Name | ⬜ Blocked on Task 3 | |

Emoji: ✅ done, 🔜 next, ⬜ not started/blocked.

### 4. Next task (most critical section)

The next session must be able to start the next task with only this section. Include:

- **Source** — doc, section, task number, complexity
- **Goal** — what it accomplishes and why (one paragraph)
- **Files to create/modify** — table with path and what each exports
- **Read before coding** — ordered list of specific files/sections to read first, with *why* each matters
- **Key constraints** — non-negotiable rules; violations that would require rework (not style preferences)
- **Suggested data shapes** — if applicable, TypeScript type sketches for the core interfaces
- **Tests to write** — specific test cases, not just "write tests"
- **Definition of done** — explicit checkable criteria (tsc clean, N tests pass, specific behaviors verified)
- **What this task does NOT include** — deliberately deferred work, so scope is clear

### 5. Open items

Decisions still needed before specific future tasks:

| # | Item | Status |
|---|---|---|
| 1 | Confirm XYZ default | Open — resolve before Task N |
| 2 | Decide on ABC | ✅ Resolved — outcome |

## Quick Reference

| Section | What it answers |
|---|---|
| Completed work | What changed; which invariants it satisfies |
| Phase state | Which tasks done vs. remaining, in one scannable table |
| Next task | Exactly what to do, with enough detail to start immediately |
| Open items | Outstanding decisions and which tasks they block |

## Common Mistakes

| Mistake | Fix |
|---|---|
| Vague file descriptions ("utility functions") | One-line: exports + what they do |
| Next task section too thin | Include: read-order, constraints, data shapes, specific test cases, definition of done |
| Missing open items | Always check the project's implementation plan for outstanding questions |
| Stale phase table | Update every task's emoji status before finishing |
| Including full code | Reference file paths; include only type sketches for interfaces not yet written |
| Missing "what is NOT in scope" | Explicitly list deferred work so the next session doesn't over-implement |

## What NOT to Include

- Raw implementation code (it's in the files — read those)
- Git history (use `git log`)
- Architectural docs (they're in `docs/` — link to them)
- Resolved items with no future relevance
- Directory trees (useful once as a snapshot; omit if the codebase structure is clear from the files table)

## When the Goal Is Fully Met

If the handoff you are writing reflects the **final close-out** — the phase state table is all ✅
and the overall goal is declared met — do not write another Next task section. Instead, after
writing the handoff, invoke the **`ingest-handoff` skill** to promote its durable content into the
project's long-term stores:

- Architectural decisions → `docs/adrs/` (via `/create-adr`).
- Operational facts → `docs/memory/` documents indexed at `docs/memory/INDEX.md`.

The handoff document itself is left in place as a session record; `ingest-handoff` handles
what gets promoted and what gets discarded.
