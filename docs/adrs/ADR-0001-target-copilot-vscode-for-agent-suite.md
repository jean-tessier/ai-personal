---
date: 2026-07-01
decision_date: 2026-06-30
description: Build the Capability-Scoped Agent Suite for GitHub Copilot/VS Code, not Claude Code
status: superseded
superseded_by: b305d3d
---

# ADR-0001: Target GitHub Copilot/VS Code for the Capability-Scoped Agent Suite

## Status

Superseded (2026-07-08) — the top-level `.github/`, `.vscode/`, and root-level suite scripts this
ADR describes were deleted from the repo as part of curating it for public release. The design
lives on solely as `suites/tiered-escalation-suite/`, a more complete, generalized,
distributable payload meant to be copied into a *target* project rather than dogfooded in place
here — see that suite's `README.md`. This ADR is kept for historical context on why the
now-removed top-level copy existed and why it was never exercised live.

## Context

This repo's actual day-to-day driver is Claude Code (see `.claude/skills/`), not VS Code with
GitHub Copilot Chat. A design document, `.tmp/capability-scoped-agent-suite.html` ("Capability-Scoped
Agent Suite"), was dogfooded onto this repo across six build stages (Floor, Gates, Brains, Executors,
Isolation, Measure). Every artifact the design specifies is GitHub Copilot/VS Code-specific:
`.github/copilot-instructions.md`, `.github/agents/*.agent.md`, `.github/skills/*/SKILL.md`,
`.github/hooks/*.json`, and `.vscode/settings.json`/`tasks.json`/`mcp.json`. None of these surfaces
are read by Claude Code.

Before starting Stage 2 (the first stage after this mismatch became apparent), the fork was surfaced
explicitly: continue building Copilot/VS Code artifacts as literally specified, retarget the whole
effort to Claude-Code-native mechanisms (e.g. `.claude/settings.json` hooks), build both in parallel,
or stop the effort at Stage 1.

## Decision

We will continue building the suite exactly as the design doc specifies, targeting GitHub
Copilot/VS Code, through all six stages. We will not retarget any part of it to Claude Code's native
hooks/settings mechanism, and we will not build a parallel Claude-Code-native mirror.

## Consequences

### Positive

- The design is dogfooded faithfully and completely, producing a reference implementation that
  matches the source doc's literal templates and file layout without translation drift.
- If this repo (or another project) is ever opened in VS Code with Copilot Chat agent mode and the
  hooks preview flag enabled, the suite is already fully built and ready to exercise live.

### Negative

- Every artifact built across all six stages is dormant in this repo's actual daily workflow —
  Claude Code never reads `.github/agents/`, `.github/skills/`, `.github/hooks/`, or
  `.vscode/settings.json`.
- None of it has ever been exercised in a live VS Code + GitHub Copilot Chat agent-mode session;
  all verification across all six stages was static (JSON/YAML validation, self-tests against
  synthetic fixtures, `make check`).

### Neutral

- If this repo's daily driver ever changes to VS Code + Copilot, or a future project wants a
  Claude-Code-native equivalent of this design, that is new, separate work — not a retrofit of
  these files.

## References

- `.tmp/capability-scoped-agent-suite.html` — design source (all sections).
- `docs/archive/handoffs/` — the archived handoff recording this six-stage build effort.
