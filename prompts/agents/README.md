# prompts/agents/

Each subdirectory is a named agent configuration.

## Naming

Kebab-case. The directory name is the agent's canonical identifier across
the entire repo — it must match the corresponding `evals/agents/{name}/` path.

## Minimum structure

```
{agent-name}/
├── system.md       # The system prompt
├── CHANGELOG.md    # Version log
└── examples/       # Input/output pairs
    ├── 001-input.md
    └── 001-output.md
```

## CHANGELOG.md format

```
# Changelog

## 2026-01-15 · claude-sonnet-4-5 · Initial version
- Created.

## 2026-03-02 · claude-sonnet-4-6 · Tightened output contract
- Replaced prose format instruction with explicit JSON schema reference.
- Removed redundant "be concise" instruction (now in _shared/personas/concise.md).
```
