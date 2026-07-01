# prompts/tasks/

One-shot task prompts. Each file is a standalone Markdown document.

## Naming

Kebab-case: `extract-entities.md`, `summarise-doc.md`, `rewrite-email.md`.
The stem is the task's canonical identifier — it must match the corresponding
`evals/tasks/{name}/` path.

## Frontmatter

```yaml
---
name: extract-entities
description: Extract named entities from unstructured text and return structured JSON.
output: "JSON array: [{ entity, type, confidence }]"
model_notes: "Works well with claude-sonnet-4-5+; requires extended thinking for complex docs."
---
```

## When to add examples/

If a task prompt benefits from few-shot examples, create a subdirectory:

```
tasks/
├── extract-entities.md
└── extract-entities/
    └── examples/
        ├── 001-input.md
        └── 001-output.md
```
