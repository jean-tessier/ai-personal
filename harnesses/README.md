# harnesses/

Per-harness configuration. A harness is the scaffolding that wraps a model:
Claude.ai Projects, Cursor, Windsurf, a custom API client, etc.

## Customisation vs. extension

These are not separate directories — the distinction lives in file type:

| File type | Meaning |
|-----------|---------|
| `.md` | Customisation — changes existing harness behaviour (prose config, system prompts) |
| `.json` | Extension — adds capability (wires in tools, MCP servers, plugins) |

Document the intent of each file in the harness's README.

## Adding a new harness

1. Create `harnesses/{harness-name}/`
2. Add a `README.md` explaining the harness and what config files mean
3. Add config files following the file-type convention above
