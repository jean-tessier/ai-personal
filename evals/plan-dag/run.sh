#!/usr/bin/env bash
# plan-dag eval driver. Wraps `claude plugin eval`; see evals/README.md for what each stage costs.
#   bash evals/plan-dag/run.sh <smoke|pilot|behaviour|trigger> [--arm B|C] [--part NAME] [--case GLOB] [--runs N] [--max-cost-usd USD] [--dry-run]
#   bash evals/plan-dag/run.sh arm B|C
# Exit: 0 ok | 64 usage | 3 precondition failed | else the first non-zero runner exit (2 = cost ceiling hit).
set -euo pipefail

usage() { sed -n '2,4p' "${BASH_SOURCE[0]}" >&2; exit 64; }
die() { echo "run.sh: $*" >&2; exit 3; }

# ---- args -------------------------------------------------------------------
STAGE="${1:-}"; [ $# -gt 0 ] && shift
ARM_ONLY="" PART_ONLY="" CASE_OVERRIDE="" RUNS_OVERRIDE="" CAP_OVERRIDE="" DRY=0 ARM_ARG=""
case "$STAGE" in
  smoke|pilot|behaviour|trigger) ;;
  arm) ARM_ARG="${1:-}"; [ $# -gt 0 ] && shift; case "$ARM_ARG" in B|C) ;; *) usage ;; esac ;;
  *) usage ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --arm) [ $# -ge 2 ] || usage; ARM_ONLY="$2"; case "$ARM_ONLY" in B|C) ;; *) usage ;; esac; shift 2 ;;
    --part) [ $# -ge 2 ] || usage; PART_ONLY="$2"; shift 2 ;;
    --case) [ $# -ge 2 ] || usage; CASE_OVERRIDE="$2"; shift 2 ;;
    --runs) [ $# -ge 2 ] || usage; RUNS_OVERRIDE="$2"; case "$RUNS_OVERRIDE" in ''|*[!0-9]*) usage ;; esac; shift 2 ;;
    --max-cost-usd) [ $# -ge 2 ] || usage; CAP_OVERRIDE="$2"; case "$CAP_OVERRIDE" in ''|*[!0-9.]*) usage ;; esac; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) usage ;;
  esac
done

# ---- fixed values -----------------------------------------------------------
SUBJECT=claude-opus-5-5 HARNESS_SUBJECT=claude-haiku-5-5 JUDGE=claude-opus-5-5
export CLAUDE_CODE_EFFORT_LEVEL=high
# Agent is disallowed to bound cost. If smoke's h-no-agent-tool shows Task in the init tool list, add Task here.
DISALLOW=(Agent WebFetch WebSearch)

# ---- preconditions (in order) -------------------------------------------------
for t in claude git node; do command -v "$t" >/dev/null || die "$t not on PATH"; done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
REL="${HERE#"$REPO"/}"
cd "$REPO"

[ -z "$(git status --porcelain -- skills/plan-dag)" ] || die "skills/plan-dag has uncommitted changes; commit or revert them first"
[ -z "$(git status --porcelain --untracked-files=no -- "$REL/arms")" ] || die "tracked files in $REL/arms are modified"

want_arm() { # does this invocation touch arm $1?
  if [ "$STAGE" = arm ]; then [ "$ARM_ARG" = "$1" ]; else [ -z "$ARM_ONLY" ] || [ "$ARM_ONLY" = "$1" ]; fi
}
CDESC="$HERE/arms/C.description.txt"
if want_arm C; then
  node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8");
const m = /^([^\n]*)\n$/.exec(s);
const l = m && m[1];
if (!l || l.length < 1 || l.length > 1536 || !/^[A-Za-z0-9]/.test(l) || l.includes(": ") || l.includes(" #") || l.includes("\t") || l.endsWith(":")) process.exit(1);
' "$CDESC" 2>/dev/null || die "arms/C.description.txt is not a single valid YAML-plain line"
fi

mkdir -p "$HERE/work"
mkdir "$HERE/work/.lock" 2>/dev/null || die "another run.sh holds $REL/work/.lock (remove it if no run is active)"
trap 'rmdir "$HERE/work/.lock" 2>/dev/null || true' EXIT

# ---- arm build ----------------------------------------------------------------
ARM_DIR="$HERE/work/arm/plan-dag"
ARM_CHARS_B="" ARM_CHARS_C=""
desc_chars() { node -e 'console.log(require("fs").readFileSync(process.argv[1], "utf8").split("\n")[2].slice("description: ".length).length)' "$1"; }

build_arm() { # B|C
  local arm="$1" ref="skills/plan-dag/SKILL.md"
  rm -rf "$ARM_DIR" && mkdir -p "$ARM_DIR"
  git archive HEAD:skills/plan-dag | tar -x -C "$ARM_DIR"
  if [ "$arm" = B ]; then
    cmp -s "$ARM_DIR/SKILL.md" <(git show "HEAD:$ref") || die "arm B SKILL.md differs from HEAD:$ref"
  else
    local line; line="$(cat "$CDESC")"
    DESC="$line" awk 'NR==3{ if ($0 !~ /^description: /) exit 3; print "description: " ENVIRON["DESC"]; next } {print}' \
      "$ARM_DIR/SKILL.md" > "$ARM_DIR/SKILL.md.new" || die "SKILL.md line 3 does not start with 'description: '"
    mv "$ARM_DIR/SKILL.md.new" "$ARM_DIR/SKILL.md"
    diff <(git show "HEAD:$ref" | sed -n '1,2p;4p') <(sed -n '1,2p;4p' "$ARM_DIR/SKILL.md") >/dev/null || die "arm C: lines 1, 2 or 4 differ from B"
    diff <(git show "HEAD:$ref" | tail -n +5) <(tail -n +5 "$ARM_DIR/SKILL.md") >/dev/null || die "arm C: body differs from B"
    [ "$(sed -n 3p "$ARM_DIR/SKILL.md")" = "description: $line" ] || die "arm C: line 3 is not the C description"
  fi
  local n; n="$(desc_chars "$ARM_DIR/SKILL.md")"
  if [ "$arm" = B ]; then ARM_CHARS_B="$n"; else ARM_CHARS_C="$n"; fi
  echo "arm $arm built: description $n chars, body identical to HEAD:skills/plan-dag" >&2
}

# ---- trigger case generation ----------------------------------------------------
gen_trigger_cases() {
  rm -rf "$HERE/work/trigger-cases"
  node -e '
const fs = require("fs"), path = require("path");
const [here] = process.argv.slice(1);
const t = JSON.parse(fs.readFileSync(path.join(here, "triggers.json"), "utf8"));
const up5 = "../../../../../";
const plugins = [
  "../../arm/plan-dag",
  ...["atomic-commits", "create-adr", "create-changelog", "fix-validation", "readme-maintenance", "yaml-frontmatter"].map(s => up5 + "skills/" + s),
  ...["archive-handoff", "capture-deferred", "drive-to-completion", "handoff-document", "ingest-handoff", "resume-handoff"].map(s => up5 + "suites/handoff-workflow/" + s),
  ...["brainstorm", "dep-graph", "implementation-plan", "kickoff-document", "model-picker", "parallel-agents", "research-squad", "roadmap", "subagent-dev", "wrap-session"].map(s => "../../../distractors/" + s),
];
t.forEach((e, i) => {
  const nn = String(i + 1).padStart(2, "0"), name = "trig-" + nn;
  const dir = path.join(here, "work", "trigger-cases", name);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "scaffold.sh"),
    "#!/usr/bin/env bash\nexec \"$(dirname \"$0\")/../../../scaffold.sh\" \"$(dirname \"$0\")\"\n", { mode: 0o755 });
  fs.chmodSync(path.join(dir, "scaffold.sh"), 0o755);
  const obj = {
    schema_version: "1.0", name,
    tags: nn === "01" || nn === "13" ? ["trigger", "smoke"] : ["trigger"],
    plugins,
    context: { scaffold_script: "scaffold.sh" },
    execution: {
      max_turns: 4, timeout_seconds: 300,
      allowed_tools: ["Read", "Glob", "Grep", "Skill"],
      disallowed_tools: ["Write", "Edit", "Bash", "NotebookEdit"],
      prompt: e.query,
    },
    graders: [{ name: "triggered", type: "tool_used", tool: "Skill", input_match: "plan-dag", min: 1 }],
  };
  fs.writeFileSync(path.join(dir, "case.yaml"), JSON.stringify(obj, null, 2) + "\n");
});
' "$HERE"
}

