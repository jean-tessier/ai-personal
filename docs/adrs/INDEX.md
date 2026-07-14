# ADR Index

| Number | Title | Status | Description | Date |
|---|---|---|---|---|
| [0001](ADR-0001-target-copilot-vscode-for-agent-suite.md) | Target GitHub Copilot/VS Code for the Capability-Scoped Agent Suite | superseded | Build the Capability-Scoped Agent Suite for GitHub Copilot/VS Code, not Claude Code | 2026-06-30 |
| [0002](ADR-0002-hook-filtering-in-scripts-not-matcher.md) | Hook Enforcement Lives in Invoked Scripts, Not the JSON `matcher` Field | superseded | Filter hook commands in the invoked script, since VS Code ignores the hook JSON matcher field | 2026-06-30 |
| [0003](ADR-0003-data-driven-harness-manifest.md) | Data-Driven Harness Manifest, With Compatibility-by-Omission | accepted | Declare harnesses in scripts/harnesses.json, not as branches in install.sh; a missing mapping key means "incompatible", not an error | 2026-07-01 |
| [0004](ADR-0004-claude-code-native-formats-incompatible.md) | `claude-code`'s Own Native Agent/MCP Formats Are Also Incompatible With This Repo's Shapes | superseded | claude-code's own mapping omits agents and tools/mcp too — this repo's asset shapes for those categories don't match Claude Code's native formats either, not just Copilot's | 2026-07-01 |
| [0005](ADR-0005-packs-flatten-into-skills.md) | Packs Flatten Into the `skills` Destination Category | superseded | A pack's skills install as plain skills (reusing the skills mapping); packs get no separate top-level mapping key | 2026-07-01 |
| [0006](ADR-0006-harness-variant-subdirectories-in-suites.md) | Harness-Variant Subdirectories Within a Suite | superseded | Multi-harness suites get per-harness subdirs named by harnesses.json keys; shared canonical docs stay at the suite root | 2026-07-09 |
| [0007](ADR-0007-suites-as-native-plugins.md) | Suites and Skills as Native Claude Code/Copilot Plugins | accepted | Plugin-shaped suites/skills get .claude-plugin manifests; install.sh translates them for Copilot and resolves deps | 2026-07-13 |
