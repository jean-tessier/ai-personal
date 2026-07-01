---
date: 2026-07-01
decision_date: 2026-07-01
description: claude-code's own mapping omits agents and tools/mcp too — this repo's asset shapes for those categories don't match Claude Code's native formats either, not just Copilot's
status: accepted
---

# ADR-0004: `claude-code`'s Own Native Agent/MCP Formats Are Also Incompatible With This Repo's Shapes

## Status

Accepted

## Context

`claude-code` is this repo's own daily driver (see `skills/` installed live under `.claude/skills/`
in this working tree), so it would be easy to assume it can accept every asset category this repo
stores. It cannot. `scripts/harnesses.json`'s `claude-code.mapping` has only three keys — `skills`,
`tasks`, `workflows` — deliberately omitting `agents` and `mcp` (`tools/mcp` in the catalog). This
was verified against Claude Code's own live documentation (via Context7) and confirmed with smoke
tests during Task 2, not assumed.

The reason is a shape mismatch, not a policy choice: this repo stores an agent as
`prompts/agents/{name}/system.md` — a bare system-prompt markdown file, no frontmatter for tool
permissions, model, or description (see `scripts/catalog.sh`'s agents entry, which only records
`hasSystem`/`hasChangelog`/`hasExamples` booleans). Claude Code's native subagent format is a
single file with YAML frontmatter declaring `name`, `description`, `tools`, and (optionally)
`model`, at `.claude/agents/{name}.md`. Copying `system.md` verbatim to that path would produce a
file Claude Code can't parse as a subagent definition — it's missing the frontmatter contract
entirely. Similarly, this repo's `tools/mcp/{name}/manifest.json` is an arbitrary manifest shape
(only `hasManifest` is checked); Claude Code's native MCP registration is a project-root
`.mcp.json` with an `mcpServers` object of a specific shape, not one-manifest-per-directory. Neither
`prompts/agents/` nor `tools/mcp/` can be mechanically reshaped into their Claude-Code-native
counterparts by a plain file copy — the same conclusion independently reached for `copilot`'s own
agent/MCP formats (see `scripts/harnesses.json`'s `copilot.mapping`, which has only `skills`).

The notable finding here: this isn't "Copilot is a different vendor, of course it's incompatible."
It's that `claude-code`'s *own* mapping — for the harness that is this repo's native, daily-driver
format — has the identical gap for the identical reason.

## Decision

`claude-code.mapping` in `scripts/harnesses.json` omits `agents` and `mcp` (the `tools.mcp`
catalog key), exactly as `copilot.mapping` does. Neither harness's mapping will gain those keys
until this repo's `prompts/agents/` and `tools/mcp/` storage shapes are changed to match a target
harness's native format (or a transform step is introduced — out of scope for this effort; see
Open items).

## Consequences

### Positive

- `install.sh`'s `select_assets()` needs no special-casing: `agents`/`mcp` are simply absent from
  `claude-code.mapping`, so they're skipped with the same `_warn`-and-continue path described in
  ADR-0003, with no risk of writing a `.claude/agents/*.md` file Claude Code can't actually load.
- The gap was found and fixed at manifest-authoring time (Task 2, cross-checked against live docs)
  rather than discovered later as a bug report from a user whose Claude Code install silently
  ignored — or worse, errored on — a malformed subagent file.

### Negative

- Neither harness can install this repo's agent prompts or MCP manifests as native
  subagents/MCP servers today — those two categories are effectively `install.sh`-inert for every
  currently-declared harness, even the one that is this repo's own daily driver.
- Confirming this required an external documentation check (Context7 against Claude Code's own
  docs) rather than being obvious from reading this repo's asset shapes alone.

### Neutral

- If a future task wants `prompts/agents/` or `tools/mcp/` assets installable into Claude Code,
  that requires either changing this repo's storage shape to match Claude Code's native subagent
  frontmatter / `.mcp.json` schema, or adding a transform step to `install.sh` beyond a plain
  template-substituted copy — a materially bigger change than adding a mapping key, and not
  something this effort's `install.sh` (copy-only, no transformation) was scoped to do.

## References

- `scripts/harnesses.json` — `claude-code.mapping` and `copilot.mapping`, both missing `agents`/
  `mcp` keys.
- `scripts/catalog.sh` — the `agents`/`mcp` catalog entries showing this repo's actual on-disk
  shape (`prompts/agents/{name}/system.md`; `tools/mcp/{name}/manifest.json`).
- `handoff.md` (this branch's session record) — Task 2 phase-table note ("claude-code omits
  agents+mcp too (verified against live docs)") and Open item 5.
- ADR-0003 — the general compatibility-by-omission mechanism this decision relies on.
