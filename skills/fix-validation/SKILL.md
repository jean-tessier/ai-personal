---
name: fix-validation
description: Run scripts/validate.sh, auto-fix mechanical structural issues, and report what needs manual authorship
---

# Fix Validation

## Purpose

Run the repo's structural linter (`scripts/validate.sh`) and resolve what it finds. Some findings are purely mechanical (a missing `CHANGELOG.md` header, a JSON syntax slip) and can be fixed directly. Others require real authored content (a skill's procedure, an agent's persona, eval cases) that must not be fabricated — those are reported as a checklist instead.

## When to invoke

When the user wants to clean up structural issues across the repo, or check it's in a valid state. Triggers on `/fix-validation`, or phrases like "fix validation issues", "clean up the repo structure", "run validate.sh and fix what it finds".

Usage:

```
/fix-validation [path-filter]
```

**Arguments:**

- `[path-filter]` — Optional. Restrict fixes/reporting to one asset path (e.g. `skills/atomic-commits`) instead of the whole repo.

---

## Steps

### 1. Run the validator

Run `bash scripts/validate.sh` from the repo root and capture the full output. If `[path-filter]` was given, only consider findings whose path starts with it — still run the whole script, since it doesn't take a path argument.

### 2. Classify each finding

Every `FAIL` or `warn` line falls into one of two buckets:

**Auto-fixable — apply directly, no confirmation needed:**

- `warn  .../CHANGELOG.md — no version log yet` → create `CHANGELOG.md` in that directory with the header only, per the convention in the repo root `README.md`. Do not invent an entry — an empty log is a legitimate initial state, a fabricated entry is not.
  ```markdown
  # Changelog

  Format: `YYYY-MM-DD · {model-version} · {what changed and why}`
  ```
- `FAIL  .../manifest.json — invalid JSON`, `FAIL  .../.claude-plugin/plugin.json — invalid JSON`, or `FAIL  tools/functions/*.json — invalid JSON` → open the file and check whether the error is a pure syntax slip (trailing comma, unquoted key, single quotes, stray comment). If so, correct only the syntax — never change a key or value. Validate with `python3 -m json.tool <file>` before and after to confirm it now parses and that a diff shows only syntax characters changed. If the error isn't a confident syntax-only fix (e.g. the file is truncated, or fixing it requires guessing intended structure), move it to the manual-authorship list instead of guessing.

**Needs manual authorship — report only, do not create placeholder content:**

- `FAIL  .../SKILL.md — required file missing` — needs a real procedure written by the user (or via a dedicated skill-creation flow). Applies to both `skills/{name}/` and `packs/{pack-name}/skills/{name}/`.
- `FAIL  .../system.md — required file missing` — needs a real agent persona.
- `FAIL  packs/{name}/.claude-plugin/plugin.json — required file missing` — needs a real plugin identity (`name`, `description`, `version`) authored by the user.
- `FAIL  packs/{name}/README.md — required file missing` — needs a real description of what the pack bundles and why its skills ship together.
- `FAIL  packs/{name}/skills/ — no skills found in pack` — needs at least one real skill authored under `packs/{name}/skills/{skill-name}/`; a pack with no skills isn't a valid plugin.
- `FAIL  workflows/{name}/README.md — required file missing` — needs a real description of the orchestration.
- `FAIL  workflows/{name}/ — no grouped prompt files found` — needs real component prompt files.
- `warn  skills/{name} has no eval suite at evals/skills/{name}/` / same for agents — needs authored eval cases. Do not create an empty directory as a "fix": git does not track empty directories, so it would silently disappear on the next commit and give a false sense of completion.

### 3. Apply the auto-fixable fixes

For each auto-fixable finding, make the change. For JSON repairs, show the before/after diff in your response even though no confirmation is required — the user should be able to see exactly what syntax changed.

### 4. Re-run the validator

Run `bash scripts/validate.sh` again and confirm:
- Every finding you claimed to fix no longer appears (or, for JSON, now shows `ok` instead of `FAIL`).
- No new findings were introduced.

### 5. Report

Two sections:

- **Fixed** — one line per change, with the file path.
- **Needs manual authorship** — one line per remaining finding, grouped by asset, each with a concrete next step (e.g. "write `skills/foo/SKILL.md`", "author eval cases in `evals/skills/foo/`", "run `/create-changelog` once a real change is made to log it").

If nothing needed fixing and nothing remains outstanding, say so plainly instead of printing empty sections.
