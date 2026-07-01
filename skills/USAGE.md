# skills/ — usage guide

This workspace holds procedural instruction sets ("how to perform a procedure") that
Claude Code loads into an agent's context for a specific task. Consumers are Claude Code
sessions themselves — invoked via the `/skill-name` slash command or triggered by matching
phrases in a user request — either in *this* monorepo (e.g. `atomic-commits` on this repo's
own diff) or in *any other project* Claude Code is working in (e.g. `create-adr` writing to
that project's `docs/adrs/`). See [`README.md`](README.md) for directory structure, the
SKILL.md frontmatter contract, and naming conventions — this file is about how to actually
invoke and use each skill, not how the directory is laid out.

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

| Skill | Description |
|-------|-------------|
| [atomic-commits](atomic-commits/SKILL.md) | Split a dirty working tree into atomic commits and write messages in the repo's detected commit dialect. |
| [create-adr](create-adr/SKILL.md) | Generate a numbered Architecture Decision Record in `docs/adrs/` and update its index. |
| [create-changelog](create-changelog/SKILL.md) | Append a dated, model-versioned entry to a skill's or agent prompt's `CHANGELOG.md`. |
| [fix-validation](fix-validation/SKILL.md) | Run `scripts/validate.sh`, auto-fix mechanical issues, and report what still needs manual authorship. |
| [readme-maintenance](readme-maintenance/SKILL.md) | Audit and fix every README in the repo against a shared quality rubric, one subagent per workspace. |
| [yaml-frontmatter](yaml-frontmatter/SKILL.md) | Validate, add, or update YAML frontmatter blocks on `docs/` files against a spec. |

## atomic-commits

### How to use it

Invoke it any time you want changes recorded in git — explicit slash-command use isn't
required; phrases like "commit this", "write a commit message", "stage and commit", or "split
these into commits" trigger it too. It surveys `git status`/`git diff`, decides whether the
tree holds more than one logical change (the "does the subject need the word 'and'?" test),
detects the repo's commit dialect (Conventional Commits, Changesets, kernel-style trailers, or
prose) via `scripts/detect_dialect.sh`, then writes and commits messages that explain *why*.

```
User: commit this
(working tree has: an auth bug fix, an unrelated parser refactor, and a lodash bump)

Skill:
1. Diffs the tree, finds three unrelated concerns.
2. Proposes splitting into three commits; user confirms.
3. Detects .commitlintrc.json + @commitlint/* → Conventional Commits dialect.
4. Commits each with `git commit -F -`:
   - fix(auth): reject expired tokens on refresh
   - refactor(parser): extract token validation into TokenGuard
   - build: bump lodash to 4.17.21
```

## create-adr

### How to use it

Run `/create-adr <title> [context-and-rationale]` when a project needs an architectural
decision recorded. It reads the target project's `docs/specs/adr-template-spec.md` and
`docs/specs/yaml-frontmatter-spec.md` for formatting rules, computes the next `ADR-XXXX`
number from existing files in `docs/adrs/`, asks one clarifying question if context is too
sparse, then writes the ADR and updates `docs/adrs/INDEX.md`.

```
/create-adr adopt React Server Components when building full-stack application features

→ writes docs/adrs/ADR-0001-react-server-components.md
  ---
  status: proposed
  decision_date: 2026-06-30
  description: Adopt React Server Components for server-side rendering and data fetching
  ---
  ## Context
  Building full-stack features; needed to reduce client-side JavaScript...
  ## Decision
  We will adopt React Server Components for all new server-side rendering routes.
  ## Consequences
  Positive: reduced JS bundle, simpler async code
  Negative: requires React 18.3+, steeper learning curve
  Neutral: existing client components coexist

→ adds a row to docs/adrs/INDEX.md
→ reminds you to flip status to `accepted` once formally decided
```

## create-changelog

### How to use it

