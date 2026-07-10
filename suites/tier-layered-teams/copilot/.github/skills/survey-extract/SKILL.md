---
name: survey-extract
description: Extract structured facts and code statistics (read-only) — pull fields from JSON with jq, count lines/files/languages with tokei, tally results. Use for any "how many / how big / list the values of" question over JSON output or a codebase. Pairs with survey-search for count cross-checks.
allowed-tools: shell
---

# Extract & quantify (research team (research-worker) · Tier 1)
Precondition (self-gate): a count / stats / extraction trigger is met, else Tier 0.

- JSON extraction:  `... --json | jq -r '.[].file' | sort -u`
- Code stats:       `tokei --output json | jq '.Total.code'`
- Every count/aggregate is computed two independent ways and compared; surface any
  mismatch. For a hard gate, pipe both numbers through `scripts/crosscheck.sh`.

Return the extracted value(s) only — never the intermediate JSON blob. If it would be
large, hide it behind a scratch script (Tier 2) or cap it with `scripts/size-cap.sh`.
