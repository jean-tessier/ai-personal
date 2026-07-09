---
name: astgrep-rewrite
description: Structural rewrite via ast-grep — rename an API across files, transform AST-shaped patterns. Use for multi-file / structural edits. NOT for a single known string in one file (Transformer T0 direct edit covers that).
allowed-tools: shell
---

# ast-grep rewrite (Transformer · Tier 1)
Precondition (self-gate): ≥3 repetitions OR >5 files OR a determinism trigger. Else
→ Transformer T0 direct edit.

1. Preview (writes the diff the PreToolUse hook requires):
   `scripts/preview-rewrite.sh 'fetchUser($$$A)' 'getUser($$$A)' ts`
   → writes `./scratch/handoff/pending.diff` and prints it. Show it to the user.
2. Apply only after the diff is shown:
   `ast-grep -p 'fetchUser($$$A)' -r 'getUser($$$A)' --lang ts --update-all`
3. Hand to `verifier`; report success only after `make check` passes.

Gotcha: patterns are AST-isomorphic, not regex. Binary is `ast-grep` (not `sg` — see runbook).
