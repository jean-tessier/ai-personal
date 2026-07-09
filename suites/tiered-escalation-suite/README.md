# tiered-escalation-suite

A capability-scoped GitHub Copilot/VS Code agent suite, packaged as a **drop-in payload**
for a *target* project — unlike this repo's other suites, none of these files are read
in place by Claude Code; `.github/`, `.vscode/`, `Makefile`, `.gitignore`, and `scripts/`
are meant to be copied verbatim into a target repo's root (see [USAGE.md](USAGE.md)).

Two peer agents split on the one boundary the harness can enforce — **read-only vs.
write-capable** — plus a verification layer that is a **gate, not a destination**.
Genre selects the agent (enforced by the `tools` allowlist); the tiered escalation
ladder selects the tool (decided per task).

```
orchestrator ─┬─▶ Surveyor    (read-only: locate · count · map · aggregate)
              └─▶ Transformer (write-capable: rewrite · rename · codemod; diff-gated every tier)
                     └─▶ Verifier (cross-cut: hard gates + callable subagent; never a route target)
```

## Entry point

Deploy the payload into a target repo (see [USAGE.md](USAGE.md)), then open it in VS Code
with Copilot **agent mode**. [`.github/copilot-instructions.md`](.github/copilot-instructions.md)
is the always-on routing contract every request pays for; the two dispatchable peers are
[`.github/agents/surveyor.agent.md`](.github/agents/surveyor.agent.md) and
[`.github/agents/transformer.agent.md`](.github/agents/transformer.agent.md).

## Components

| Path | Role |
|---|---|
| [.github/copilot-instructions.md](.github/copilot-instructions.md) | Always-on orchestrator contract: route by capability (genre), default Tier 0, escalate only on a named trigger |
| [.github/agents/surveyor.agent.md](.github/agents/surveyor.agent.md) | Read-only peer — locate/count/map/aggregate; no `edit_file` in its tool allowlist |
| [.github/agents/transformer.agent.md](.github/agents/transformer.agent.md) | Write-capable peer — rewrite/rename/codemod; shows a diff before every apply, at every tier |
| [.github/agents/verifier.agent.md](.github/agents/verifier.agent.md) | Callable subagent, never a route target — runs `make check` + cross-checks, returns pass/fail + a ≤5-line digest |
| [.github/skills/trigger-semantics](.github/skills/trigger-semantics/SKILL.md) | Centralized escalation-tier decision table (T0–T3), consulted by both peers before picking a tool |
| [.github/skills/survey-search](.github/skills/survey-search/SKILL.md) | Surveyor Tier-1 executor: structural/AST search via `ast-grep` |
| [.github/skills/survey-extract](.github/skills/survey-extract/SKILL.md) | Surveyor Tier-1 executor: JSON/stats extraction via `jq`/`tokei` |
| [.github/skills/astgrep-rewrite](.github/skills/astgrep-rewrite/SKILL.md) | Transformer Tier-1 executor: structural rewrite via `ast-grep`; its bundled [scripts/preview-rewrite.sh](.github/skills/astgrep-rewrite/scripts/preview-rewrite.sh) writes the diff the apply hook requires |
| [.github/skills/scratch-script](.github/skills/scratch-script/SKILL.md) | Tier-2 executor (either genre): throwaway aggregation/codemod script from its [templates/aggregate.ts](.github/skills/scratch-script/templates/aggregate.ts); only a compact artifact re-enters context |
| [.github/hooks/block-apply-without-diff.json](.github/hooks/block-apply-without-diff.json) | `PreToolUse` hard gate: blocks an apply/rewrite command unless `scratch/handoff/pending.diff` exists |
| [.github/hooks/run-make-check.json](.github/hooks/run-make-check.json) | `PostToolUse` hard gate: runs `make check` after every edit |
| [scripts/crosscheck.sh](scripts/crosscheck.sh) | Hard gate: two independently-computed counts must match |
| [scripts/size-cap.sh](scripts/size-cap.sh) | Hard gate: aborts a raw dump over a line budget, forcing escalation to Tier 2 |
| [scripts/validate-handoff.sh](scripts/validate-handoff.sh) + [scripts/handoff.schema.json](scripts/handoff.schema.json) | Hard gate: validates a handoff JSON against the schema (ajv, `jq -e` fallback) — [scripts/sample-handoff.json](scripts/sample-handoff.json) is a worked example |
| [scripts/preflight.sh](scripts/preflight.sh) / [scripts/install-prereqs.sh](scripts/install-prereqs.sh) | Toolchain doctor and installer for the binaries the agents shell out to (`rg`, `fd`, `ast-grep`, `jq`, `tokei`, `comby`) |
| [Makefile](Makefile) | The single `make check` sensor — wired identically into `.vscode/tasks.json` and the `PostToolUse` hook |
| [.vscode/settings.json](.vscode/settings.json), [.vscode/tasks.json](.vscode/tasks.json), [.vscode/mcp.json](.vscode/mcp.json) | Terminal auto-approve/deny lists, the `make check` task, and an empty MCP config reserved for a future Tier-3 Integrator peer |
| [scratch/](scratch/.gitkeep) | Runtime-only working dir in the *target* repo (intermediates, `handoff/pending.diff`, `metrics.csv`) — gitignored there except its two `.gitkeep` placeholders |

