# skills/

Procedural instruction sets. A skill teaches an agent *how to perform a procedure*.

A skill here is standalone and monorepo-internal — one canonical copy, referenced by
name from any `suites/{name}/` that uses it, never forked into the suite's own
directory.

## Structure per skill

```
{skill-name}/
├── SKILL.md       # The skill: procedure, constraints, examples
├── USAGE.md       # How to invoke it: trigger phrases, one worked example
├── CHANGELOG.md   # Date · model-version · what changed and why
└── references/    # (optional) supporting docs; some skills also add scripts/
```

## SKILL.md frontmatter

```yaml
---
name: {skill-name}
description: One sentence — when to use this skill and what it produces.
---
```

The `description` field is consumed by `scripts/catalog.sh` and surfaced
in the catalog. Keep it under 120 characters.

## Available skills

| Skill | Description |
|-------|-------------|
| [atomic-commits](atomic-commits/SKILL.md) | Generate clean, atomic git commits from working changes with meaningful messages that explain *why*, not just *what*. |
| [create-adr](create-adr/SKILL.md) | Create a new Architecture Decision Record (ADR) in docs/adrs/ |
| [create-changelog](create-changelog/SKILL.md) | Create or append a dated entry to a skill's CHANGELOG.md |
| [fix-validation](fix-validation/SKILL.md) | Run scripts/validate.sh, auto-fix mechanical structural issues, and report what needs manual authorship |
| [readme-maintenance](readme-maintenance/SKILL.md) | Audit and refresh every README in the repo against a quality rubric, one reviewer subagent per workspace |
| [yaml-frontmatter](yaml-frontmatter/SKILL.md) | Validate, add, or update YAML frontmatter on documentation files |