# ---- parts per stage -------------------------------------------------------------
# part|eval dir|filter|model|ablation|runs|cap|keep-temp
B_CASES="$REL/cases" T_CASES="$REL/work/trigger-cases"
parts_for_stage() {
  case "$1" in
    smoke)
      echo "harness|$B_CASES|tag:smoke|$HARNESS_SUBJECT|none|1|1|1"
      echo "behaviour-B|$B_CASES|case:secret-hygiene|$SUBJECT|with-without|1|4|1"
      echo "trigger-B|$T_CASES|tag:smoke|$SUBJECT|none|1|1|1"
      echo "behaviour-C|$B_CASES|case:secret-hygiene|$SUBJECT|none|1|3|1"
      echo "trigger-C|$T_CASES|tag:smoke|$SUBJECT|none|1|1|1" ;;
    pilot)
      echo "behaviour-B|$B_CASES|tag:behaviour|$SUBJECT|with-without|1|27|1"
      echo "behaviour-C|$B_CASES|tag:behaviour|$SUBJECT|none|1|13|1" ;;
    behaviour)
      echo "behaviour-B|$B_CASES|tag:behaviour|$SUBJECT|with-without|5|140|0"
      echo "behaviour-C|$B_CASES|tag:behaviour|$SUBJECT|none|3|60|0" ;;
    trigger)
      echo "trigger-B|$T_CASES|none|$SUBJECT|none|5|40|0"
      echo "trigger-C|$T_CASES|none|$SUBJECT|none|5|40|0" ;;
  esac
}
part_arm() { case "$1" in harness|*-B) echo B ;; *) echo C ;; esac; }