Run `/create-changelog <asset-name-or-path> [what-changed-and-why] [model-version]` right
after editing a skill or agent prompt, or say "log this change to the changelog". It resolves
whether the target is a skill (`skills/<name>/`), a packed skill (`packs/<pack-name>/skills/<name>/`),
or an agent prompt (`prompts/agents/<name>/`), confirms it's a real asset (`SKILL.md` or
`system.md` present), asks one focused question if you didn't describe the change, and appends
a newest-first bullet to `CHANGELOG.md` (creating it with the standard header if it doesn't
exist yet).

```
/create-changelog atomic-commits Improved detection of Conventional Commits vs. \
  kernel-style trailers by parsing multiple recent commits instead of the latest one \
  Sonnet 5

→ skills/atomic-commits/CHANGELOG.md now contains:
  # Changelog

  Format: `YYYY-MM-DD · {model-version} · {what changed and why}`

  - 2026-06-30 · Sonnet 5 · Improved detection of Conventional Commits vs. kernel-style
    trailers by parsing multiple recent commits instead of the latest one
```

## fix-validation

### How to use it

Run `/fix-validation [path-filter]` (e.g. `/fix-validation skills/atomic-commits`) to clean up
structural issues across the repo, or say "fix validation issues" / "run validate.sh and fix
what it finds". It runs `bash scripts/validate.sh`, buckets each failure into auto-fixable
(syntax slips, missing boilerplate) versus needs-authorship (missing SKILL.md content, eval
cases), applies the auto-fixes directly, re-runs `validate.sh` to confirm nothing regressed,
then reports two sections: what it fixed and what still needs a human.

```
/fix-validation skills/my-new-skill

Before: skills/my-new-skill/manifest.json has a trailing-comma syntax error;
        no SKILL.md exists yet.

Fixed:
  - manifest.json syntax corrected: {"name": "my-new-skill", "tags": ["foo"]}

Needs manual authorship:
  - write skills/my-new-skill/SKILL.md
  - author eval cases in evals/skills/my-new-skill/
```

## readme-maintenance

### How to use it

Run `/readme-maintenance [workspace-filter]` (e.g. `/readme-maintenance skills`, or omit to
cover every workspace) to audit READMEs, or say "audit the READMEs" / "check the READMEs are
up to date". It reads the root README for cross-cutting conventions, then dispatches one
subagent reviewer per workspace with an 8-point quality rubric; each reviewer verifies every
claim against the real repo tree (via `ls`/`find`/`grep`) before making surgical edits, and
flags anything out-of-scope (bugs in non-README files) separately. `validate.sh` runs at the
end to confirm no structural regression; nothing is auto-committed.

```
/readme-maintenance

(a new workflows/ directory was added but the root README's workspace table wasn't updated)

→ reviewer for the root README finds the gap, confirms `workflows/` exists via `git ls-tree`,
  adds the missing table row, reports "Workspace table: added missing workflows/ entry."
→ other reviewers check their own workspace READMEs for stale paths/commands
→ final summary: one report per workspace + a separate list of out-of-scope issues found
→ changes sit in the working tree for you to `git diff` and commit yourself
```

## yaml-frontmatter

### How to use it

Four modes, all sourced from `docs/specs/yaml-frontmatter-spec.md` in the target project:

```
/yaml-frontmatter                       # validate the current file in conversation
/yaml-frontmatter add <filepath>        # add missing frontmatter
/yaml-frontmatter update <filepath>     # fix non-conforming frontmatter
/yaml-frontmatter check-all             # audit every .md file under docs/
```

Also triggers on "validate the frontmatter", "add frontmatter to", "fix the frontmatter on",
or "audit all docs frontmatter". For `add`/`update` it always proposes the frontmatter block
and waits for confirmation before writing; the body is never touched.

```
/yaml-frontmatter add docs/adr/adr-042.md

(file starts with "# Decision: Migrate to Service Mesh", no frontmatter)

→ proposes:
  ---
  date: 2026-06-30
  description: Decision to migrate the platform to a service mesh for traffic management
  status: draft
  tags: [architecture, service-mesh, infrastructure]
  scope: adr
  ---
→ you confirm → block is prepended, body unchanged
```
