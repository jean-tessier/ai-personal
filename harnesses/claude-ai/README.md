# harnesses/claude-ai/

Configuration for Claude.ai (web product, including Projects).

## projects/{name}/

Each subdirectory is a named Claude.ai Project:

```
projects/{project-name}/
├── system.md          # Project system prompt (customisation)
├── mcp-servers.json   # MCP servers connected to this project (extension)
└── README.md          # Purpose, wiring notes, any quirks
```

### mcp-servers.json format

```json
[
  {
    "name": "Display Name",
    "ref": "tools/mcp/{server-name}/manifest.json"
  }
]
```

`ref` points to the canonical manifest — don't duplicate server definitions here.

## extensions/

Claude.ai extension config not scoped to a specific Project.
(e.g., account-level MCP server registrations, if Claude.ai exposes that.)
