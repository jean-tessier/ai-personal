---
name: scratch-script
description: Ad-hoc script in ./scratch for aggregation, cross-source joins, or
  a multi-source codemod that no single deterministic tool covers in one call.
  Use when a task needs an intermediate that must not enter context directly
  (aggregate/join for Surveyor, multi-source codemod for Transformer).
allowed-tools: shell        # GitHub/open-standard field; may be ignored by VS Code (§18)
---

# scratch script (Tier 2)
Precondition: aggregation/join across sources, or a codemod spanning multiple
inputs — the one thing no lower tier covers in a single deterministic call.
Shared by both agents — Surveyor (read: aggregate/join → JSON/MD) and
Transformer (write: multi-source codemod → diff). The capability ceiling comes
from the calling agent's `tools:` allowlist, not from this skill's prose.

1. Copy `scratch-script/templates/aggregate.ts` into `./scratch/`, rename it,
   and adapt it for the task at hand.
2. Run it with `node ./scratch/<name>.ts <args>`.
   - Surveyor: write its output as JSON/MD under `./scratch/`.
   - Transformer: write its output as a diff under `./scratch/handoff/*.diff`
     (the PreToolUse hook requires that file to exist before any apply).
3. Surveyor: report only the distilled result, not the raw intermediate.
   Transformer: hand to verifier; report only after `make check` passes.