write_meta() { # $1 = finishedAt or "", $2 = exit code or ""; reads the M_* variables of run_part
  node -e '
const fs = require("fs"), crypto = require("crypto"), e = process.env;
const sha = f => { try { return crypto.createHash("sha256").update(fs.readFileSync(f)).digest("hex"); } catch { return null; } };
const m = {
  schema: 1, runId: e.M_RUNID, stage: e.M_STAGE, part: e.M_PART, suite: e.M_SUITE, arm: e.M_ARM,
  ablation: e.M_ABL, model: e.M_MODEL, judgeModel: e.M_JUDGE, effort: e.CLAUDE_CODE_EFFORT_LEVEL,
  runs: +e.M_RUNS, maxCostUsd: +e.M_CAP, caseFilter: e.M_CASE || null, cliVersion: e.M_CLI,
  repoCommit: e.M_COMMIT, skillTree: e.M_TREE, armDescriptionChars: +e.M_CHARS,
  cDescriptionSha256: sha(e.M_CDESC), armsTracked: e.M_TRACKED === "true", triggersSha256: sha(e.M_TRIG),
  platform: e.M_PLATFORM, startedAt: e.M_START, finishedAt: e.M_FIN || null,
  exitCode: e.M_RC === "" ? null : +e.M_RC, command: process.argv.slice(1),
};
fs.writeFileSync(e.M_FILE, JSON.stringify(m, null, 2) + "\n");
' -- "${CMD[@]}"
}