## The one operational fact: hard vs. soft

Instructions and skill bodies are **soft** — the model may ignore them. Only a handful of
things are **hard**, so every critical gate is encoded as one of them, never as prose:

| Gate | Mechanism | Strength |
|---|---|---|
| Diff before apply | `PreToolUse` hook blocks apply unless `scratch/handoff/pending.diff` exists | **hard** |
| Lint/type/test sensor | `PostToolUse` hook runs `make check`; non-zero halts | **hard** |
| Cross-check-two-ways | `scripts/crosscheck.sh` exits non-zero on mismatch | **hard** |
| Output-size cap | `scripts/size-cap.sh` aborts a raw dump, forces Tier 2 | **hard** |
| Handoff schema | `scripts/validate-handoff.sh` (ajv, `jq -e` fallback) | **hard** |
| Read-only confinement | Surveyor has no `edit_file`; global `denyList` blocks rm/sudo/curl/chmod | **hard** |
| Tier discipline / "default T0" | skill body + orchestrator prose | soft |

Surveyor's read-only-ness is enforced two ways: (a) no `edit_file` in its `tools`,
(b) the workspace `denyList` on destructive shell commands. There is no per-agent
terminal scoping in the harness — the `tools` allowlist is the real capability wall.

## Measurement is mandatory

SkillsBench: curated skills lift pass rate ~16pp on average but **16 of 84 tasks go
negative**, and self-generated skills net **−1.3pp**. A skill is guilty until measured.
Turn on OTel export (`github.copilot.chat.otel.*`) or read the Chat Debug View summary,
log per-task rows to `scratch/metrics.csv` (schema in `trigger-semantics`), and A/B each
skill against a no-skill baseline. **Kill criteria:** skill net ≤ 0 on a known op →
merge/delete; subagent handoff overhead > naive read for a task class → stop delegating it.

## Where this hardened the spec (deviations, on purpose)

- **Diff artifact is a single canonical file** `scratch/handoff/pending.diff`, not a
  `*.diff` glob. `test -f <glob>` breaks on multi-match and passes on stale files; the
  preview script clears old diffs and writes exactly one. Residual edge: a `pending.diff`
  left from a prior op could pass — a stronger version would hash-match diff↔apply target.
- **`ast-grep` binary name everywhere** (not `sg`). On this build and most Linux, `sg`
  is util-linux's set-group — a mis-resolved `sg` fails *silently* inside a gate. The
  `autoApprove` regex, preview script, and preflight all guard for it.
- **preflight distinguishes core from optional.** A missing `ajv` no longer fails
  preflight (the `jq -e` fallback covers the handoff gate); only missing *core* binaries do.
- **Verifier `.agent.md` authored from intent.** The spec described it (hooks + callable
  subagent) but shipped no body; this one returns only a verdict + ≤5-line digest and
  states explicitly that it is *not* the enforcement.

## Validate before you trust (moving targets)

- **Tool identifiers** (`read_file`, `edit_file`, `terminal`) and the agent/skill
  frontmatter fields follow the design's convention — confirm the real VS Code Copilot
  tool ids (may be e.g. `editFiles`, `runInTerminal`) and field names against current docs.
- **Hook JSON shapes** are illustrative — validate against the current hooks schema.
- **OTel setting keys** (`github.copilot.chat.otel.*`) are best-effort — confirm against release notes.
- **Preview flags** (`chat.customAgentInSubagent.enabled`, `chat.subagents.allowInvocationsFromSubagents`)
  and skill `context: fork` may change; the per-subagent `model` field has a known bug
  (microsoft/vscode #291883) — don't rely on a cheaper subagent model for cost control yet.
- **Tier 3 is a stub.** `mcp.json` is empty; the external/stateful trigger routes to
  "defer". Adding an Integrator peer later is adding a capability scope — the clean trigger.

## Conventions

- This is a **drop-in payload**, not something read in place: `.github/`, `.vscode/`,
  `Makefile`, `.gitignore`, and `scripts/` are copied verbatim to a target repo's root —
  see [USAGE.md](USAGE.md). The nested `.github/...` paths are load-bearing; VS Code
  Copilot only recognizes agents/skills/hooks at those exact locations, so nothing here
  is flattened the way `hub-and-spoke-orchestration/agents/` is.
- Two `scripts/` directories exist at different scopes — don't conflate them: the
  top-level [scripts/](scripts/) holds repo-wide gates (crosscheck, size-cap,
  validate-handoff, preflight, install-prereqs); `.github/skills/astgrep-rewrite/scripts/`
  holds a script bundled with that one skill.
- This repo already dogfoods an earlier iteration of the same design at its own root
  (`.github/agents/`, `.github/skills/`, `.github/hooks/`, `.vscode/` — see
  `docs/adrs/ADR-0001-target-copilot-vscode-for-agent-suite.md`). This suite is a
  separate, later revision of that design packaged for distribution to *other* projects —
  not a replacement for that dogfood, and the two are not kept in sync.
