---
date: 2026-07-01
description: Status and operating notes for the GitHub Copilot/VS Code Capability-Scoped Agent Suite
status: superseded
tags: [copilot, vscode, agent-suite]
---

# Capability-Scoped Agent Suite — status and operations

**Superseded (2026-07-08)**: the top-level `.github/`, `.vscode/`, and root-level suite scripts
this document describes were deleted from the repo as part of curating it for public release —
see ADR-0001's superseded note. The design lives on solely as
[`workflows/tiered-escalation-suite/`](../../workflows/tiered-escalation-suite/README.md), a more
complete, generalized, distributable payload. Kept below for historical context.

## What it is

A six-stage GitHub Copilot/VS Code agent-orchestration design (source:
`.tmp/capability-scoped-agent-suite.html`), fully built onto this repo. See
[ADR-0001](../adrs/ADR-0001-target-copilot-vscode-for-agent-suite.md) for why it targets
Copilot/VS Code rather than this repo's actual daily driver, Claude Code.

## Status: fully built, never live-tested

All six stages are complete and committed. **No artifact has ever run in a live VS Code +
GitHub Copilot Chat agent-mode session** — every verification across all six stages was static
(JSON/YAML validation, self-tests against synthetic fixtures, `make check`). It is dormant under
Claude Code.

## Where things live

| Surface | Path |
|---|---|
| Orchestrator contract | `.github/copilot-instructions.md` |
| Agent bodies | `.github/agents/{surveyor,transformer,verifier}.agent.md` |
| Skills | `.github/skills/{trigger-semantics,astgrep-rewrite,survey-search,survey-extract,scratch-script}/SKILL.md` |
| Hard-gate hooks | `.github/hooks/{block-apply-without-diff,run-make-check,validate-handoff}.json` |
| Hook/gate script implementations | `scripts/{hook-block-apply-without-diff,cross-check,validate-handoff,cap-output}.sh` |
| Measurement scaffold | `scratch/metrics.csv` (header-only, no data rows) + `scripts/ab-report.sh` |
| VS Code wiring | `.vscode/{settings,tasks,mcp}.json` |

## How to validate

`make check` (wraps `bash scripts/validate.sh`) is the one deterministic sensor for this repo.
Every hook/gate script also ships its own `--self-test` flag, e.g.
`bash scripts/hook-block-apply-without-diff.sh --self-test`.

## How to use the measurement tooling

`scratch/metrics.csv` is a real, empty scaffold — no skill has ever been measured. Once/if rows
are ever logged (schema: `task_id, agent, tier, trigger, tool, tokens_in, tokens_out, tool_calls,
make_check, crosscheck`, per `.github/skills/trigger-semantics/SKILL.md`), add an 11th `variant`
column (`baseline`/`skill`) and run `bash scripts/ab-report.sh [path-to-csv]`. It sums
`tokens_in + tokens_out + tool_calls` per row, computes `delta = baseline_total - skill_total`,
and prints `KILL/MERGE` when `delta <= 0`, else `KEEP` — the design's kill criterion (§16). It
no-ops cleanly on a missing/empty file.

## Prerequisite to actually activating this suite

Open VS Code on this repo with GitHub Copilot Chat in agent mode, and enable the hooks preview
flag — hooks are Preview/experimental in VS Code Copilot Chat. See
[ADR-0002](../adrs/ADR-0002-hook-filtering-in-scripts-not-matcher.md) for a real-schema finding
that already differs from the design doc's illustrative templates.
