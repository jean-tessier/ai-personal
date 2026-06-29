# tools/mcp/

MCP server definitions. One subdirectory per server.

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

Harness configs (e.g. `harnesses/claude-ai/projects/{name}/mcp-servers.json`)
reference servers by pointing to this manifest, not by duplicating it:

```json
[{ "name": "display-name", "ref": "tools/mcp/{server-name}/manifest.json" }]
```
