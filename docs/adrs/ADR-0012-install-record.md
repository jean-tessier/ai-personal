---
date: 2026-11-15
decision_date: 2026-11-15
description: install.sh records every placed file and its sha256 in <scope root>/.ai-personal-install.json, so uninstall can be safe
status: accepted
---

# ADR-0012: Install Record — `.ai-personal-install.json` per Scope Root

## Status

Accepted

## Context

`install.sh` copies assets into a harness's scope root and keeps no memory of it. Nothing can later
say which files an install placed, so an uninstall would have to guess, and could delete a file the
user edited or one that was never ours. Deferred item #6 asked for an installed-assets record for
that reason. The owner chose a record plus `--uninstall` and rejected `--update` (owner
decision Q4, 2026-11-15).

## Decision

On every real install, `install.sh` writes or merges `<scope root>/.ai-personal-install.json`, for
example `.claude/.ai-personal-install.json`, `~/.claude/.ai-personal-install.json` or
`.github/.ai-personal-install.json`.

```json
{
  "version": 1,
  "harness": "claude-code",
  "scope": "project",
  "source": { "repo": "jean-tessier/ai-personal", "ref": "main" },
  "assets": {
    "skills/atomic-commits": {
      "installedAt": "2026-11-15T18:00:00Z",
      "ref": "main",
      "files": { ".claude/skills/atomic-commits/SKILL.md": "sha256:9f2c..." }
    }
  }
}
```

- **One record per scope root.** The roots of `claude-code` and `copilot` differ, so they never share one.
- **File granularity, root-anchored paths**, in the same convention as a row's `dest` (relative to
  the project root, or `~/`-anchored). That covers whole-directory placements and Copilot-translated
  suites alike.
- **Hashes are taken after any transform**, so they describe what is on disk. A later uninstall can
  tell an untouched file from an edited one.
- **Every write path calls `record_write asset dest`**: plain copies, Copilot-translated copies and
  dependency copies all go through `apply_selection()`. `record_write` flushes at once, right after
  the placement, so a failure part-way through an install never leaves placed files unrecorded.
  `_json record` expands directories, hashes the files with python `hashlib` (python3 is already
  required, so there is no `shasum` vs `sha256sum` split) and merges them in. Per asset, the entries
  under the placed destination are replaced (keys the new version no longer ships are dropped) and
  `installedAt` is refreshed; other assets and paths are kept. The record is written to a temp file
  and renamed into place.
- **Only what was written is recorded.** A destination skipped because it exists is not logged, so
  a user's own skill with the same name is never claimed. `--dry-run` writes no record.
- **`source.ref` is the `--ref` value** (default `main`), and `null` under `--local`. It describes
  the *last* install; each asset entry also keeps the `ref` it came from, so mixed-ref installs stay
  traceable.
- **`version` is the only forward-compatibility hook.** The installer validates an existing record
  before any file is copied, and exits 1 with a clean message, leaving the record untouched, when it
  is corrupt, has an unknown version or a malformed shape, or belongs to a different harness or scope
  (`--scope project` run from `$HOME` resolves to the same file as `--scope user`).
- **Symlinks inside `skills/` and `suites/` are rejected by `scripts/validate.sh`**, because a
  copied symlink would be recorded by its target or dangle.
- This repo's own dogfood install writes `.claude/.ai-personal-install.json`; it is gitignored.

Alternatives considered:

- **A central manifest in the repo** — says what *could* be installed, not what *was*, and can't
  hold per-machine hashes.
- **Asset-level records (no per-file list)** — can't uninstall merge-created files or detect edits.
- **Hash with `shasum`/`sha256sum`** — needs per-platform detection; `hashlib` is already available.

## Consequences

### Positive

- `--uninstall` (next slice) can remove exactly what was installed, and keep what the user changed.
- Re-installing merges instead of clobbering, so partial installs accumulate in one record.

### Negative

- A new dotfile appears in every scope root, and ships on every real install.
- A file edited or deleted by hand after install makes the record stale until uninstall or re-install.
- Installs made before this record existed are not covered.

### Neutral

- `--update` is not planned; the record would support it, but the owner declined it.
