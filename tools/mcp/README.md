# tools/mcp/

MCP server definitions. One subdirectory per server. No servers defined yet.

## manifest.json schema

```json
{
  "name": "server-name",
  "description": "What this server exposes.",
  "type": "url | stdio",
  "url": "https://...",
  "command": ["npx", "..."],
  "capabilities": ["tools", "resources", "prompts"]
}
```

Use `type: url` for hosted servers, `type: stdio` for local processes.
Only one of `url` or `command` is required.

## Referencing servers from harnesses

Harness configs reference servers by pointing to this manifest, not by
duplicating it:

```json
[{ "name": "display-name", "ref": "tools/mcp/{server-name}/manifest.json" }]
```
