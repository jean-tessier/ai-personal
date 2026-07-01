---
name: survey-search
description: Structural/AST search via ast-grep (sg --json) — find every call
  site or match an AST-shaped pattern across the codebase. Use for
  structural/AST search; NOT for a plain text/string search in a handful of
  files (Surveyor T0 rg/fd covers that).
allowed-tools: shell        # GitHub/open-standard field; may be ignored by VS Code (§18)
---

# ast-grep search (Tier 1, read-only)
Precondition: structural / AST (Surveyor's T1 row). A plain string search stays at T0 (rg/fd).

1. Search: `sg --json --pattern '<pattern>' --lang <lang> <path>` — `--json` only;
   never `--rewrite` or `--update-all`. This skill never mutates.
2. Don't dump the whole match set into context. If it's large, escalate to
   `scratch-script` (T2) to filter/aggregate first.
3. Cross-check any count derived from the matches a second, independent way
   (e.g. `rg -c` on the same pattern) before reporting it.
