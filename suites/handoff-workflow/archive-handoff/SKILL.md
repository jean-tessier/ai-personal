---
name: archive-handoff
description: Move a completed handoff.md from the project root into docs/archive/handoffs/ with a date-stamped filename, add frontmatter, and update the consolidated index.
---

# Archive Handoff

## Purpose

After a completed handoff has been ingested (`/ingest-handoff`), move `handoff.md` from the project root into `docs/archive/handoffs/` so the root stays clean for future work. The archived file is the verbatim session record; `docs/archive/handoffs/INDEX.md` makes all past handoffs discoverable at a glance.

## When to invoke

After `/ingest-handoff` has completed — all durable content has been promoted to `docs/adrs/` and `docs/memory/`. Archive only terminal handoffs where the goal is declared met. Do **not** archive an in-progress handoff; the session loop needs it at the root.

---

## Steps

### 1. Read and validate handoff.md

Read `handoff.md` at the project root. Confirm:

- The phase state table shows every planned task ✅.
- The handoff explicitly declares the overall goal met.

If either check fails, stop and tell the user which tasks remain incomplete. Do not archive a handoff that is still in use.

Extract:
- **Description** — the one-line summary of what the handoff covered (from "Goal met" or "What was completed" section). Used as the INDEX.md description.
- **Completion date** — use today's date (`YYYY-MM-DD`).

### 2. Derive the archive filename

Format: `YYYY-MM-DD-<slug>.md`

- **Date**: today's date.
- **Slug**: 3–5 kebab-case words derived from the handoff's overall goal. Drop articles and short prepositions. Examples:
  - "MCM pipeline fully built and deployed" → `mcm-pipeline-complete`
  - "Auth service refactor with JWT" → `auth-service-jwt-refactor`

Present the proposed filename to the user and allow them to correct it before proceeding.

### 3. Ensure the archive directory exists

Check for `docs/archive/handoffs/`. If it does not exist, create it (`mkdir -p`). If `docs/` does not exist, stop — this project is not set up for docs and something is wrong.

### 4. Prepare frontmatter

`handoff.md` files typically have no frontmatter. Before writing the archive copy, prepend a compliant YAML frontmatter block following `docs/specs/yaml-frontmatter-spec.md`:

```yaml
---
date: YYYY-MM-DD
description: <≤120-char plain-text summary of what this handoff covered>
status: active
tags: [handoff, archive]
scope: archive.handoffs
---
```

- `date` — today.
- `description` — derived in Step 1; must be ≤ 120 plain-text characters.
- `status: active` — the record is accurate as a historical artifact.
- If frontmatter already exists on the source, validate it and update `date` to today rather than prepending a second block.

### 5. Write the archived file

Write the handoff content (with frontmatter prepended) to:

```
docs/archive/handoffs/<YYYY-MM-DD-slug>.md
```

Do not alter the body — the archive is a verbatim session record. Only frontmatter is added.

### 6. Update docs/archive/handoffs/INDEX.md

If `INDEX.md` does not exist at `docs/archive/handoffs/`, create it:

```markdown
# Handoff Archive

Completed session records in reverse-chronological order.

| File | Date | Description |
|---|---|---|
```

Append (or prepend if the table already has rows — newest first) a row for the newly archived handoff:

```markdown
| [YYYY-MM-DD-slug.md](YYYY-MM-DD-slug.md) | YYYY-MM-DD | <description> |
```

Keep rows in **reverse-chronological order** (most recent at the top).

`INDEX.md` does not require YAML frontmatter (consistent with `docs/adrs/INDEX.md` and `docs/memory/INDEX.md`).

### 7. Remove handoff.md from the project root

Delete `handoff.md` from the project root. This is a destructive step — state clearly that you are doing this before acting. The content is fully preserved in the archive file, so no information is lost.

### 8. Report

Summarize:
- The full archive path (`docs/archive/handoffs/<filename>`).
- That `docs/archive/handoffs/INDEX.md` was created or updated.
- That `handoff.md` was removed from the project root.
- What to do next if a new project phase begins (create a fresh `handoff.md` via `/handoff-document`).

---

## Edge cases

- **handoff.md not at project root**: Stop and tell the user. This skill operates only on `handoff.md` in the working directory root.
- **Archive file already exists for today's date**: Either the slug is not unique (adjust the slug) or the skill is being run twice. Confirm with the user before overwriting.
- **docs/specs/yaml-frontmatter-spec.md not found**: Write minimal valid frontmatter (`date`, `description`, `status: active`) and note the spec was unavailable.
- **Goal not declared met**: Do not archive. Tell the user which tasks are still incomplete and suggest running `/handoff-document` to update the handoff instead.
