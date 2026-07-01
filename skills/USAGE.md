# skills/ — usage guide

This workspace holds procedural instruction sets ("how to perform a procedure") that
Claude Code loads into an agent's context for a specific task. Consumers are Claude Code
sessions themselves — invoked via the `/skill-name` slash command or triggered by matching
phrases in a user request — either in *this* monorepo (e.g. `atomic-commits` on this repo's
own diff) or in *any other project* Claude Code is working in (e.g. `create-adr` writing to
that project's `docs/adrs/`). See [`README.md`](README.md) for directory structure, the
SKILL.md frontmatter contract, and naming conventions — this file is about how to actually
invoke and use each skill, not how the directory is laid out. For a given skill's trigger
phrases and a worked example, see that skill's own `USAGE.md`, linked in the table below —
this file stays at the workspace level and doesn't duplicate what's one level down.

## How the pieces relate

```
                         ┌────────────────────────────┐
                         │   Claude Code session       │
                         │  (this repo, or any other)  │
                         └──────────────┬──────────────┘
                                         │ user says "commit this",
                                         │ "/create-adr ...", etc.
                                         ▼
                         ┌────────────────────────────┐
                         │        skills/{name}/       │
                         │  SKILL.md  — the procedure   │
                         │  USAGE.md  — how to invoke   │
                         │  CHANGELOG.md — drift log    │
                         │  references/, scripts/ (opt) │
                         └──────────────┬──────────────┘
                                         │ reads/writes files in the
                                         │ *target* project, not skills/
                                         ▼
        ┌───────────────┬───────────────┬────────────────┬──────────────────┐
        ▼               ▼               ▼                ▼                  ▼
  git history      docs/adrs/      any file's       skills/*/          repo tree
  (atomic-commits) docs/adrs/      YAML frontmatter  CHANGELOG.md       (readme-
                    INDEX.md       (yaml-frontmatter) (create-changelog) maintenance,
                                                                          fix-validation)
```

Each skill is self-contained (one `SKILL.md` per directory) but several cooperate: e.g. after
using `atomic-commits` to land a change to a skill's own logic, follow up with
`create-changelog` to log the drift in that skill's `CHANGELOG.md`; `fix-validation` and
`readme-maintenance` both operate across the whole repo tree (not just `skills/`) to keep
structure and docs honest.

## Assets

| Skill | Description | Usage guide |
|-------|-------------|--------------|
| [atomic-commits](atomic-commits/SKILL.md) | Split a dirty working tree into atomic commits and write messages in the repo's detected commit dialect. | [USAGE.md](atomic-commits/USAGE.md) |
| [create-adr](create-adr/SKILL.md) | Generate a numbered Architecture Decision Record in `docs/adrs/` and update its index. | [USAGE.md](create-adr/USAGE.md) |
| [create-changelog](create-changelog/SKILL.md) | Append a dated, model-versioned entry to a skill's or agent prompt's `CHANGELOG.md`. | [USAGE.md](create-changelog/USAGE.md) |
| [fix-validation](fix-validation/SKILL.md) | Run `scripts/validate.sh`, auto-fix mechanical issues, and report what still needs manual authorship. | [USAGE.md](fix-validation/USAGE.md) |
| [readme-maintenance](readme-maintenance/SKILL.md) | Audit and fix every README in the repo against a shared quality rubric, one subagent per workspace. | [USAGE.md](readme-maintenance/USAGE.md) |
| [yaml-frontmatter](yaml-frontmatter/SKILL.md) | Validate, add, or update YAML frontmatter blocks on `docs/` files against a spec. | [USAGE.md](yaml-frontmatter/USAGE.md) |
