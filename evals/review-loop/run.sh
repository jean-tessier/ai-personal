#!/usr/bin/env bash
# review-loop evals. COSTS REAL MONEY: every case x arm is a full headless loop (Opus orchestrator + reviewer + fixers).
#   bash evals/review-loop/run.sh <iteration> [case ...]      # all cases when none given; both arms, in parallel
#   RUNS=3 bash evals/review-loop/run.sh <iteration>          # repeats per case x arm (sequential), in run-<i>/
# Arms: with_skill  = skills/review-loop copied into the fixture repo, prompt as written in prompt.md
#       without_skill = no skill; the prompt is the outline the user would otherwise type, plus the same target
# Each run is a `claude -p` session in a throwaway fixture repo outside this repo (so this repo's CLAUDE.md doesn't
# load), with user settings excluded and a scoped tool allowlist. Results: work/iteration-<N>/<case>/<arm>/.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
IT="${1:?usage: run.sh <iteration> [case ...]}"; shift
if [ $# -gt 0 ]; then CASES=("$@"); else CASES=($(ls "$HERE/cases")); fi
OUT="$HERE/work/iteration-$IT"
BUDGET="${BUDGET:-10}"   # USD per run
RUNS="${RUNS:-1}"
OUTLINE='Run this subagent orchestration loop: an Opus 5.5 subagent performs a code review on a PR returning clear, actionable findings; Haiku 5.5 subagents tackle mechanical findings whilst Sonnet 5.5 subagents tackle those more complex; repeat until the Opus reviewer is SATISFIED.'
TOOLS=(Agent SendMessage ToolSearch Skill Read Edit Write Glob Grep TodoWrite
       "Bash(git:*)" "Bash(node:*)" "Bash(npm:*)" "Bash(ls:*)" "Bash(cat:*)" "Bash(grep:*)"
       "Bash(wc:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(diff:*)")

one() { # case arm [run]
  local c="$1" arm="$2" dir="$OUT/$1/$2${3:+/run-$3}" run body prompt turns
  rm -rf "$dir" && mkdir -p "$dir"
  run="$(mktemp -d "${TMPDIR:-/tmp}/review-loop-eval.XXXXXX")" && echo "$run/repo" > "$dir/run-dir.txt"
  mkdir "$run/repo" && (cd "$run/repo" && bash "$HERE/cases/$c/scaffold.sh" && echo ".claude/" >> .git/info/exclude)
  git -C "$run/repo" rev-parse HEAD > "$dir/scaffold-head.txt"
  body="$(awk 'n>=2{print} /^---$/{n++}' "$HERE/cases/$c/prompt.md" | sed '/./,$!d')"
  turns="$(awk '/^---$/{n++; next} n==1 && /^max_turns:/{print $2; exit}' "$HERE/cases/$c/prompt.md")"
  if [ "$arm" = with_skill ]; then
    mkdir -p "$run/repo/.claude/skills" && cp -R "$REPO/skills/review-loop" "$run/repo/.claude/skills/"
    prompt="$body"
  else
    prompt="$OUTLINE"$'\n\n'"Run it on ${body#/review-loop }"
  fi
  printf '%s\n' "$prompt" > "$dir/prompt.txt"
  local start; start="$(date +%s)"
  (cd "$run/repo" && claude -p "$prompt" --model claude-opus-5-5 --setting-sources project,local \
     --allowedTools "${TOOLS[@]}" --disallowedTools WebFetch WebSearch \
     --output-format stream-json --verbose --max-budget-usd "$BUDGET" ${turns:+--max-turns $turns} \
     > "$dir/transcript.jsonl" 2> "$dir/stderr.txt") || echo "run.sh: $c/$arm exited non-zero" >&2
  echo "$start $(date +%s)" > "$dir/wall.txt"
  node "$HERE/grade.mjs" "$dir" "$run/repo"
}

for c in "${CASES[@]}"; do
  [ -d "$HERE/cases/$c" ] || { echo "run.sh: no case $c" >&2; exit 64; }
  for arm in with_skill without_skill; do
    if [ "$RUNS" = 1 ]; then one "$c" "$arm" &
    else (for i in $(seq 1 "$RUNS"); do one "$c" "$arm" "$i"; done) & fi
  done
done
wait
