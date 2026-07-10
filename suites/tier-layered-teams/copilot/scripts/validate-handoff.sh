#!/usr/bin/env bash
# Handoff schema HARD gate. Validates a handoff JSON against handoff.schema.json.
# Prefers ajv; falls back to a jq -e structural check when ajv is absent.
# Usage: validate-handoff.sh <path-to-handoff.json>
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
schema="$here/handoff.schema.json"
doc=${1:?handoff json path required}

if command -v ajv >/dev/null 2>&1; then
  ajv validate --spec=draft2020 -s "$schema" -d "$doc"
  exit $?
fi

command -v jq >/dev/null 2>&1 || { echo "validate-handoff: neither ajv nor jq present — gate cannot run." >&2; exit 2; }
jq -e '
  (.task | type == "string" and (. | length > 0))
  and (.tier | type == "number" and . == floor and . >= 0 and . <= 3)
  and (.inputs | type == "object")
  and (.outputs | type == "object")
' "$doc" >/dev/null \
  && { echo "validate-handoff: OK ($doc)"; exit 0; } \
  || { echo "validate-handoff: INVALID ($doc)" >&2; exit 1; }
