---
name: yaml-frontmatter
description: Validate, add, or update YAML frontmatter on documentation files
---

# YAML Frontmatter

## Purpose

Manage YAML frontmatter on project documentation files. The authoritative field definitions, types, allowed values, and validation rules live in `docs/specs/yaml-frontmatter-spec.md`. Read that file before performing any validation or generation.

## When to invoke

When the user needs to check, add, or fix YAML frontmatter on a `docs/` file. Triggers on `/yaml-frontmatter`, or phrases like "validate the frontmatter", "add frontmatter to", "fix the frontmatter on", or "audit all docs frontmatter".

---

## Modes

### No arguments — validate the current file

If a file is already being discussed in the conversation, validate its frontmatter against the spec. If context is ambiguous, ask the user which file to check.

Steps:
1. Read `docs/specs/yaml-frontmatter-spec.md`.
2. Read the target file.
3. Check that a frontmatter block exists (opening `---` on line 1, closing `---` before body content).
4. Validate each required field is present and conforms to its type and allowed values.
5. If `status` is `superseded`, confirm `superseded_by` is also present.
6. Check optional fields (`tags`, `scope`) for format compliance if they appear.
7. Report each violation as a numbered finding with the field name, the problem, and the correction needed. If everything is valid, say so explicitly.

---

### `add <filepath>` — add missing frontmatter

Add a compliant frontmatter block to a file that has none. Infer field values from the document content — do not use placeholder text.

Steps:
1. Read `docs/specs/yaml-frontmatter-spec.md`.
2. Read the target file at `<filepath>`.
3. Confirm there is no existing frontmatter block. If one exists, stop and tell the user to use `update` instead.
4. Infer values:
   - `date` — use today's date in `YYYY-MM-DD` format.
   - `description` — write a one-line plain-text summary (≤ 120 chars) derived from the document's title and opening content.
   - `status` — default to `draft` unless the content clearly describes a finalised decision or active guide.
   - `tags` — derive from technologies, domains, and concepts mentioned in the document; use lowercase kebab-case.
   - `scope` — derive from the document's directory path and subject matter.
5. Present the proposed frontmatter block to the user for confirmation before writing.
6. Prepend the block to the file.

---

### `update <filepath>` — fix non-conforming frontmatter

Re-validate and repair any frontmatter fields in the target file without altering the document body.

Steps:
1. Read `docs/specs/yaml-frontmatter-spec.md`.
2. Read the target file at `<filepath>`.
3. If no frontmatter exists, tell the user to use `add` instead.
4. Parse the existing frontmatter and validate every field against the spec.
5. For each violation, compute the corrected value. Where inference is needed (e.g. a missing required field), derive it from document content rather than leaving it blank.
6. List all proposed changes and ask for confirmation before writing.
7. Write the corrected frontmatter block in place, leaving the document body unchanged.

---

### `check-all` — audit every doc file

Scan all Markdown files under `docs/` and report compliance status for each.

Steps:
1. Read `docs/specs/yaml-frontmatter-spec.md`.
2. Find every `.md` file under `docs/` recursively.
3. For each file, check:
   - Does a frontmatter block exist?
   - Are all required fields present and valid?
   - If `status` is `superseded`, is `superseded_by` present?
   - Do optional fields, if present, conform to their format rules?
4. Produce a summary table:

   | File | Frontmatter | Issues |
   |---|---|---|
   | `docs/adr/adr-001.md` | Present | None |
   | `docs/guides/setup.md` | Missing | No frontmatter block |
   | `docs/adr/adr-002.md` | Present | `status` has unknown value `wip` |

5. After the table, list files with issues as actionable items and suggest running `/yaml-frontmatter add <filepath>` or `/yaml-frontmatter update <filepath>` for each.
