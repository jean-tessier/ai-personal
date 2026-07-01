# evals/ — Usage Guide

This is the eval workspace of the `ai-personal` monorepo. It exists to catch behavioural
drift: when a system prompt (`prompts/agents/`), a task prompt (`prompts/tasks/`), or a
skill (`skills/`) changes, the matching `cases.yaml` here is what tells you whether it
still behaves the way it used to. For the directory layout and the `cases.yaml` format
itself, see [`evals/README.md`](README.md) — this file is about how the pieces get used,
not what they structurally contain.

Two consumers touch this workspace today:

- **`scripts/validate.sh`** — real, runs today. Its "evals alignment" check walks
  `prompts/agents/` and `skills/` and warns (doesn't fail the build) when an agent or
  skill has no matching `evals/{agents,skills}/{name}/` subdirectory. Right now it warns
  on all six skills, because no `cases.yaml` has been written yet:
  ```
  $ bash scripts/validate.sh
  ── evals alignment ──
    warn  skills/atomic-commits has no eval suite at evals/skills/atomic-commits/
    warn  skills/create-adr has no eval suite at evals/skills/create-adr/
    warn  skills/create-changelog has no eval suite at evals/skills/create-changelog/
    warn  skills/fix-validation has no eval suite at evals/skills/fix-validation/
    warn  skills/readme-maintenance has no eval suite at evals/skills/readme-maintenance/
    warn  skills/yaml-frontmatter has no eval suite at evals/skills/yaml-frontmatter/
  ```
  Note it only checks `evals/agents/` and `evals/skills/` — there is no equivalent
  alignment check for `evals/tasks/` yet.
- **An eval/test runner that executes `cases.yaml`** — documented by convention in
  `evals/README.md`, but not present anywhere in this repo. No invocation syntax for it
  exists yet; someone still has to build or wire one in.

## How the pieces relate

```
prompts/agents/{name}/system.md ─┐
prompts/tasks/{name}.md ─────────┼──▶ evals/{agents,tasks,skills}/{name}/cases.yaml
skills/{name}/SKILL.md ──────────┘              │
                                                 ├──▶ scripts/validate.sh
                                                 │      "evals alignment" — warns if the
                                                 │      cases.yaml subdir is missing;
                                                 │      does not read or run cases.yaml
                                                 │
                                                 └──▶ (not yet built) eval runner
                                                        tags gate what it runs:
                                                        smoke      → pre-commit
                                                        regression → full suite
                                                        edge       → full suite
                                                        slow       → full suite only
```

## Assets in this workspace

| Asset | Description |
|-------|-------------|
| [`evals/agents/`](agents/README.md) | Eval suites for agent system prompts (`prompts/agents/{name}`) — empty, and `prompts/agents/` itself has no agents defined yet either |
| [`evals/skills/`](skills/README.md) | Eval suites for skills (`skills/{name}`) — empty, even though 6 skills already exist and `scripts/validate.sh` is actively warning about the gap |
| [`evals/tasks/`](tasks/README.md) | Eval suites for task prompts (`prompts/tasks/{name}`) — empty, and `prompts/tasks/` itself has no tasks defined yet either |

Every one of these is currently a placeholder: each subdirectory contains only a
`README.md` pointing back at `evals/README.md` for the format. There are no `cases.yaml`
files anywhere in this workspace yet. The sections below document the intended workflow
for populating each one — not real, run invocations, since none exist in this repo yet.

### evals/agents/

**Status:** empty. There's nothing to write suites for yet either — `prompts/agents/`
has no agent subdirectories, only its own `README.md`.

**How to use it (once an agent exists):** after adding `prompts/agents/{name}/system.md`,
create `evals/agents/{name}/cases.yaml` in the format from `evals/README.md`, tagging
each case `smoke`/`regression`/`edge`/`slow`. Illustrative walkthrough:

```
Before: prompts/agents/my-classifier/system.md is written and in use.
        No regression protection exists for it.

After:  evals/agents/my-classifier/cases.yaml is added with:
        - a `smoke` case: input "classify this review" →
          expected.contains: ["positive", "negative", "neutral"], format: json
        - a `regression` case guarding a past bug: input "" (empty string) →
          expected.behaviour: graceful_error
        - a `slow` case running 100 sample reviews, tag: slow

        If a future change to system.md makes the classifier stop returning JSON,
        the `smoke` case is the one that's expected to catch it before commit.
```

### evals/skills/

**Status:** empty, but the most actionable gap of the three — `skills/` already has six
real skills (`atomic-commits`, `create-adr`, `create-changelog`, `fix-validation`,
`readme-maintenance`, `yaml-frontmatter`) and `scripts/validate.sh` is warning on all six
right now (see the transcript above).

**How to use it:** create `evals/skills/{name}/cases.yaml` matching an existing
`skills/{name}` directory name exactly — no slug translation. Illustrative walkthrough:

```
Before: skills/fix-validation/ exists and skills/fix-validation/SKILL.md is in use.
        `bash scripts/validate.sh` warns: "skills/fix-validation has no eval suite
        at evals/skills/fix-validation/".

After:  evals/skills/fix-validation/cases.yaml is added with a case like:
          input:  { user: "broken validation rule: ..." }
          expected: { contains: ["corrected rule"] }
          tags: [smoke]

        `bash scripts/validate.sh` now reports `evals/skills/fix-validation/ exists`
        instead of the warning, and a future CI step would run the case before the
        skill ships a change.
```

### evals/tasks/

**Status:** empty. Same situation as `evals/agents/` — `prompts/tasks/` has no task
prompts yet, only its own `README.md`, and there's no `scripts/validate.sh` alignment
check for tasks yet either.

**How to use it (once a task exists):** after adding `prompts/tasks/{name}.md`, create
`evals/tasks/{name}/cases.yaml` (directory name = filename without `.md`). Illustrative
walkthrough:

```
Before: prompts/tasks/summarize-logs.md exists with no eval suite.

After:  evals/tasks/summarize-logs/cases.yaml is added with a case like:
          input:    a sample 100-line error log
          expected: format: json; output must match a schema and contain all
                     root-cause categories present in the sample log

        This becomes the check that catches summarize-logs.md regressions the
        next time the prompt is edited.
```
