# tier-layered-teams — usage guide

See [`README.md`](README.md) for what this suite does, the pattern diagram, and the
tier-to-vendor mapping. This file is about *how to actually deploy and dispatch it*, for
both variants.

## Claude Code variant

Role files under [`claude-code/agents/`](claude-code/agents/) map onto Claude Code
subagent definitions the same way as in
[tiered-team-orchestration](../tiered-team-orchestration/USAGE.md): each numbered file
from `01-core-orchestrator.md` on is a YAML-frontmatter role prompt (`model`, `name`,
`description`, `tools`, `agents`) dispatched as a subagent. `00-escalation-protocol.md`
is the odd one out — it mirrors [`PROTOCOL.md`](PROTOCOL.md) and is a shared reference
every role consults before picking a tool tier, not itself a dispatch target; it carries
no `model` field. On another harness, adapt the frontmatter to that harness's
subagent/model-routing mechanism — the role structure and the escalation protocol
underneath don't change.

**Before dispatching**: workers self-escalate to the same external binaries the copilot
variant's preflight doctor checks for (`rg`, `fd`, `ast-grep`, `jq`, `comby`, `make
check` — see the tool-axis tables in [`PROTOCOL.md`](PROTOCOL.md)). Run
[`copilot/scripts/preflight.sh`](copilot/scripts/preflight.sh) against the target repo
first; a missing T1/T2 binary doesn't fail loudly, it silently no-ops.

A run starts by dispatching
[`claude-code/agents/01-core-orchestrator.md`](claude-code/agents/01-core-orchestrator.md)
with the goal; it decomposes the work into team-scoped assignments and routes to the
three leads exactly as in the parent suite, except every worker now also carries a tool
tier it can self-escalate within (see the worked example below).

## Copilot variant

There's no `install.sh` support for this — deliberate, matching the
tiered-escalation-suite precedent (`install.sh`'s `suites` mapping only targets Claude
Code; see [`scripts/harnesses.json`](../../scripts/harnesses.json)). Deploy by hand
instead:

```bash
cp -R suites/tier-layered-teams/copilot/. <target-repo>/
```

The payload mirrors the target repo's root (`.github/` plus its supporting skills,
hooks, scripts, `Makefile`, and `.vscode` config — see README's Components section).
Merge instead of overwriting if the target repo already has any of these.

**Moving targets** — Copilot tool ids, hook JSON shapes, the per-subagent `model` field,
and preview flags are unverified/moving targets: confirm against current VS Code Copilot
docs before relying on them.

## Worked example

Dispatching the Core Orchestrator for a task that exercises both axes: "Rename the
config key `apiTimeout` to `requestTimeoutMs` everywhere it's used across ~40 files; one
use site is in the auth middleware."

```
# Initial dispatch to the Core Orchestrator
{
  "goal": "Rename config key apiTimeout to requestTimeoutMs across the codebase
           (~40 use sites, one in auth middleware)",
  "repo": "<repo pointer>"
}
```

```
01-Core-Orchestrator (Opus-tier)
  decomposes the goal into three team-scoped assignments:
    research: "Find every use site of the apiTimeout config key; flag any on a
               trust boundary (auth, request handling)."
    coding:   "Rename apiTimeout to requestTimeoutMs at every use site research finds."
    review:   "Review the rename for completeness and, since one use site is in auth
               middleware, for trust-boundary risk."
  → dispatches Research Lead
```

```
01-Core-Orchestrator → 02-Research-Lead (Sonnet-tier)
  dispatches a Research Worker to find every use site:
    05-Research-Worker (Haiku-tier)
      consults the tool-axis table in PROTOCOL.md → ~40 matches trips the volume trigger
      → self-escalates T0 (grep) to T1 (ast-grep --json); no dispatcher involved,
        this is self-serve within the worker's own ceiling
      logs: { "axis": "tool", "tier": "T1", "trigger": "volume" }
      → returns 40 locators, including src/middleware/auth.ts:17
  Research Lead synthesizes:
  { "status": "BRIEF_READY",
    "use_sites": ["...40 file:line locators..."],
    "trust_boundary_site": "src/middleware/auth.ts:17" }
  → returns synthesis to Core Orchestrator
```

```
01-Core-Orchestrator → 03-Coding-Lead (Sonnet-tier)
  dispatches a Coding Worker with the 40 locators:
    06-Coding-Worker (Haiku-tier)
      same volume trigger applies to the edit → T1: ast-grep structural rewrite
      writes the diff and shows it before applying — the diff-before-apply invariant
      holds at every tier, not just T0 — then applies
      logs: { "axis": "tool", "tier": "T1", "trigger": "volume" }
  Coding Lead synthesizes:
  { "status": "CHANGES_READY",
    "files_changed": ["...40 files..."],
    "summary": "apiTimeout renamed to requestTimeoutMs at all 40 use sites via a T1
                 ast-grep rewrite." }
  → returns synthesis to Core Orchestrator
```

```
01-Core-Orchestrator
  src/middleware/auth.ts:17 is a trust boundary → applies the high-stakes trigger.
  This is a model-axis escalation, decided one level up by the Orchestrator itself —
  neither worker could have self-served it.
  logs: { "axis": "model", "tier": "Opus", "trigger": "high-stakes" }
  → dispatches 04-Review-Lead at its Opus-tier variant
```

```
01-Core-Orchestrator → 04-Review-Lead (Opus-tier, escalated)
  dispatches one Review Worker per check:
    07-Review-Worker (Haiku-tier) → runs the repo's deterministic gate (make check)
    07-Review-Worker (Haiku-tier) → cross-checks the rename count two independent ways
                                     (ast-grep --json | jq length  vs.  rg -c count)
    07-Review-Worker (Haiku-tier) → checks src/middleware/auth.ts:17 specifically for
                                     any lingering reference to the old key name
  → 3 workers return pass/fail digests (≤5 lines each, no raw logs — never raw logs
    is itself an invariant, unscaled by the Opus-tier escalation)
  Review Lead synthesizes a verdict:
  { "status": "APPROVED",
    "note": "All 40 sites renamed, gate green, auth middleware clean." }
  → returns synthesis to Core Orchestrator
```

```
# Final integration and report from the Core Orchestrator:
DONE — apiTimeout renamed to requestTimeoutMs at all 40 use sites. The Research and
Coding Workers each self-escalated tool tier to T1 (ast-grep) on the volume trigger;
the auth-middleware use site triggered a model-axis escalation to an Opus-tier review,
decided by the Orchestrator, never self-served. Approved.
```
