# suites/

Grouped collections of inter-referential prompts and/or skills that only function
together — as distinct from the single, independently-invocable skills in `skills/`.

## When to use `suites/`

| Asset | Lives in | Invocable alone? |
|---|---|---|
| Skill | `skills/{name}/` | Yes |
| Orchestration system | `suites/{name}/` | No — components reference each other and are deployed as a set |

If moving, renaming, or deleting one file would break others in the set, the set
belongs in `suites/`, not scattered across `skills/`.

## Structure per suite

```
{suite-name}/
├── README.md       # What the suite does, the role of each component, the entry point
├── USAGE.md        # How to invoke it: step-by-step guidance and a worked example
└── agents/         # Grouped prompt files, numbered in read/dispatch order
    ├── 00-....md
    ├── 01-....md
    └── ...
```

or, when the components are skills, one subdirectory per skill — same shape as
`skills/{name}/`:

```
{suite-name}/
├── README.md
├── USAGE.md
├── {skill-a}/
│   └── SKILL.md
└── {skill-b}/
    └── SKILL.md
```

or, when a suite ships multiple harness-native variants of the same pattern, one subdirectory
per harness, named by that harness's key in `scripts/harnesses.json`:

```
{suite-name}/
├── README.md         # The pattern, harness-agnostic
├── USAGE.md          # Per-variant invocation
├── PROTOCOL.md        # Shared must-not-drift semantics (optional)
├── claude-code/       # named by the harnesses.json key
│   └── agents/
│       └── ...
└── copilot/            # named by the harnesses.json key
    └── .github/
        └── ...
```

Each variant's mirrored semantics carry a provenance header ("Canonical source: `<relative path>`
— edit there first, then mirror here"). See
[ADR-0006](../docs/adrs/ADR-0006-harness-variant-subdirectories-in-suites.md) for the full decision.

Grouped files live inside a component subdirectory — never loose at the suite's
top level — so `scripts/validate.sh` can tell a real group from an empty placeholder.

## Naming

Kebab-case, describing the orchestration pattern: `hub-and-spoke-orchestration`.

## Plugin-shaped vs. drop-in payload

A suite whose shape already fits Claude Code's/Copilot's native plugin schema (plain
`agents/*.md`, or per-skill directories directly containing `SKILL.md`) carries a root
`.claude-plugin/plugin.json` and is listed in the repo-root
`.claude-plugin/marketplace.json`. That earns it two things from `install.sh`: any
skill dependency it declares gets auto-installed alongside it, and `--harness copilot`
gets a mechanically-translated Copilot-native copy (`agents/*.md` → `agents/*.agent.md`,
manifest relocated to a root `plugin.json`) instead of being skipped.

A suite that's a **drop-in payload** for a *different* target project — its own
`.github/`, `.vscode/`, `Makefile`, and `scripts/*.sh` working together, deployed by
hand — is not plugin-shaped and never will be; forcing that shape onto a payload's
bespoke hook/build wiring would risk breaking it for a cosmetic format match. See
[ADR-0007](../docs/adrs/ADR-0007-suites-as-native-plugins.md) for the full reasoning and
which suites landed on which side.

## Available suites

| Suite | Plugin-shaped? | Description |
|---|---|---|
| [handoff-workflow](handoff-workflow/README.md) | Yes | Multi-session work loop: `handoff.md` carries state between sessions via `resume-handoff`/`handoff-document`, then `ingest-handoff` retires a completed handoff into ADRs, `docs/memory/`, and the handoff archive. Declares `create-adr`/`yaml-frontmatter` as dependencies. |
| [hub-and-spoke-orchestration](hub-and-spoke-orchestration/README.md) | Yes | Multi-agent software-engineering pipeline: a central Orchestrator dispatches Planner/Explorer/Coder/Reviewer/Arbiter/Executor spokes and a Scribe write-path service against one shared protocol. |
| [tier-layered-teams](tier-layered-teams/README.md) | `claude-code/` only | A two-axis orchestration lattice crossing model-cost team tiers (Opus-tier orchestrator, Sonnet-tier leads, Haiku-tier workers) with T0–T3 tool escalation, shipped as Claude Code- and Copilot-native variants. Its `copilot/` variant is a hand-authored drop-in payload, not plugin-translated. |
| [tiered-escalation-suite](tiered-escalation-suite/README.md) | No — drop-in payload | Capability-scoped GitHub Copilot/VS Code agent suite (Surveyor/Transformer peers + Verifier gate), a drop-in `.github/`/`.vscode`/`scripts`/`Makefile` payload for a *target* project, not read in place by Claude Code. |
| [tiered-team-orchestration](tiered-team-orchestration/README.md) | Yes | A three-tier model-cost hierarchy — an Opus-tier core orchestrator plans and routes, Sonnet-tier research/coding/review team leads decompose and synthesize, Haiku-tier workers execute narrow tasks. |
