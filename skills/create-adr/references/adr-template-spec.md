---
date: 2026-07-10
description: Canonical ADR file structure, naming, numbering, frontmatter, and required sections for docs/adrs/.
status: active
---

# ADR Template Spec

## Purpose and scope

Defines the canonical structure for Architecture Decision Record files in `docs/adrs/`, so that
every ADR — however it's authored — is structurally consistent. This spec is read and followed by
the `create-adr` skill before it drafts a new ADR file.

## Naming convention

- Path: `docs/adrs/ADR-XXXX-<kebab-slug>.md`
- `XXXX` is a four-digit, zero-padded sequential number (e.g. `0001`, `0002`).
- The slug is derived from the ADR's title: lowercase words, hyphens as separators, articles
  (`a`, `an`, `the`) and short prepositions dropped unless essential to meaning.

## Numbering

- List files in `docs/adrs/` matching `ADR-[0-9][0-9][0-9][0-9]-*.md`.
- Take the highest existing number and add 1. If no ADR files exist yet, start at `0001`.
- Zero-pad the result to four digits.

## Frontmatter

Base fields — `date`, `description` (≤120 chars, plain text), `status` — are defined in
`docs/specs/yaml-frontmatter-spec.md`; every ADR carries them. ADRs additionally carry one
ADR-specific field:

- `decision_date` (`YYYY-MM-DD`) — the date the decision was actually made. This is distinct from
  `date`, which tracks when the file's frontmatter was last touched; the two commonly differ (e.g.
  a decision made on one date gets its file edited — renumbered, superseded — on a later date).

ADRs do **not** carry the base spec's conditional `superseded_by` frontmatter field. An ADR records
supersession in its `## Status` section instead — a parenthetical date and one-line reason (see
Required body sections). This ADR-specific rule overrides the base spec's `superseded_by`
requirement for files in `docs/adrs/`.

`status` takes one of:

- `proposed` — newly drafted, not yet ratified.
- `accepted` — ratified and in effect.
- `superseded` — later replaced by another decision (see Status section format below).

Example frontmatter block:

```yaml
---
date: 2026-07-01
decision_date: 2026-06-30
description: Use PostgreSQL as the primary datastore for new services instead of MongoDB
status: accepted
---
```

## Required body sections

In order, all required unless noted:

1. `## Status` — plain text matching the frontmatter `status` (e.g. `Proposed`, `Accepted`). When
   status is `superseded`, follow with a parenthetical date and a one-line reason, e.g.
   `Superseded (2026-07-08) — reason.`
2. `## Context` — the situation, forces, and constraints; neutral factual tone.
3. `## Decision` — opens with "We will …" in active voice; specific, not vague.
4. `## Consequences` — three sub-sections, each with at least one bullet:
   - `### Positive`
   - `### Negative`
   - `### Neutral`
5. `## References` — optional; omit the section entirely if there are no relevant links or docs.

## `docs/adrs/INDEX.md` format

Create the file with this header if it doesn't already exist:

```markdown
# ADR Index

| Number | Title | Status | Description | Date |
|---|---|---|---|---|
```

Append one row per ADR. The Number column links to the ADR file; the Date column uses
`decision_date`, not `date`:

```markdown
| [XXXX](ADR-XXXX-<slug>.md) | <Title> | <status> | <description> | <decision_date> |
```

## No placeholder text

Every section must contain real content derived from the ADR's actual title and context. Do not
leave placeholder text — `<!-- … -->` comments, `…` bullets, or literal `YYYY-MM-DD` strings — in
the written file.
