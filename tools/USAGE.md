# tools/ — Usage Guide

`tools/` holds MCP server manifests and function/tool-call schemas — the
capability definitions that get wired into a harness config (Claude Code,
or any other agent runtime that reads this repo). Nothing here runs on its
own; a harness config points at a manifest or schema file by reference, and
that's what makes the capability available inside an agent session.

For directory layout and naming conventions, see [`tools/README.md`](README.md).
This file is about how you'd actually reach for what's in here.

## How the pieces fit together

```
harness config (e.g. Claude Code settings)
        │
        │  "ref": "tools/mcp/{server-name}/manifest.json"
        ▼
tools/
├── mcp/                       MCP server definitions
│   ├── README.md              manifest.json schema + referencing convention
│   └── {server-name}/         ← not created yet; scaffold only
│       ├── manifest.json
│       └── README.md
│
└── functions/                 function/tool-call schemas (planned, not created yet)
    ├── _common/                the canonical, provider-agnostic definition
    ├── anthropic/               thin binding shim → _common/
    └── openai/                  thin binding shim → _common/
```

A harness never duplicates a server or schema definition inline — it
references the file in `tools/` by path, so the manifest stays the single
source of truth.

## Assets

| Asset | Status | One-line description |
|-------|--------|-----------------------|
| `mcp/` | Scaffold only — no servers defined | Reference schema + convention for defining MCP server manifests |
| `functions/` | Not yet created | Planned home for provider-specific function/tool-call schemas, bound to a shared `_common/` definition |

Both assets are currently placeholders: `tools/` has no working example to
point at yet. Below is what exists today and the structure you'd follow to
add the first real one.

### mcp/

**Status:** scaffold only. `tools/mcp/` contains just a `README.md` with the
manifest schema — no `{server-name}/` subdirectories exist yet.

**How to use it:** when you need to add an MCP server (hosted or local) to
the harness, create a new subdirectory under `tools/mcp/{server-name}/`
containing a `manifest.json` that follows the schema in
[`tools/mcp/README.md`](mcp/README.md), then point a harness config at it by
reference rather than inlining the definition.

Example — adding a local stdio server (illustrative; this server doesn't
exist in the repo yet):

`tools/mcp/local-llm/manifest.json`:
```json
{
  "name": "local-llm",
  "description": "Local LLM inference server.",
  "type": "stdio",
  "command": ["python", "server.py"],
  "capabilities": ["tools", "resources", "prompts"]
}
```

Referenced from a harness config:
```json
[{ "name": "local-llm", "ref": "tools/mcp/local-llm/manifest.json" }]
```

Use `"type": "url"` with a `"url"` field instead of `"command"` for hosted
servers. Only one of `url`/`command` is required per manifest.

### functions/

**Status:** not yet created. `tools/README.md` documents the intended
layout, but no `_common/`, `anthropic/`, or `openai/` directories exist on
disk yet.

**Intended structure**, per the authoring rule in `tools/README.md`: define
each logical tool once in `functions/_common/`, then add a thin per-provider
binding shim in `functions/anthropic/` or `functions/openai/` that
references it — never a duplicate definition. Add a new provider by adding
a shim directory, not by copying the schema.

No example exists yet because no schema has been written. Follow the
`_common/` + shim pattern above when adding the first one.
