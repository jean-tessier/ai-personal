# ai-personal

Personal monorepo of reusable Claude Code assets — skills and multi-component suites — kept
in one place with consistent structure, documentation, and a vendor-agnostic installer so they can
be dropped into any project, professional or otherwise.

## Directory map

| Path | Contents |
|------|----------|
| `skills/` | Procedural instruction sets injected into agent context. See [`skills/README.md`](skills/README.md) |
| `suites/` | Grouped, inter-referential skill/prompt collections that only make sense as a set. See [`suites/README.md`](suites/README.md) |
| `docs/` | ADRs, operational memory, and archived session handoffs — the "why" behind this repo's own shape |
| `scripts/` | Catalog generation and structural validation |

## Skills

| Skill | What it does | Harness |
|-------|---------------|---------|
| [atomic-commits](skills/atomic-commits/SKILL.md) | Splits a working diff into clean, atomic commits with dialect-aware messages (Conventional Commits, Changesets, kernel-style, plain prose) | vendor-agnostic |
| [create-adr](skills/create-adr/SKILL.md) | Writes a new Architecture Decision Record to `docs/adrs/`, keeping its index in sync | vendor-agnostic |
| [create-changelog](skills/create-changelog/SKILL.md) | Creates or appends a dated `CHANGELOG.md` entry for a skill | vendor-agnostic |
| [fix-validation](skills/fix-validation/SKILL.md) | Runs `scripts/validate.sh`, auto-fixes mechanical structural issues, reports what needs manual authorship | this repo |
| [readme-maintenance](skills/readme-maintenance/SKILL.md) | Audits and refreshes every README in a repo against a quality rubric | vendor-agnostic |
| [yaml-frontmatter](skills/yaml-frontmatter/SKILL.md) | Validates, adds, or updates YAML frontmatter on documentation files | vendor-agnostic |

## Suites

| Suite | What it does | Harness |
|----------|---------------|---------|
| [handoff-workflow](suites/handoff-workflow/README.md) | Carries multi-session work forward via a `handoff.md` file, then retires it into `docs/adrs/`, `docs/memory/`, `docs/archive/handoffs/` once its goal is met | Claude Code |
| [hub-and-spoke-orchestration](suites/hub-and-spoke-orchestration/README.md) | A multi-agent software-engineering pipeline (orchestrator/planner/explorer/coder/reviewer/arbiter/scribe/executor) built around a strict hub-and-spoke protocol | Claude Code |
| [tier-layered-teams](suites/tier-layered-teams/README.md) | A two-axis orchestration lattice that crosses model-cost team tiers (Opus-tier orchestrator, Sonnet-tier leads, Haiku-tier workers) with T0–T3 tool escalation, shipped as Claude Code- and Copilot-native variants | Claude Code + GitHub Copilot / VS Code |
| [tiered-escalation-suite](suites/tiered-escalation-suite/README.md) | A capability-scoped GitHub Copilot/VS Code agent suite, packaged as a drop-in payload (`.github/`, `.vscode/`, `Makefile`, `scripts/`) for a *target* project | GitHub Copilot / VS Code |
| [tiered-team-orchestration](suites/tiered-team-orchestration/README.md) | A three-tier model-cost hierarchy — an Opus-tier core orchestrator plans and routes, Sonnet-tier research/coding/review team leads decompose and synthesize, Haiku-tier workers execute narrow tasks | Claude Code |

## Installing

Fetch assets into another project with `install.sh`:

```bash
curl -fsSL https://raw.githubusercontent.com/jean-tessier/ai-personal/main/install.sh \
  | bash -s -- --harness claude-code --scope project
```

| Flag | Purpose |
|------|---------|
| `--harness <key>` | harness key from `scripts/harnesses.json` (required) |
| `--scope <key>` | scope key declared for that harness (required) |
| `--assets <a,b,...>` | comma-separated asset categories (default: all available; omit in a terminal for an interactive picker — see below) |
| `--dry-run` | print planned copy operations; write nothing |
| `--force` | overwrite existing destination files/dirs (default: skip existing) |
| `--no-deps` | don't auto-include a selected suite's declared skill dependencies (see below) |
| `-h`, `--help` | show usage |

Harness/scope keys come from `scripts/harnesses.json`:

| Harness | Scopes |
|---------|--------|
| `claude-code` | `project` → `.claude`, `user` → `~/.claude` |
| `copilot` | `project` → `.github` (no `user` scope) |

`copilot` has no `user` scope — don't pass `--scope user` with `--harness copilot`.

Some suites (and every skill) carry a `.claude-plugin/plugin.json`, making them real
Claude Code/Copilot plugins — see
[ADR-0007](docs/adrs/ADR-0007-suites-as-native-plugins.md). For those, `install.sh`:

- **Auto-includes declared dependencies.** A suite that names shared skills in its
  `plugin.json`'s `dependencies` (e.g. `handoff-workflow` needs `create-adr` and
  `yaml-frontmatter`) gets those skills installed alongside it, deduped against
  anything already selected. Pass `--no-deps` to skip this.
- **Translates plugin-shaped suites for `--harness copilot`**: `agents/*.md` →
  `agents/*.agent.md`, and `.claude-plugin/plugin.json` moves to a root `plugin.json` —
  Copilot's own manifest location, per GitHub's docs. A suite without a
  `.claude-plugin/plugin.json` at its root — a drop-in Copilot payload like
  `suites/tiered-escalation-suite/`, or `suites/tier-layered-teams/copilot/` (which
  already ships its own hand-authored Copilot form) — has no translated form and is
  skipped for `copilot` with a one-line notice. `suites/tiered-escalation-suite/` is a
  drop-in payload you copy by hand instead (see its own
  [USAGE.md](suites/tiered-escalation-suite/USAGE.md)).

This repo's root `.claude-plugin/marketplace.json` also makes it directly installable
via `/plugin marketplace add jean-tessier/ai-personal` in Claude Code, alongside (not
instead of) `install.sh`.

Omitting `--assets` in a real terminal launches a picker per category (fzf → gum → numbered
prompt, whichever is available) instead of installing everything. Piped runs (`curl | bash`)
have no TTY on stdin, so they skip the picker and install every category.

## Key conventions

- A skill that's also used inside a suite is referenced from that suite, never forked into
  it — one canonical copy under `skills/{name}/`.
- Skills that only function as a group (e.g. a multi-agent orchestration system) live under
  `suites/{name}/`, not as separate flat assets.
- Skills carry a `CHANGELOG.md` to track drift across model versions.
- Run `bash scripts/catalog.sh > catalog.json` to regenerate the asset index.
- Run `bash scripts/validate.sh` before committing.
- This repo only ships categories with real, finished content — no placeholder directories
  waiting for a first asset.

## Versioning

Skill changes are logged in each skill's `CHANGELOG.md`.
Format: `YYYY-MM-DD · {model-version} · {what changed and why}`

## Running scripts

```bash
bash scripts/validate.sh          # structural lint; exits 1 on failures
bash scripts/catalog.sh           # emits catalog JSON to stdout
bash scripts/catalog.sh > catalog.json
bash scripts/test-install.sh          # install.sh behavioral tests, sandboxed via mktemp
bash scripts/test-install-docker.sh   # same tests, fully isolated in a container
```
