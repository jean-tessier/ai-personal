---
date: 2026-07-01
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
| 7 | `tasks` category name carries a stray `.md` from `catalog.sh`'s file-basename vs. `harnesses.json`'s `{name}.md` template — defensively stripped in `install.sh`, untested against real data since `prompts/tasks/` is currently empty | tech-debt | low | handoff.md § Open items (vendor-agnostic-installer) | 2026-07-01 | |
| 8 | `feature/vendor-agnostic-installer` is committed locally (5 commits: harnesses.json, install.sh, README docs, validate.sh integration, ADR/memory ingestion) but not pushed; `origin/main` is still at `1763ef7`, predating this whole effort | future-work | normal | handoff.md § Open items (vendor-agnostic-installer) | 2026-07-01 | partially resolved 2026-07-01 (committed; push still open) |

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
