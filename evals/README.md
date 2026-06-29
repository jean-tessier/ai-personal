# evals/

Evaluation suites for prompts and skills.
Tree structure mirrors `prompts/` and `skills/` exactly:

```
evals/
├── agents/{agent-name}/cases.yaml
├── skills/{skill-name}/cases.yaml
└── tasks/{task-name}/cases.yaml
```

Finding the eval for `skills/docx/` → `evals/skills/docx/cases.yaml`.
No slug translation required.

## cases.yaml format

```yaml
cases:
  - id: "001-happy-path"
    description: "Basic invocation with well-formed input."
    input:
      user: "Summarise this in three bullet points: ..."
    expected:
      contains: ["•", "key finding"]      # Strings that must appear
      not_contains: ["I cannot", "sorry"] # Strings that must not appear
      format: markdown                    # Optional: markdown | json | plain
    tags: [smoke]

  - id: "002-empty-input"
    description: "Edge case: empty input string."
    input:
      user: ""
    expected:
      behaviour: graceful_error           # For cases where output shape varies
    tags: [edge]

  - id: "003-json-output"
    description: "Validates structured JSON output."
    input:
      user: "Extract entities from: 'Apple Inc. is based in Cupertino.'"
    expected:
      format: json
      json_contains:
        - { entity: "Apple Inc.", type: "ORG" }
    tags: [smoke, regression]
```

## Tags

| Tag | Meaning |
|-----|---------|
| `smoke` | Fast, must-pass — run before every commit |
| `regression` | Guards against known past failures |
| `edge` | Boundary conditions and error paths |
| `slow` | Long-running; omit from pre-commit |
