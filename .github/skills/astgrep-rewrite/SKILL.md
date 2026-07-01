---
name: astgrep-rewrite
description: Structural rewrite via ast-grep (sg) — rename an API across files,
  transform AST-shaped patterns. Use for multi-file/structural edits; NOT for a
  single known string in one file (Transformer T0 direct edit covers that).
allowed-tools: shell        # GitHub/open-standard field; may be ignored by VS Code (§18)
---

# ast-grep rewrite (Tier 1)
Precondition: ≥3 repetitions OR >5 files OR a determinism trigger. Else → T0.

1. Preview: `sg -p 'fetchUser($$$A)' -r 'getUser($$$A)' --lang ts`  → write diff to
   ./scratch/handoff/rename.diff  (the PreToolUse hook requires this file to exist)
2. Apply: `sg ... --update-all`
3. Hand to verifier; report only after `make check` passes.
