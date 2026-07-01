---
date: 2026-07-01
description: Built all six stages of the Capability-Scoped Agent Suite (GitHub Copilot/VS Code design) onto this repo; never live-tested
status: active
tags: [handoff, archive]
scope: archive.handoffs
---

# Handoff

## What was completed this session

**Stage 6 — Measure** (FINAL STAGE — overall goal met)

## Completed work

### Files (Stage 6)

| File | What it contains |
|---|---|
| `scratch/metrics.csv` | New (`scratch/` dir didn't exist; created it). Header-only CSV, byte-for-byte the schema already committed in `.github/skills/trigger-semantics/SKILL.md`: `task_id, agent, tier, trigger, tool, tokens_in, tokens_out, tool_calls, make_check, crosscheck`. Verified identical via `diff` against the SKILL.md's header line. No data rows — stays a real, empty scaffold; no telemetry has ever been collected. |
| `scripts/ab-report.sh` | New, originally-authored (no literal template exists in the design beyond the kill-criteria prose in §16). Reads a metrics CSV (default `./scratch/metrics.csv`), sums `tokens_in + tokens_out + tool_calls` per row, groups by an 11th `variant` column (`baseline` / `skill` — a minimal, documented extension beyond the committed file's 10-column header, needed only so the script has something to group by), computes `delta = baseline_total - skill_total`, and applies §16's primary kill criterion: `delta <= 0` → prints `KILL/MERGE`, else prints `KEEP`. No-op (`exit 0`, "nothing to A/B") when the file is missing or has no baseline/skill rows — matches today's real, empty `scratch/metrics.csv`. Ships `--self-test` in the same convention as every other script in `scripts/` (`set -euo pipefail`, self-contained tmp-dir, bash-3.2-compatible), fabricating one net-negative synthetic CSV (asserts `KILL/MERGE` is printed) and one net-positive synthetic CSV (asserts `KEEP` is printed). Does not implement the two secondary/optional kill criteria from §16 (subagent handoff overhead vs. naive read; tool count nearing 128) — not requested, no data shape to test them against yet. |

### Key design decisions

- **`variant` column is a script-side extension only, not added to the committed `scratch/metrics.csv`.** The Stage 6 task explicitly required the shipped CSV to stay byte-for-byte the `trigger-semantics` 10-column header; `ab-report.sh` needs an 11th `variant` column to distinguish baseline from skill runs, so that column is documented as something to append only once/if real rows are ever logged — not retrofitted into the empty scaffold speculatively.
- **`ab-report.sh` always exits 0**, whether it prints `KILL/MERGE` or `KEEP` — it is a report, not an enforced gate. No hook in `.github/hooks/` was touched or added this stage (out of scope per the Key constraints), so nothing consumes a non-zero exit from this script; making it non-zero-on-kill would be speculative plumbing for a consumer that doesn't exist.
- **`.vscode/settings.json` intentionally NOT touched.** §16 marks `github.copilot.chat.otel.*` export as requiring a live Langfuse/Grafana sink to mean anything (§6 lists Langfuse/Grafana as soft/optional prerequisites, not core), and names VS Code's built-in Chat Debug View as the documented zero-install fallback for tokens/tool-calls/cache-hit-rate. No live VS Code+Copilot runtime was available this session (or any prior stage) to validate what wiring OTel export would actually do. Same caution already applied in Stage 5 to the subagent-preview flags.
- **No changes to `.github/agents/`, `.github/skills/`, or `.github/hooks/`** — Stages 3–5 stay closed, per this stage's explicit constraint.
- **No skill was killed, merged, or deleted.** `scratch/metrics.csv` has zero data rows; there is no real telemetry to apply the kill criteria to. `ab-report.sh`'s verdicts (`KILL/MERGE` / `KEEP`) were only ever produced against fabricated synthetic CSVs inside its own `--self-test`, in a `mktemp -d` tmp dir, never against real usage data. **No real skill was measured or killed this turn or at any point in this 6-stage effort.**

### Verification

| Check | Result |
|---|---|
| `diff` of `scratch/metrics.csv` header vs. `.github/skills/trigger-semantics/SKILL.md`'s header line | identical, byte-for-byte |
| `bash scripts/ab-report.sh --self-test` | PASS (net-negative synthetic CSV → `KILL/MERGE`; net-positive synthetic CSV → `KEEP`; missing-file case → exit 0) |
| `bash scripts/ab-report.sh` against the real (empty) `scratch/metrics.csv` | `ok: no baseline/skill rows in ./scratch/metrics.csv, nothing to A/B` |
| `bash scripts/validate-handoff.sh --self-test` | PASS (no regression) |
| `bash scripts/hook-block-apply-without-diff.sh --self-test` | PASS (no regression) |
| `bash .github/skills/astgrep-rewrite/scripts/preview.sh --self-test` | PASS (no regression) |
| `bash scripts/cross-check.sh --self-test` | PASS (no regression) |
| `bash scripts/cap-output.sh --self-test` | PASS (no regression) |
| `make check` | exit 0, `All checks passed.` (only pre-existing warns: skills without eval suites, unrelated to this stage) |
| `git status --short --untracked-files=all` after commit | only `handoff.md` untracked |

**No live VS Code + GitHub Copilot Chat agent-mode runtime was available** at any point in this 6-stage effort to confirm any hook fires, any subagent delegation works, or any skill auto-triggers as documented. Static JSON/YAML/CSV validation plus self-tests of the underlying scripts is the sufficient, intended verification for a dormant, statically-authored suite — consistent with every prior stage.

### Commits this session

- `27284f6` — Stage 6's 2 new files (`scratch/metrics.csv` + `scripts/ab-report.sh`).
- `handoff.md` intentionally left uncommitted, per this repo's established convention.

## Phase state (design's own build-order table, §17) — ALL STAGES COMPLETE

| Task | Status | Notes |
|---|---|---|
| Stage 1 — Floor | ✅ Done (commit `7300b8c`) | orchestrator contract + Makefile + tasks.json + terminal allow/deny + empty mcp.json |
| Stage 2 — Gates | ✅ Done (commit `596b818`) | 2 hook configs + hook impl script + cross-check/validate-handoff/cap-output scripts, each self-tested |
| Stage 3 — Brains | ✅ Done (commit `53eb45f`) | trigger-semantics skill (centralized) + Surveyor/Transformer agent bodies (genre-local tier tables) |
| Stage 4 — Executors | ✅ Done (commits `a3c05b8`, `f298ad2`) | survey-search/extract, astgrep-rewrite (+ bundled preview.sh), scratch-script (+ aggregate.ts template) |
| Stage 5 — Isolation | ✅ Done (commit `e6d58cc`) | verifier.agent.md + validate-handoff.json hook; `.vscode/settings.json` and `surveyor.agent.md` deliberately untouched |
| Stage 6 — Measure | ✅ Done (commit `27284f6`) | `scratch/metrics.csv` scaffold (header-only) + `ab-report.sh` kill-criteria tooling, self-tested against synthetic data; no live OTel sink, no real skill measured |

## Overall goal met — closing summary

This effort built out the full "Capability-Scoped Agent Suite" design (`.tmp/capability-scoped-agent-suite.html`) across all six stages, dogfooded onto this repo: an orchestrator contract with `make check` as its single deterministic gate (Stage 1); hard-gate hooks and scripts that block un-diffed applies and validate handoff records rather than trusting instructions alone (Stage 2); a centralized `trigger-semantics` skill plus Surveyor/Transformer agent bodies that decide tool-escalation tiers from named triggers (Stage 3); four narrow, on-demand executor skills — `survey-search`, `survey-extract`, `astgrep-rewrite`, `scratch-script` — each wrapping a single deterministic tool (Stage 4); a `verifier` subagent that isolates raw check output from the agents that consume it, plus the handoff-schema hook that was defined but left unwired until this stage closed the loop (Stage 5); and finally, in this session, the measurement scaffolding and A/B/kill-criteria tooling that the design's own thesis — "a skill is guilty until measured" — requires before any skill can be trusted long-term (Stage 6).

The central design tension running through every stage: this is a suite of GitHub Copilot/VS Code-specific artifacts (`.github/agents/`, `.github/skills/`, `.github/hooks/`, `.vscode/settings.json`), built as literally as the design doc specifies, dogfooded onto a repo (`ai-personal`) whose actual daily driver is Claude Code, not Copilot. That mismatch was an explicit, upfront user decision (Decision #1, carried through all six stages), not an oversight discovered late: the artifacts are accepted to stay dormant here, valuable as a faithfully-built reference design rather than as something exercised in this repo's real workflow.

**The single largest caveat of the whole effort, stated plainly: no artifact from any of the six stages has ever been exercised in a live VS Code + GitHub Copilot Chat agent-mode session.** Every hook, every agent body, every skill's auto-triggering, every subagent delegation, and this session's kill-criteria tooling has been verified only statically — JSON/YAML validation, self-tests against synthetic fixtures, and `make check` — never against a real Copilot runtime. This is not a gap specific to Stage 6; it spans Stages 1 through 6 uniformly, because no such runtime was available in this sandboxed environment at any point in the effort.

## Open items

| # | Item | Status |
|---|---|---|
| 1 | Hook JSON schema: VS Code product docs + the `microsoft/vscode-copilot-chat` extension repo agree on `hookSpecificOutput.permissionDecision` (nested), but a third, more generic GitHub Copilot hooks-reference page shows `permissionDecision` un-nested at the top level. Implemented the VS Code-specific (nested, doubly-corroborated) shape in `scripts/hook-block-apply-without-diff.sh`. | Open — needs an actual live VS Code + Copilot Chat hooks-preview install to confirm; best-effort research ceiling reached. |
| 2 | `scripts/validate-handoff.sh` enforces an originally-authored minimal schema (`task_id` + `status`); no literal handoff-JSON schema ever surfaced in the design doc across all six stages. | Open — no upgrade planned unless a future live run surfaces fields the minimal schema is missing. |
| 3 | No artifact from any of the six stages (hooks, agent bodies, skill auto-triggering, subagent delegation, this session's `ab-report.sh` against real data) has ever been exercised in a live VS Code + GitHub Copilot Chat agent-mode session. | Open — the effort's single largest standing caveat, spanning Stages 1–6 uniformly. Only resolvable by actually running the suite in that runtime. |
| 4 | `surveyor.agent.md` doesn't declare `agents:`/`handoffs:` for its optional Verifier invocation (§11(b): "Surveyor optionally, for aggregate cross-checks"), unlike `transformer.agent.md` which does. | Open — deferred at Stage 5 as scope expansion beyond that stage's file list; candidate for a small follow-up whenever Surveyor's aggregate-cross-check path is actually exercised live. |
| 5 | `.vscode/settings.json` still has neither the subagent-preview flags (`chat.customAgentInSubagent.enabled` / `chat.subagents.allowInvocationsFromSubagents`, §18) nor OTel export config (`github.copilot.chat.otel.*`, §16) — both deliberately left unset across every stage that touched on them. | Open — informational; revisit only if/when this suite is ever run live in actual VS Code + Copilot. |

## Standing rules (for whoever reads this next)

- This handoff is **terminal**: the originally-locked task list (Stages 2 through 6 of the Capability-Scoped Agent Suite effort) is now fully complete. Do not invent a "Stage 7" or further work from this document alone.
- The next step in the surrounding workflow is for the orchestrating process to invoke the `ingest-handoff` skill against this file (extracting durable content into ADRs / `docs/memory/`) — that skill was not available in this sandboxed turn, so it was not invoked here.
- Any genuinely new work (e.g., actually running the suite live, upgrading the handoff schema, wiring OTel) should start from a fresh scoping conversation with the user, using the Open items above as candidate starting points — not by treating this handoff as still having a "Next task."
