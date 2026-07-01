---
name: ingest-handoff
description: After a handoff's overall goal is fully met, extract its durable content into ADRs (architectural decisions) and docs/memory/ (operational facts) for long-term persistence and progressive discovery.
---

# Ingest Handoff

## Purpose

When `handoff.md` records that all planned work is complete and the overall goal is met, its
durable content must be promoted to the project's long-term stores before the handoff is retired:

- **Architectural decisions** → `docs/adrs/` via the `/create-adr` skill.
- **Operational facts** (resource IDs, URLs, deploy commands, token notes, unresolved open items)
  → `docs/memory/` documents, indexed at `docs/memory/INDEX.md`.

This skill defines what to extract, where it goes, and how to keep the indexes current.

## When to invoke

Invoke this skill exactly once, after the final handoff session confirms all of:

- The phase state table in `handoff.md` shows every planned task ✅.
- The handoff explicitly declares the overall goal met.
- No fabricated "next task" has been added to keep the loop alive.

Do not invoke on intermediate handoffs — only on the terminal one.

---

## Step 1 — Read and classify

Read `handoff.md` in full. Assign every substantive piece of content to one of three buckets:

| Bucket | Content type | Destination |
|---|---|---|
| **Decision** | Why the codebase is shaped a certain way; non-obvious architectural or design choice | `docs/adrs/` |
| **Operational fact** | Resource IDs, URLs, deploy commands, credential notes, config values | `docs/memory/` |
| **Ephemeral** | In-progress notes, next-task detail, intermediate status, test run counts | Discard — do not promote |

Decisions answer "why". Operational facts answer "where" and "how to operate". If a future
developer would need to re-discover the information without it, it belongs in one of the two
stores. If it would be stale or irrelevant a week from now, it is ephemeral.

---

## Step 2 — Write ADRs for decisions

For each decision identified in Step 1:

1. Check `docs/adrs/INDEX.md`. If an existing ADR already covers this decision, skip or update
   its status (do not create a duplicate).
2. For new decisions, invoke the `/create-adr` skill with the decision title and rationale.
3. If a decision was captured as a `proposed` ADR and the completed work has confirmed it, promote
   it: update `status` from `proposed` to `accepted` in the frontmatter and body section, and
   update the Status column in `docs/adrs/INDEX.md`.

Decisions worth capturing as ADRs include:

- Choice of auth mechanism (e.g., bearer token vs. API Gateway key auth).
- Non-obvious constraints baked into infrastructure (e.g., CDK construct ID immutability).
- Intentional scope limitations (e.g., single-store focus, single-tenant only).
- Token type choices and their lifetime implications.
- Any "we chose X over Y because Z" that is not derivable from reading the code.

---

## Step 3 — Write docs/memory/ documents for operational facts

### 3a. Ensure docs/memory/ exists

If `docs/memory/` does not exist, create it. Create `docs/memory/INDEX.md` with this header:

```markdown
# Memory Index

| Document | Description | Updated |
|---|---|---|
```

### 3b. Write or update individual documents

Group related operational facts into named Markdown documents. Each document:

- Covers one cohesive topic (one concern, one operational domain).
- Opens with YAML frontmatter per `docs/specs/yaml-frontmatter-spec.md` — required fields:
  `date` (today), `description` (≤ 120 chars, plain text), `status: active`; optional: `tags`,
  `scope`.
- Uses tables, bullet lists, or fenced code blocks — no narrative prose.
- Is self-contained: a reader should not need to open another document to act on it.

Typical documents to create or update from a completed handoff:

| Filename | What it holds |
|---|---|
| `deployed-resources.md` | Stack ARN, Lambda ARNs, S3 bucket names, Step Function ARNs, API URL |
| `api-endpoints.md` | Webhook URLs, path parameters, example `curl` commands |
| `deploy-operations.md` | The exact deploy command and any prerequisite env setup |
| `credential-management.md` | Token types, lifetimes, how to refresh, which `.env` vars are required |

If a document already exists, update it in place. Update `date` in its frontmatter to today.

### 3c. Update docs/memory/INDEX.md

After writing each document, add or update its row:

```markdown
| [deployed-resources.md](deployed-resources.md) | ARNs, bucket names, and API URL for the deployed stack | 2026-06-28 |
```

Keep rows in alphabetical order by filename. Update the date when a document is updated, not when
it is unchanged.

### 3d. Capture deferred items

Scan `handoff.md` for items that were explicitly set aside rather than completed:

- Rows in the Open items table whose Status is not ✅ Resolved.
- Entries in any "What this task does NOT include" section that represent future work (not permanent
  exclusions).
- Inline notes flagging future enhancements, technical debt, or deferred decisions.

If any such items are found, invoke the **`/capture-deferred` skill** to record them in
`docs/memory/deferred-items.md`. That skill handles creating the file, assigning row numbers, and
updating the memory index — do not write `docs/memory/deferred-items.md` directly.

If no deferred items are found, skip this sub-step.

---

## Step 4 — Confirm and close out

After writing all ADRs and memory documents, report to the user:

- Which ADRs were created or promoted to `accepted` (with file paths).
- Which `docs/memory/` documents were created or updated (with file paths).
- A one-line summary of what was classified as ephemeral and not promoted.

Then:

- **Invoke the `/archive-handoff` skill** to move `handoff.md` into `docs/archive/handoffs/`,
  prepend frontmatter, update the archive index, and remove the file from the project root. Do not
  delete or move `handoff.md` manually — that skill owns the archive step.
- **Remind the user:** if `docs/memory/INDEX.md` is not already referenced in `CLAUDE.md`, add a
  line pointing agents to it so they consult it at the start of future sessions.

---

## What NOT to ingest

| Content | Why not |
|---|---|
| Code snippets or implementation details | Live in the source files; read those |
| Git history, commit SHAs, branch names | `git log` / `git blame` are authoritative |
| Task-by-task implementation notes | Belong in commit messages, not memory |
| Resolved open items with no future relevance | Ephemeral — discard |
| File trees or directory snapshots | Read the current filesystem |
| Test counts, CI run results, tsc output | Ephemeral state |
| Content already documented in CLAUDE.md | Already loaded at session start; do not duplicate |
