---
name: capture-deferred
description: Record known deferred items — future work, open decisions, and out-of-scope items — into docs/memory/deferred-items.md so they persist across sessions and are discoverable in future work.
---

# Capture Deferred Items

## Purpose

When work is completed or a session ends, some items are deliberately set aside: future enhancements,
unresolved decisions, technical debt acknowledged but not addressed, and scope explicitly excluded
from the current effort. Without a dedicated record, these items scatter across handoffs, comments,
and memory — and get lost.

This skill collects those items from any source (handoff, conversation, design doc) and appends them
to `docs/memory/deferred-items.md`, creating a persistent, scannable backlog for future sessions.

## When to invoke

- During `/ingest-handoff` when the handoff contains unresolved open items or "NOT in scope" entries.
- At the end of any session where known future work was explicitly acknowledged but not acted on.
- When the user says "make a note to come back to X", "defer this for later", or "add this to the backlog".

---

## Step 1 — Identify deferred items

Scan the source material for items that are known but explicitly not done:

| Source location | What to look for |
|---|---|
| Open items table | Any row whose Status is not ✅ Resolved |
| "What this task does NOT include" section | Deliberate deferrals, not just permanent exclusions |
| Inline notes | TODOs, "future enhancement", "consider later", "next phase" markers |
| Conversation | Anything the user explicitly flagged as "defer this" |

For each item, note:

- **Description** — one line (≤ 80 characters), specific enough to act on without additional context.
- **Type** — one of: `future-work`, `open-decision`, `tech-debt`, `enhancement`.
- **Priority** — `high` (blocks future work), `normal` (should revisit), `low` (nice-to-have).
- **Source** — where you found it (e.g., `handoff.md § Open items`, `handoff.md § Task 3 NOT in scope`).

If no deferred items are found, report that and stop — do not create an empty file.

---

## Step 2 — Write or update docs/memory/deferred-items.md

### 2a. Verify docs/memory/ exists

If `docs/memory/` does not exist, do not create it here — stop and tell the user. The memory
directory is established by `/ingest-handoff`; this skill writes into an existing store.

### 2b. Create or update

If `docs/memory/deferred-items.md` does not exist, create it with YAML frontmatter per
`docs/specs/yaml-frontmatter-spec.md`:

```markdown
---
date: YYYY-MM-DD
description: Known deferred items, open decisions, and future work to revisit in later sessions
status: active
tags: [backlog, deferred]
scope: memory.deferred
---

# Deferred Items

Items explicitly set aside during prior sessions. Resolved items are struck through and dated in the Status column.

| # | Item | Type | Priority | Source | Added | Status |
|---|---|---|---|---|---|---|
```

If the file already exists, append new rows to the existing table and update `date` in the
frontmatter to today. Do not alter existing rows.

### 2c. Assign row numbers

Number new rows sequentially, continuing from the highest existing number. Never renumber
existing rows — stable numbers let other documents reference items by number.

### 2d. Write rows

One row per deferred item:

```markdown
| 1 | Migrate upload handler to streaming to support large files | tech-debt | normal | handoff.md § Open items | 2026-06-29 | |
```

Keep descriptions ≤ 80 characters and imperative ("Add X", "Migrate Y", "Decide on Z"). If context
beyond 80 characters is genuinely necessary, add a fenced note block below the table rather than
bloating the cell.

---

## Step 3 — Update docs/memory/INDEX.md

Add or update the `deferred-items.md` row:

```markdown
| [deferred-items.md](deferred-items.md) | Known deferred items, open decisions, and future work to revisit | YYYY-MM-DD |
```

Keep rows in alphabetical order by filename. Update the date only when the file is modified.

---

## Step 4 — Report

Tell the user:

- How many items were captured (N new rows added to `docs/memory/deferred-items.md`).
- A one-line breakdown by type (`future-work: 2, open-decision: 1`).
- Any items that were skipped and why (already in the file, too vague to capture).

---

## Resolving deferred items

When a deferred item is completed in a future session, do **not** delete its row. Instead:

- Strike through the description: `~~Migrate upload handler to streaming~~`.
- Set the Status column to `✅ Done YYYY-MM-DD`.
- Update `date` in the frontmatter to today.

Example resolved row:

```markdown
| 3 | ~~Migrate upload handler to streaming to support large files~~ | tech-debt | normal | handoff.md § Open items | 2026-06-15 | ✅ Done 2026-07-02 |
```

This preserves history — what was deferred, when it was captured, and when it was addressed.
