---
date: 2026-07-10
description: Base YAML frontmatter spec for Markdown docs under docs/ — fields, status enum, and validation rules
status: active
---

# YAML Frontmatter Spec

## Purpose

This is the base frontmatter spec for every Markdown document under `docs/`. It defines the
fields every doc's frontmatter block must or may carry, the allowed `status` values, and the
validation rules a tool checks a file against.

Other specs can layer on top of this one for a specific doc type instead of duplicating it — e.g.
a project might add an ADR-only spec (body structure, naming, a `decision_date` field) on top of
the fields defined here. If a doc type needs fields beyond this base set, add a spec for that type
rather than growing this file with type-specific cases.

## Applicability

Applies to every `.md` file under `docs/`, with one exception: `INDEX.md` files are index/listing
pages, not content documents, and carry no frontmatter block by convention.

## Required fields

Every non-`INDEX.md` file under `docs/` must have all three:

| Field | Type | Rule |
|---|---|---|
| `date` | string | `YYYY-MM-DD`. The date the file was last written or updated. |
| `description` | string | Single-line plain text, ≤120 characters. A summary of the doc's content. |
| `status` | string | One of the allowed values below. |

## `status` allowed values

| Value | Meaning | Used by |
|---|---|---|
| `draft` | Not yet finalized; still subject to change | New docs before they're finalized |
| `active` | Current and accurate as written | Current operational docs and guides |
| `proposed` | Awaiting a decision | Decision records (e.g. ADRs) awaiting adoption |
| `accepted` | The decision has been adopted | Decision records whose outcome has been adopted |
| `superseded` | Replaced by a later decision or document | Docs replaced by a later decision or doc |

This is a closed set — a `status` value outside this list is a validation failure.

## Conditional field: `superseded_by`

If `status` is `superseded`, `superseded_by` is required and must name the doc or decision that
replaced this one (e.g. a decision-record id like `ADR-0004`, or a file path). If `status` is
anything else, `superseded_by` must not be present.

A project that adopts this rule after already having files marked `status: superseded` may find
older files that predate the rule and lack `superseded_by`. That's an existing gap for `check-all`
to flag and for `add`/`update` to close, not a reason to drop the rule — see Validation rules below.

## Optional fields

| Field | Type | Format | Example |
|---|---|---|---|
| `tags` | list of strings | Lowercase kebab-case per item (`^[a-z0-9]+(-[a-z0-9]+)*$`) | `tags: [architecture, security, deprecated]` |
| `scope` | string | Lowercase, dot-delimited (`^[a-z0-9]+(\.[a-z0-9]+)*$`) | `scope: api.auth` |

Omit them where they don't apply — both are optional everywhere.

## Validation rules

A file is compliant when all of the following hold:

1. **Frontmatter block delimiters** — the file opens with `---` on line 1 and has a closing `---`
   line before any body content. (Skip this check entirely for `INDEX.md` files — see Applicability.)
2. **Required fields present and well-typed**:
   - `date` matches `YYYY-MM-DD` and is a valid calendar date.
   - `description` is a single-line plain-text scalar, ≤120 characters.
   - `status` is present and its value is one of the closed set in `status` allowed values.
3. **Conditional field**: if `status: superseded`, `superseded_by` is present and non-empty. If
   `status` is not `superseded`, `superseded_by` must be absent.
4. **Optional field format**, only checked when the key is present:
   - `tags` is a YAML list; each item matches `^[a-z0-9]+(-[a-z0-9]+)*$`.
   - `scope` is a single string matching `^[a-z0-9]+(\.[a-z0-9]+)*$`.

Any rule violated is reported as a distinct finding (field name, problem, correction needed) —
one file can carry multiple findings.

## Relationship to ADR frontmatter

If a project keeps architectural decision records under `docs/adrs/`, they use the fields and
`status` enum defined here, plus one ADR-only field, `decision_date` (`YYYY-MM-DD`, the date the
decision was actually made — may differ from `date`). In practice ADRs draw only from
`proposed → accepted` or `→ superseded` in the enum above; they don't use `draft` or `active`.
That lifecycle, the `decision_date` field, and ADR body structure belong in a separate,
ADR-specific spec, not duplicated here.
