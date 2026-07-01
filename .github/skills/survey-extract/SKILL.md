---
name: survey-extract
description: Count/stats extraction via jq (JSON) and tokei (LOC/code stats).
  Use for count/stats questions across files; NOT for locating matches
  (survey-search or Surveyor T0 covers that).
allowed-tools: shell        # GitHub/open-standard field; may be ignored by VS Code (§18)
---

# jq / tokei extract (Tier 1, read-only)
Precondition: count / stats (Surveyor's other T1 row). A single ad-hoc read stays at T0.

1. Extract: `tokei <path> --output json | jq '<filter>'` for LOC/code stats, or
   `jq '<filter>' <file>.json` directly on existing JSON.
2. Compute the same count a second, independent way (e.g. `rg -c` or `wc -l`)
   before reporting it — cross-check-two-ways is not optional here.
3. Report only the extracted number(s)/summary, not the raw tokei/jq dump.
