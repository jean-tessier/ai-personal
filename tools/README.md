# tools/

Tool and capability definitions wired into agents or harnesses.

## mcp/

MCP server definitions. Each subdirectory is a named server:

```
{server-name}/
├── manifest.json   # Server manifest
└── README.md
```

## functions/

Function/tool call schemas, split by provider.

| Directory | Contents |
|-----------|----------|
| `_common/` | Provider-agnostic base schemas (the canonical definition) |
| `anthropic/` | Anthropic-format binding shims referencing `_common/` |
| `openai/` | OpenAI-format binding shims referencing `_common/` |

**Authoring rule:** define the logical tool once in `_common/`, then write a
thin binding shim per provider. New providers get a shim, not a duplicate
definition.
