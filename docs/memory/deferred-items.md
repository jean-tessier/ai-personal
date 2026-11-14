---
date: 2026-11-13
description: Known deferred items, open decisions, and future work to revisit in later sessions
status: active
tags: [backlog, deferred]
scope: memory.deferred
---

# Deferred Items

Items explicitly set aside during prior sessions. Resolved items are struck through and dated in the Status column.

| # | Item | Type | Priority | Source | Added | Status |
|---|---|---|---|---|---|---|
| 1 | Confirm hook permissionDecision nesting via live VS Code + Copilot install | open-decision | normal | handoff.md § Open items | 2026-07-01 | |
| 2 | Define real ./scratch/handoff/*.json schema beyond task_id+status minimum | tech-debt | low | handoff.md § Open items | 2026-07-01 | |
| 3 | Run Capability-Scoped Agent Suite live in VS Code + Copilot Chat to verify | future-work | high | handoff.md § Open items | 2026-07-01 | |
| 4 | Add agents:/handoffs: to surveyor.agent.md for optional Verifier calls | tech-debt | low | handoff.md § Open items | 2026-07-01 | |
| 5 | Decide on subagent-preview flags + OTel export in .vscode/settings.json | future-work | low | handoff.md § Open items | 2026-07-01 | |
| 6 | Installed-assets manifest for future uninstall/update support (`install.sh`) | future-work | normal | handoff.md § Open items (vendor-agnostic-installer) | 2026-07-01 | |
| 7 | ~~`tasks` category name carries a stray `.md` from `catalog.sh`'s file-basename vs. `harnesses.json`'s `{name}.md` template — defensively stripped in `install.sh`, untested against real data since `prompts/tasks/` is currently empty~~ | tech-debt | low | handoff.md § Open items (vendor-agnostic-installer) | 2026-07-01 | moot 2026-07-08 (`prompts/tasks/` and the `tasks` category removed entirely — see ADR-0001 superseded note) |
| 8 | `feature/vendor-agnostic-installer` is committed locally (5 commits: harnesses.json, install.sh, README docs, validate.sh integration, ADR/memory ingestion) but not pushed; `origin/main` is still at `1763ef7`, predating this whole effort | future-work | normal | handoff.md § Open items (vendor-agnostic-installer) | 2026-07-01 | partially resolved 2026-07-01 (committed; push still open) |
| 9 | `install.sh`'s Copilot-suite translation (ADR-0007) is gated by three `is_copilot_suite_category()` calls hardcoded in `install.sh`'s own control flow, not expressed as data in `scripts/harnesses.json` the way `mapping` is — a partial reintroduction of the harness-name branching ADR-0003 was written to eliminate | tech-debt | normal | code review, 2026-07-13 session | 2026-07-13 | |
| 10 | Add test_deps_unsupported_category_warns case to scripts/test-install.sh | tech-debt | low | handoff.md § Open items (asset-dependency-manifest) | 2026-07-12 | |
| 11 | Decide whether/when to merge feature/asset-dependency-manifest into main | open-decision | normal | handoff.md § Open items (asset-dependency-manifest) | 2026-07-12 | conflicts against main resolved 2026-07-16 (PR #9); merge itself still the user's call |
| 12 | Re-run the plan-dag trigger suite with a higher max_turns; 93 of 160 runs hit the 4-turn cap, so later triggers are never seen (~$23) | tech-debt | normal | PR #11 (plan-dag evals) and its independent review | 2026-11-13 | |
| 13 | Re-evaluate the scoped expand-then-contract wording in plan-dag (`oversized-slice`, 5 runs each of A and the skill, ~$12) | future-work | normal | PR #11 (plan-dag evals) and its independent review | 2026-11-13 | |
| 14 | Re-run the full plan-dag A-vs-B behaviour test on the finished skill (~$110); the pre-registered test ran on the pre-fix skill and later re-evals covered selected cases only | future-work | normal | PR #11 (plan-dag evals) and its independent review | 2026-11-13 | |
| 15 | Re-run the eval smoke stage after the CLI upgrade from 2.1.322 to 2.1.323 (a few cents) | tech-debt | low | PR #11 (plan-dag evals) and its independent review | 2026-11-13 | |
| 16 | Run paid evals on Linux or in a container: the subject's `git` fails inside the macOS sandbox (xcrun shim), costing both arms turns | tech-debt | low | PR #11 (plan-dag evals) and its independent review | 2026-11-13 | |
| 17 | `o-j6-owner-questions` still fails most runs (3/5 at best even after the skill asks the owner to rule); revisit the criterion | tech-debt | normal | PR #11 (plan-dag evals) and its independent review | 2026-11-13 | |
| 18 | `s-plan-only-close` regex rejects valid rewordings of "nothing was built"; widen or move to a judge | tech-debt | low | PR #11 (plan-dag evals) and its independent review | 2026-11-13 | |
| 19 | The plan-dag "at most 4 questions per call" rule can't be tested headless: `AskUserQuestion` is absent in `claude plugin eval` runs | future-work | low | PR #11 (plan-dag evals) and its independent review | 2026-11-13 | |
| 20 | plan-dag's dispatch, watch and close-out phases are not evaluated (the runner refuses Monitor and worktree tools) | future-work | low | PR #11 (plan-dag evals) and its independent review | 2026-11-13 | |
| 21 | plan-dag references `review-loop`, `board-refresh` and `session-retro` skills and `.claude/agents/builder.md`, none of which ship in this repo: add them or drop the steps | open-decision | normal | PR #11 (plan-dag evals) and its independent review | 2026-11-13 | partly resolved 2026-11-13: `skills/review-loop` added; `board-refresh`, `session-retro` and `builder.md` still missing |
| 22 | Implement ADR-0008 suite manifest: resourceKinds in harnesses.json, manifest.json read/validate in catalog.sh/validate.sh/install.sh, migrate tier-layered-teams, decide merge-mode semantics | future-work | normal | ADR-0008 (PR #10) | 2026-11-13 | |

> Item 1: two corroborating VS Code-specific sources (product docs + the
> `microsoft/vscode-copilot-chat` extension repo) show `hookSpecificOutput.permissionDecision`
> nested; a third, more generic GitHub Copilot hooks reference shows it un-nested — likely a
> different Copilot surface (CLI/cloud agent), not VS Code. The nested shape was implemented in
> `scripts/hook-block-apply-without-diff.sh`; see ADR-0002.
>
> Item 3: no artifact from any of the six build stages (hooks, agent bodies, skill
> auto-triggering, subagent delegation, `ab-report.sh` against real data) has ever run in a live
> VS Code + GitHub Copilot Chat agent-mode session. This is the effort's single largest standing
> caveat, spanning all six stages uniformly — only resolvable by actually running the suite live.
>
> Item 8: whether/when to commit and push this branch is the user's call, not any task's to decide
> unilaterally — carried forward unresolved from the installer effort's final handoff.
>
> Item 9: surfaced by an independent code-review pass (altitude angle) on ADR-0007's own diff. The
> transform's *content* is narrow and ADR-0007 defends that scope explicitly, but the *decision to
> invoke it* — `$HARNESS == "copilot" && $category == "suites"` — lives in `install.sh` code at
> three call sites (now consolidated behind one `is_copilot_suite_category()` helper, so at least
> they can't drift from each other) rather than in `harnesses.json` data. A deeper fix would give
> `harnesses.json`'s `mapping` schema a way to name a transform/eligibility check per category, and
> have `install.sh` dispatch on it generically — undone here since it's a schema change beyond a
> post-review cleanup pass, not because the critique is wrong.