run_part() {
  local part="$1" evaldir="$2" filter="$3" model="$4" abl="$5" runs="$6" cap="$7" keep="$8"
  local arm; arm="$(part_arm "$part")"
  local suite="${part%%-*}"
  [ -n "$RUNS_OVERRIDE" ] && runs="$RUNS_OVERRIDE"
  [ -n "$CAP_OVERRIDE" ] && cap="$CAP_OVERRIDE"
  # --case only reaches behaviour parts; it replaces the stage's tag filter
  local case_filter=""
  if [ "$suite" = behaviour ] && [ -n "$CASE_OVERRIDE" ]; then filter="case:$CASE_OVERRIDE"; fi
  [ "${filter%%:*}" = case ] && case_filter="${filter#case:}"

  local runid; runid="$(date -u +%Y%m%dT%H%M%SZ)-$STAGE-$part"
  local out="$REL/work/results/$runid"
  CMD=(claude plugin eval "$REPO" --eval-dir "$evaldir"
       --model "$model" --judge-model "$JUDGE" --runs "$runs" -j 4
       --ablation "$abl" --scaffold --trust-plugin --no-publish --threshold 0
       --max-cost-usd "$cap")
  case "$filter" in tag:*) CMD+=(--tag "${filter#tag:}") ;; case:*) CMD+=(--case "${filter#case:}") ;; esac
  [ "$keep" = 1 ] && CMD+=(--keep-temp)
  [ "$suite" != trigger ] && CMD+=(--allow-tools Write Edit Bash)
  CMD+=(--disallow-tools "${DISALLOW[@]}"
        --output-dir "$out" --report "$out/report.html" --json "$out/run.json")

  if [ "$DRY" = 1 ]; then printf '%q ' "${CMD[@]}"; echo; return 0; fi

  mkdir -p "$HERE/work/results/$runid"
  local chars; if [ "$arm" = B ]; then chars="$ARM_CHARS_B"; else chars="$ARM_CHARS_C"; fi
  local tracked=false
  git ls-files --error-unmatch "$REL/arms/C.description.txt" >/dev/null 2>&1 && tracked=true
  export M_RUNID="$runid" M_STAGE="$STAGE" M_PART="$part" M_SUITE="$suite" M_ARM="$arm" M_ABL="$abl" \
         M_MODEL="$model" M_JUDGE="$JUDGE" M_RUNS="$runs" M_CAP="$cap" M_CASE="$case_filter" \
         M_CLI="$(claude --version)" M_COMMIT="$(git rev-parse HEAD)" M_TREE="$(git rev-parse --short HEAD:skills/plan-dag)" \
         M_CHARS="$chars" M_CDESC="$CDESC" M_TRACKED="$tracked" M_TRIG="$HERE/triggers.json" \
         M_PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)" \
         M_START="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" M_FILE="$HERE/work/results/$runid/meta.json" M_FIN="" M_RC=""
  write_meta
  echo "run.sh: $part -> $out" >&2
  set +e
  "${CMD[@]}" </dev/null 2>&1 | tee "$HERE/work/results/$runid/runner.log"
  local rc="${PIPESTATUS[0]}"
  set -e
  M_FIN="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" M_RC="$rc"
  write_meta
  [ "$rc" -eq 0 ] || exit "$rc"
}

# ---- main ------------------------------------------------------------------------
if [ "$STAGE" = arm ]; then build_arm "$ARM_ARG"; exit 0; fi

PARTS="$(parts_for_stage "$STAGE")"
case "$PARTS" in *"|$T_CASES|"*) gen_trigger_cases ;; esac

for arm in B C; do
  want_arm "$arm" || continue
  build_arm "$arm"
  while IFS='|' read -r part evaldir filter model abl runs cap keep; do
    [ "$(part_arm "$part")" = "$arm" ] || continue
    [ -z "$PART_ONLY" ] || [ "$PART_ONLY" = "$part" ] || continue
    run_part "$part" "$evaldir" "$filter" "$model" "$abl" "$runs" "$cap" "$keep"
  done <<< "$PARTS"
done
