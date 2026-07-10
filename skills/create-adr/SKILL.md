---
name: create-adr
description: Create a new Architecture Decision Record (ADR) in docs/adrs/
---

# Create ADR

## Purpose

Create a new Architecture Decision Record (ADR) for this project. ADRs document significant architectural decisions with their context, rationale, and consequences.

## When to invoke

When the user wants to record an architectural or technical decision. Triggers on `/create-adr`, or when the user says "create an ADR for …", "document this decision as an ADR", or "add an architecture decision record".

Usage:

```
/create-adr <title> [context-and-rationale]
```

**Arguments:**

- `<title>` — A short descriptive title for the decision (3–6 words works well).
- `[context-and-rationale]` — Optional free-form text describing the situation, the decision made, and why. If omitted or too sparse to write meaningful sections, ask the user one focused question before drafting.

---

## Steps

### 1. Read the specs

Read both specification files before doing anything else:

- `docs/specs/adr-template-spec.md` — ADR body structure, naming convention, frontmatter rules, and required sections.
- `docs/specs/yaml-frontmatter-spec.md` — Base frontmatter field definitions, types, and validation rules.

These are the consuming project's own files, kept under its `docs/specs/` so each project can
configure its own ADR rules. If either is missing, copy the bundled templates: this skill's own
`references/adr-template-spec.md`, and the `yaml-frontmatter` skill's base template, into
`docs/specs/`.

### 2. Determine the next ADR number

- List all files in `docs/adrs/` matching the pattern `ADR-[0-9][0-9][0-9][0-9]-*.md`.
- Extract the four-digit number from each filename.
- Take the highest number found and add 1. If no ADR files exist yet, start at `0001`.
- Zero-pad to four digits.

### 3. Check for sufficient context

Review the title and the optional context-and-rationale argument. If the provided information is too sparse to write a meaningful **Context** and **Decision** section — for example, the title alone with no rationale — ask the user one focused question before proceeding:

> "What specific problem, constraint, or change is driving this decision?"

Wait for the answer. Do not ask multiple questions at once.

### 4. Draft the ADR file

- Derive the kebab-case slug from the title: lowercase words, hyphens as separators, no articles (a, an, the) or short prepositions unless essential to meaning.
- Create the file at `docs/adrs/ADR-XXXX-<kebab-slug>.md`.
- Populate every required section using content from the title and context provided:
  - **Status** — write `Proposed` (plain text).
  - **Context** — the situation, forces, and constraints; neutral factual tone.
  - **Decision** — open with "We will …" in active voice; be specific.
  - **Consequences** — three sub-sections (Positive, Negative, Neutral); at least one bullet each.
  - **References** — include if relevant links or docs were mentioned; omit the section entirely if none.
- Set the frontmatter block: populate every base field the project's `docs/specs/yaml-frontmatter-spec.md` requires (read in step 1) — filling `description` from the ADR's summary and any date field with today's date — plus the ADR-specific `decision_date` (today, `YYYY-MM-DD`) and `status: proposed`.
- Do not leave placeholder text (`<!-- … -->` comments, `…` bullets, or `YYYY-MM-DD` literals) in the written file. Every section must contain real content derived from the input.

### 5. Update `docs/adrs/INDEX.md`

- If `INDEX.md` does not exist, create it with this header before appending:
  ```markdown
  # ADR Index

  | Number | Title | Status | Description | Date |
  |---|---|---|---|---|
  ```
- Append a new row for the new ADR. The Number column must be a Markdown link to the ADR file:
  ```markdown
  | [XXXX](ADR-XXXX-<slug>.md) | <Title> | proposed | <description from frontmatter> | <decision_date> |
  ```

### 6. Confirm and remind

- Report the exact absolute file paths written: the ADR file and `docs/adrs/INDEX.md`.
- Remind the user: once the decision is formally adopted, update `status` from `proposed` to `accepted` in the ADR frontmatter, update `decision_date` if the actual decision date differs from today, update the Status column in `INDEX.md`, and update the **Status** section in the ADR body to read `Accepted`.
