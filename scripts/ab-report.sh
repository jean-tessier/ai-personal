#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ab-report.sh — A/B-and-kill-criteria report (design doc §16): sums
# tokens_in + tokens_out + tool_calls per variant across ./scratch/metrics.csv
# and applies the "skill net ≤ 0 vs baseline → delete/merge" kill criterion.
#
# Requires one column beyond the trigger-semantics schema (§12): "variant",
# with values "baseline" / "skill", appended after crosscheck. The committed
# ./scratch/metrics.csv stays header-only on the literal trigger-semantics
# schema (no variant column) since it has no data yet; once/if rows are ever
# logged for a real A/B run, add "variant" as the 11th field so this script
# can group them.
#
# Usage: scripts/ab-report.sh [csv_file]   (default: ./scratch/metrics.csv)
# Exit:  0 always — this is a report, not an enforced gate (no hook wires it)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

main() {
  local file="${1:-./scratch/metrics.csv}"

  [[ -f "$file" ]] || { echo "ok: $file does not exist, nothing to report"; exit 0; }

  local sums
  sums="$(awk -F',' '
    NR > 1 {
      cost = $6 + $7 + $8
      variant = $11
      gsub(/^[ \t]+|[ \t]+$/, "", variant)
      if (variant == "baseline") { baseline += cost }
      else if (variant == "skill") { skill += cost }
    }
    END { print baseline+0, skill+0 }
  ' "$file")"

  local baseline_total skill_total delta
  baseline_total="$(echo "$sums" | cut -d' ' -f1)"
  skill_total="$(echo "$sums" | cut -d' ' -f2)"

  if [[ "$baseline_total" -eq 0 && "$skill_total" -eq 0 ]]; then
    echo "ok: no baseline/skill rows in $file, nothing to A/B"
    exit 0
  fi

  delta=$((baseline_total - skill_total))
  echo "baseline_total=$baseline_total skill_total=$skill_total delta=$delta"
  if [[ "$delta" -le 0 ]]; then
    echo "KILL/MERGE: skill net <= 0 vs baseline (delta=$delta)"
  else
    echo "KEEP: skill net > 0 vs baseline (delta=$delta)"
  fi
}

self_test() {
  local tmp fail
  tmp="$(mktemp -d)"
  fail=0

  bash "$0" "$tmp/does-not-exist.csv" > /dev/null 2>&1 || { echo "FAIL: missing file should exit 0"; fail=1; }

  cat > "$tmp/negative.csv" <<'EOF'
task_id, agent, tier, trigger, tool, tokens_in, tokens_out, tool_calls, make_check, crosscheck, variant
t1,surveyor,T1,volume,survey-search,100,50,5,pass,pass,baseline
t1,surveyor,T1,volume,survey-search,120,60,6,pass,pass,skill
EOF
  bash "$0" "$tmp/negative.csv" 2>&1 | grep -q "KILL/MERGE" || { echo "FAIL: net-negative case should print KILL/MERGE"; fail=1; }

  cat > "$tmp/positive.csv" <<'EOF'
task_id, agent, tier, trigger, tool, tokens_in, tokens_out, tool_calls, make_check, crosscheck, variant
t1,surveyor,T1,volume,survey-search,150,50,10,pass,pass,baseline
t1,surveyor,T1,volume,survey-search,60,30,4,pass,pass,skill
EOF
  bash "$0" "$tmp/positive.csv" 2>&1 | grep -q "^KEEP" || { echo "FAIL: net-positive case should print KEEP"; fail=1; }

  rm -rf "$tmp"
  if [[ $fail -eq 0 ]]; then echo "self-test: PASS"; exit 0; else echo "self-test: FAIL"; exit 1; fi
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; else main "$@"; fi
