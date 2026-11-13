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
description: What the skill does, the phrases that should trigger it, and what it is not for.
---
```

The `description` is the trigger text Claude reads to decide when to load the skill. Aim for
about 500 characters and never exceed 1024 (the Agent Skills limit), because longer text is cut off in the skill listing.
Lead with what the skill does and the phrases that should trigger it, and say what it is not for.
Keep it on one line: `scripts/catalog.sh` reads only the first line of the field into the
catalog.

The 120-character limit applies only to the short text used in the skills table below and in
`.claude-plugin/marketplace.json`, not to the frontmatter `description`.

## Available skills

| Skill | Description |
|-------|-------------|
| [atomic-commits](atomic-commits/SKILL.md) | Generate clean, atomic git commits from working changes with meaningful messages that explain *why*, not just *what*. |
| [create-adr](create-adr/SKILL.md) | Create a new Architecture Decision Record (ADR) in docs/adrs/ |
| [create-changelog](create-changelog/SKILL.md) | Create or append a dated entry to a skill's CHANGELOG.md |
| [fix-validation](fix-validation/SKILL.md) | Run scripts/validate.sh, auto-fix mechanical structural issues, and report what needs manual authorship |
| [plan-dag](plan-dag/SKILL.md) | Plan multi-part work as a DAG of small slices with cost-appropriate models, then dispatch builders wave by wave |
| [readme-maintenance](readme-maintenance/SKILL.md) | Audit and refresh every README in the repo against a quality rubric, one reviewer subagent per workspace |
| [yaml-frontmatter](yaml-frontmatter/SKILL.md) | Validate, add, or update YAML frontmatter on documentation files |
