# skills/

Procedural instruction sets. A skill teaches an agent *how to perform a procedure*,
as distinct from a prompt, which establishes *who the agent is*.

## Skills vs. prompts

| Dimension | Skill | Agent prompt |
|-----------|-------|--------------|
| Nature | Procedural (steps, constraints, output spec) | Contextual (identity, tone, domain knowledge) |
| Reuse | High — shared across many agents | Low — usually specific to one agent |
| Change trigger | Procedure or tooling changes | Agent purpose or model behaviour changes |
| Consumer | Agent invokes it for a specific task | Agent carries it as standing context |

## Structure per skill

```
{skill-name}/
├── SKILL.md       # The skill: procedure, constraints, examples
├── CHANGELOG.md   # Date · model-version · what changed and why
└── examples/      # Invocation examples or input/output pairs
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
| [create-changelog](create-changelog/SKILL.md) | Create or append a dated entry to a skill's or agent prompt's CHANGELOG.md |
