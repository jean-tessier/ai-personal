# harnesses/claude-ai/projects/

One subdirectory per Claude.ai Project.

```
{project-name}/
├── system.md          # Project system prompt
├── mcp-servers.json   # Connected MCP servers (refs into tools/mcp/)
└── README.md
```

The `project-name` directory name should match how the project is named in
Claude.ai for easy correlation. Use kebab-case.
