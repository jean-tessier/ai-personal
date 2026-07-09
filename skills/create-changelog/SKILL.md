---
name: create-changelog
description: Create or append a dated entry to a skill's CHANGELOG.md
---

# Create Changelog

## Purpose

Create or update the `CHANGELOG.md` for a skill (`skills/{name}/`), per the versioning convention in the repo root `README.md`: `YYYY-MM-DD · {model-version} · {what changed and why}`. This log tracks drift in a skill's behavior across model versions — it is separate from git history and should describe *what changed in the skill's behavior or instructions*, not implementation mechanics.

## When to invoke

When the user has just edited a skill and wants the change logged. Triggers on `/create-changelog`, or phrases like "log this change to the changelog", "add a changelog entry for X", or "update the CHANGELOG for this skill".

Usage:

```
/create-changelog <skill-name-or-path> [what-changed-and-why] [model-version]
```

**Arguments:**

- `<skill-name-or-path>` — A bare skill name (e.g. `atomic-commits`) or an explicit path (`skills/atomic-commits`).
- `[what-changed-and-why]` — Optional free-form description of the change and its motivation. If omitted, ask the user one focused question before drafting.
- `[model-version]` — Optional. Defaults to the model powering the current session if not given.

---

## Steps

### 1. Resolve the target skill directory

- If the argument contains a `/`, treat it as a path relative to the repo root and use it directly.
- Otherwise, check for `skills/<name>/`.
  - If it doesn't exist, tell the user and ask for the correct path.
- Confirm `SKILL.md` exists in the resolved directory — this confirms it's a real skill directory, not an arbitrary folder.

### 2. Check for sufficient context

If `[what-changed-and-why]` is missing or too sparse to produce a meaningful entry (e.g. just "updated it"), ask the user one focused question:

> "What changed in this asset's behavior or instructions, and why?"

Wait for the answer. Do not ask multiple questions at once.

### 3. Determine the model version

- Use `[model-version]` if provided.
- Otherwise, default to the model currently powering this session (human-readable form, e.g. `Sonnet 5`).

### 4. Create or update `CHANGELOG.md`

- If `CHANGELOG.md` does not exist in the resolved directory, create it with this header:
  ```markdown
  # Changelog

  Format: `YYYY-MM-DD · {model-version} · {what changed and why}`
  ```
- Insert the new entry as a bullet directly below the header, newest entry first:
  ```markdown
  - YYYY-MM-DD · {model-version} · {what changed and why}
  ```
- Use today's date in `YYYY-MM-DD` format.
- Do not reorder or reword existing entries.

### 5. Confirm

- Report the exact absolute path of the `CHANGELOG.md` written.
- State whether it was newly created or appended to.
