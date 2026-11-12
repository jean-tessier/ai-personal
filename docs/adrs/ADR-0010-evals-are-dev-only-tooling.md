---
date: 2026-11-12
decision_date: 2026-11-12
description: Evals live in evals/<skill>/ as dev-only tooling, never installed and not an asset category; reports are committed
status: accepted
---

# ADR-0010: Evals Are Dev-Only Tooling in `evals/<skill>/`, Not an Asset Category

## Status

Accepted

## Context

`skills/plan-dag` needed measured evidence that its body and description earn their cost: behaviour
cases comparing a run with no skill (A), the skill as committed (B) and a shorter description (C),
plus trigger-precision cases. The harness runs through `claude plugin eval`, an early-access Claude
Code CLI feature, and makes real model calls on the operator's credentials.

Where the eval files live matters because of how skills ship. `install.sh` copies a skill's
directory with `cp -R`, and the marketplace `source` for a skill is the skill directory itself
(`./skills/plan-dag`). Anything under `skills/<skill>/` therefore reaches every installer — and
would hand the graders, canary strings and expected answers to the very model being evaluated.

`CLAUDE.md` also says "eval cases" would be added as a new asset category if they ever got real
content, which would mean touching `install.sh`'s `ALL_CATEGORIES`, `scripts/catalog.sh`,
`scripts/validate.sh` and `scripts/harnesses.json` together. Evals are not something an end user
installs, so that path does not fit.

## Decision

We will keep evals as dev-only tooling in `evals/<skill>/` at the repo root, run through
`claude plugin eval`, and never install them. They are **not** an asset category: they must not be
added to `install.sh`'s `ALL_CATEGORIES`, `scripts/catalog.sh`, `scripts/validate.sh` or
`scripts/harnesses.json`. This is an explicit exception to the "eval cases" future-category note in
`CLAUDE.md`.

- Raw results stay local: `evals/*/work/` is gitignored.
- Dated markdown reports are committed under `evals/<skill>/reports/`, named
  `<date>-<skill-tree-hash7>` (`<skill-tree-hash7>` is `git rev-parse --short HEAD:skills/<skill>`).
  A new report supersedes the previous one for that skill.
- Reports record the exact CLI version, because the feature is early access.

Alternatives considered:

- **`skills/plan-dag/evals/`** — colocated with the skill, but it ships to installers and leaks the
  graders to the subject under test.
- **`scripts/evals/` plus `docs/evals/`** — `tsc` type-checks fixtures under `scripts/`, and a
  fourth store under `docs/` breaks the "three indexed stores" contract.

## Consequences

### Positive

- Graders and fixtures never reach installers or the model being evaluated.
- No change to the installer, catalog, validator or harness manifest; the asset taxonomy stays at two kinds.
- Committed reports give a reviewable, deterministic record of each eval run, tied to the skill's tree hash.

### Negative

- Depends on an early-access CLI feature; results are only comparable within one pinned CLI version
  and every report must record it.
- Each run costs real money, so full runs need the owner's approval (see `evals/README.md`).
- Results are macOS-specific in part: `git` fails inside the subject's Bash on macOS (xcrun shim),
  so some facts are planted in files as well as history.

### Neutral

- `make check` and `validate.sh` do not look at `evals/`; only `node --test evals/plan-dag/report.test.mjs` covers its script.
- Adding evals for another skill means copying `evals/plan-dag/` to `evals/<skill>/`.

## References

- [evals/README.md](../../evals/README.md)
- [ADR-0003](ADR-0003-data-driven-harness-manifest.md)
