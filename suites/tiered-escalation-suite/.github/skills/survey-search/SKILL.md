---
name: survey-search
description: Structural / AST-shaped code search via ast-grep (read-only) — find all call sites, locate a pattern across files, count matches precisely. Use whenever a plain-text rg search is not enough — need AST shape, must exclude comments/strings, or matches span many files. NOT for a single known string in one file (use Tier 0 rg for that).
allowed-tools: shell
---

# Structural search (Surveyor · Tier 1)
Precondition (self-gate): a structural / volume / determinism trigger is met. If it
is just a known string in 1–few files, return to Tier 0 (`rg`) — do not load this.

1. Search, always `--json` for machine use:
   `ast-grep -p 'fetchUser($$$A)' --lang ts --json | jq 'length'`
2. Cross-check any count a second way and compare (the read-side discipline):
   `ast-grep ... --json | jq length`  vs  `rg -c 'fetchUser\(' | awk -F: '{s+=$2} END{print s}'`
   Surface any discrepancy rather than silently picking one number.
3. Return only the finding (count / file list), never the raw match dump. If the dump
   would be large, run under a subagent or cap it with `scripts/size-cap.sh`.

Gotcha: ast-grep patterns are AST-isomorphic, not regex — `$M` is one node, `$$$A` a
list of nodes. The binary is `ast-grep`; `sg` may collide with util-linux (see runbook).
