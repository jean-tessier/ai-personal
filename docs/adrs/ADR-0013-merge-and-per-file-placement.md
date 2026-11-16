---
date: 2026-11-16
decision_date: 2026-11-16
description: Manifest placements copy per file; merge creates missing files and never touches an existing one unless --force
status: accepted
---

# ADR-0013: Per-File Placement and `merge` Semantics

## Status

Accepted

## Context

ADR-0008 lets a suite's `manifest.json` declare placements with `mode: "copy"` or `mode: "merge"`
but left merge's conflict behavior undecided. Some placements land in the user's own tree
(`./scripts`, `./Makefile`, `.github/copilot-instructions.md`), so the whole-directory
`rm -rf` + `cp -R` that plain skills and suites use would destroy user files. The owner chose
skip-or-`--force` over format-aware merging (owner decision Q2, 2026-11-16).

## Decision

- **Manifest placements are per file.** For `copy` and `merge` alike, `install.sh` handles each file
  on its own and **never removes a directory**. A destination that is a directory or a symlink is
  skipped with a notice, and a missing parent is created with `mkdir -p`.
- **`copy`** creates a missing file, skips an existing one with a per-file notice, and overwrites it
  under `--force`.
- **`merge` is `copy` with one difference: it never touches an existing file by default.** It
  creates missing files; an existing regular file is left as is, and every such path is listed once
  in a single summary line at the end of the run (not one notice per file), so the user can merge by
  hand. Under `--force` an existing file is overwritten per file, exactly like `copy`.
- **Record interaction (ADR-0012).** Only files actually written are recorded. A skipped
  pre-existing file is not, so `--uninstall` never touches it. Merge-created files are recorded with
  their sha256 and can be uninstalled.
- **`--dry-run`** prints create vs skip per file (a skipped merge file reads "merge would leave it
  untouched") and writes nothing, including no record.

## Alternatives considered

- **A `<file>.ai-personal-new` sidecar per conflict**: more files to track and uninstall.
- **Format-aware merge** (JSON deep-merge, `.gitignore` union): roughly 150+ lines and a real risk of
  corrupting user config. Revisit only if skip-with-notice proves too weak in practice.
- **Overwrite by default**: destroys user edits to `Makefile`, `copilot-instructions.md` and the like.

## Consequences

- A re-install of a manifest suite never loses user edits, and the one summary line shows what to
  merge by hand.
- `--force` is the single opt-in to clobber; it replaces files only, never directories, so a user's
  extra file in the same directory survives.
- A merge-managed file that exists before install is never in the record, so it also never
  receives later suite updates unless the user reinstalls with `--force`.
- The summary joins paths with spaces, so a path that contains spaces reads ambiguously there.
