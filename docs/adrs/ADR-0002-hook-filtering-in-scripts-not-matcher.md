---
date: 2026-07-01
decision_date: 2026-06-30
description: Filter hook commands in the invoked script, since VS Code ignores the hook JSON matcher field
status: superseded
---

# ADR-0002: Hook Enforcement Lives in Invoked Scripts, Not the JSON `matcher` Field

## Status

Superseded (2026-07-08) — the top-level `.github/hooks/*.json` configs and `scripts/hook-*.sh`
filter scripts this ADR describes were deleted when the repo was curated for public release (see
ADR-0001). The surviving `suites/tiered-escalation-suite/` uses a different, self-contained hook
format (flat `{event, match, run, onNonZero}` with inline matching and no companion filter script),
so this decision was not carried forward. Kept for historical context on the now-removed top-level
implementation.

## Context

The Capability-Scoped Agent Suite design doc's `PreToolUse`/`PostToolUse` hook JSON templates
(`.tmp/capability-scoped-agent-suite.html` §11) are explicitly marked "illustrative — validate
against current hooks schema," and hooks are a Preview/experimental VS Code Copilot Chat feature
(§18). No live VS Code + Copilot Chat install was available to test hooks interactively, so the
real schema was researched via VS Code's own hooks documentation and the
`microsoft/vscode-copilot-chat` extension repository. Two findings, both independently corroborated:

1. The real hook config shape is a top-level `hooks` object keyed by event name (e.g.
   `PreToolUse`, `PostToolUse`), each an array of `{"type":"command","command":...,"matcher":...,
   "timeout"?,...}` — not the design doc's flat `{"event","match","run"}` template.
2. VS Code parses but **ignores** the `"matcher"` field: hooks fire on every tool invocation
   regardless of what `matcher` specifies.

A third, more generic GitHub Copilot hooks-reference source shows the hook output shape
(`permissionDecision`) un-nested at the top level, rather than nested under
`hookSpecificOutput` as the two VS Code-specific sources agree. This narrower ambiguity was not
resolved (see `docs/memory/deferred-items.md`) and does not affect this decision.

## Decision

We will keep `"matcher"` in each hook's JSON config for documentation/intent purposes, but
implement all real command-pattern and precondition filtering inside the script the hook invokes.
For example, `.github/hooks/block-apply-without-diff.json` fires on every tool call, but
`scripts/hook-block-apply-without-diff.sh` itself parses the hook's stdin JSON
(`tool_input.command`) and decides allow/deny — the JSON config does no filtering on its own.

## Consequences

### Positive

- Hooks behave correctly today even though the JSON `matcher` field is inert in VS Code's current
  implementation.
- Any future hook added to this suite has a tested, working pattern to follow: filter in the
  script, not the config.

### Negative

- Every hook script pays the cost of running on every tool invocation rather than being
  pre-filtered by VS Code itself, and must fail closed/cheaply for the common non-matching case.

### Neutral

- If VS Code's hooks implementation is later changed to honor `matcher`, the scripts' own
  filtering becomes redundant but harmless, not broken.

## References

- `.github/hooks/block-apply-without-diff.json`, `.github/hooks/run-make-check.json`,
  `.github/hooks/validate-handoff.json`
- `scripts/hook-block-apply-without-diff.sh`
- `.tmp/capability-scoped-agent-suite.html` §11, §18
