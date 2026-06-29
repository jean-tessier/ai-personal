# prompts/

Contextual instructions that establish who an agent is and what it is doing.
Contrast with `skills/`, which are procedural (how to do something).

## Subdirectories

### `agents/{name}/`
Standing context for a named agent. Minimum contents:

```
{agent-name}/
├── system.md       # The system prompt
├── CHANGELOG.md    # Date · model-version · what changed and why
└── examples/       # Representative input/output pairs
```

### `tasks/{name}.md`
One-shot task prompts. No dedicated directory unless examples are needed.
Add YAML frontmatter:

```yaml
---
name: extract-entities
description: Extract named entities from unstructured text.
output: "JSON array: [{ entity, type, confidence }]"
---
```

### `_shared/`
Composable fragments included by reference. Not standalone assets.

| Subdirectory | Contents |
|---|---|
| `personas/` | Role and voice definitions |
| `output-formats/` | Format contracts (JSON schemas, markdown templates, etc.) |
| `reasoning-modes/` | Chain-of-thought scaffolds, self-critique loops, etc. |
