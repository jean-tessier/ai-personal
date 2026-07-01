# ai-personal

Personal monorepo of reusable Claude Code assets — prompts, skills, workflows, tools, and
eval cases — kept in one place with consistent structure and conventions.

## Directory map

| Path | Contents |
|------|----------|
| `prompts/` | Agent system prompts, one-shot task prompts, reusable shared fragments |
| `skills/` | Procedural instruction sets injected into agent context |
| `workflows/` | Grouped, inter-referential prompt/skill collections — e.g. multi-agent orchestration systems. See [`workflows/README.md`](workflows/README.md) |
| `packs/` | Distributable skill bundles packaged as installable Claude Code plugins. See [`packs/README.md`](packs/README.md) |
| `tools/` | MCP server manifests and function/tool schemas |
| `evals/` | Eval cases — mirrors the `prompts/` and `skills/` tree exactly |
| `scripts/` | Catalog generation and structural validation |

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
| `-h`, `--help` | show usage |

Harness/scope keys come from `scripts/harnesses.json`:

| Harness | Scopes |
|---------|--------|
| `claude-code` | `project` → `.claude`, `user` → `~/.claude` |
| `copilot` | `project` → `.github` (no `user` scope) |

`copilot` has no `user` scope — don't pass `--scope user` with `--harness copilot`.

Omitting `--assets` in a real terminal launches a picker per category (fzf → gum → numbered
prompt, whichever is available) instead of installing everything. Piped runs (`curl | bash`)
have no TTY on stdin, so they skip the picker and install every category.

## Key conventions

- Skills and agent prompts live in their own subdirectory; task prompts are flat files
  under `prompts/tasks/`, promoted to a subdirectory only when they need `examples/`.
- Skills and agent prompts carry a `CHANGELOG.md` to track drift across model versions.
- `_shared/` directories hold composable fragments not directly invocable as standalone assets.
- Prompts/skills that only function as a group (e.g. a multi-agent orchestration system) live under `workflows/{name}/`, not as separate flat assets.
- Skills meant to be installed elsewhere as a single Claude Code plugin live under `packs/{pack-name}/skills/{name}/`, not `skills/{name}/` — a pack's skills are still independently invocable (unlike `workflows/`), they just ship bundled under one plugin manifest.
- Run `bash scripts/catalog.sh > catalog.json` to regenerate the asset index.
- Run `bash scripts/validate.sh` before committing.

## Skills vs. prompts

| Type | Location | Purpose |
|------|----------|---------|
| Agent prompt | `prompts/agents/{name}/system.md` | Who the agent is; standing context, persona, constraints |
| Task prompt | `prompts/tasks/{name}.md` | One-shot instructions for a specific task |
| Shared fragment | `prompts/_shared/` | Composable blocks (persona, format, reasoning mode) |
| Skill | `skills/{name}/SKILL.md` | Procedural how-to: teaches an agent a specific procedure |
| Skill pack | `packs/{pack-name}/skills/{name}/SKILL.md` | Same as a skill, but bundled with others into one installable Claude Code plugin |

## Versioning

Prompt and skill changes are logged in each asset's `CHANGELOG.md`.
Format: `YYYY-MM-DD · {model-version} · {what changed and why}`

## Running scripts

```bash
bash scripts/validate.sh          # structural lint; exits 1 on failures
bash scripts/catalog.sh           # emits catalog JSON to stdout
bash scripts/catalog.sh > catalog.json
bash scripts/test-install.sh          # install.sh behavioral tests, sandboxed via mktemp
bash scripts/test-install-docker.sh   # same tests, fully isolated in a container
```
