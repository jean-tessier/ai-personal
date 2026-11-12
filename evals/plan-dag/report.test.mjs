import { test, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { wilson, signTestP, loadInput, buildReport } from "./report.mjs";

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "plan-dag-report-"));
after(() => fs.rmSync(tmp, { recursive: true, force: true }));

const g = (name, passed, explanation = "") => ({ name, passed, weight: 1, explanation });
const run = (graders, extra = {}) => ({ turns: 5, costUsd: 1, judgeCostUsd: 0.1, startedAt: "2026-11-12T01:00:00Z", error: null, graders, ...extra });
const meta = (runId, suite, arm, extra = {}) => ({ schema: 1, runId, stage: suite, part: `${suite}-${arm}`, suite, arm, cliVersion: "2.1.322 (Claude Code)", repoCommit: "abcdef1234", skillTree: "1234567", startedAt: "2026-11-12T00:00:00Z", finishedAt: "2026-11-12T02:00:00Z", exitCode: 0, ...extra });
const input = (m, cases) => ({ meta: m, run: { costUsd: 2, partial: false, cases } });
const kase = (name, withRuns, withoutRuns) => ({ name, arms: withoutRuns ? { with: withRuns, without: withoutRuns } : { with: withRuns } });

const HEADINGS = [
  "## Summary (computed)", "## Interpretation", "## Behaviour: outcome by case", "## Behaviour: graders",
  "## Behaviour: pooled by class", "## Secret canary", "## Trigger: per prompt", "## Trigger: rates",
  "## Harness (smoke)", "## Cost and turns", "## Validity", "## Inputs",
];

test("wilson", () => {
  const [lo, hi] = wilson(8, 10);
  assert.ok(Math.abs(lo - 0.4902) < 0.0005 && Math.abs(hi - 0.9433) < 0.0005);
  assert.equal(wilson(0, 0), null);
});

test("signTestP", () => {
  assert.ok(Math.abs(signTestP(7, 1) - 0.03516) < 0.00005);
  assert.ok(Math.abs(signTestP(6, 2) - 0.14453) < 0.00005);
  assert.equal(signTestP(0, 0), 1);
});

test("arm mapping: behaviour B -> B and A, behaviour C -> C", () => {
  const ok = [g("o-x", true)], bad = [g("o-x", false)];
  const b = input(meta("r1", "behaviour", "B"), [kase("c1", [run(ok)], [run(bad)])]);
  const c = input(meta("r2", "behaviour", "C"), [kase("c1", [run(ok)])]);
  const md = buildReport([b, c]);
  const row = md.split("\n").find((l) => l.startsWith("| c1 | 0/1 | 1/1 | 1/1 |"));
  assert.ok(row, md);
  assert.match(md, /\| c1 \| o-x \| O \| 0\/1 \| 1\/1 \| 1\/1 \|/);
});

test("errored and contaminated runs are excluded and counted", () => {
  const ok = [g("o-x", true), g("v-not-contaminated", true)];
  const dirty = [g("o-x", false), g("v-not-contaminated", false)];
  const i = input(meta("r1", "behaviour", "B"), [kase("c1", [run(ok), run(dirty), run(ok, { error: "boom" })], [])]);
  const md = buildReport([i]);
  assert.match(md, /\| c1 \| not run \| 1\/1 \| not run \|/); // only the clean run counts for B
  assert.match(md, /\| behaviour \| B \| 1 \| 0 \| 1 \| 0 \| 0 \| 0 \|/); // errored 1, capped 0, contaminated 1
});

test("skipped graders are excluded from denominators", () => {
  const i = input(meta("r1", "behaviour", "B"), [kase("c1", [run([g("o-a", true), g("o-b", false, "skipped: cost ceiling")])], [])]);
  const md = buildReport([i]);
  assert.match(md, /\| c1 \| o-a \| O \| not run \| 1\/1 \|/);
  assert.match(md, /\| c1 \| o-b \| O \| not run \| not run \|/);
  assert.match(md, /\| behaviour \| B \| 0 \| 0 \| 0 \| 0 \| 1 \| 0 \|/);
});

test("trigger recall and false-trigger rate", () => {
  const triggers = [
    { query: "pos", should_trigger: true, held_out: false },
    { query: "neg", should_trigger: false, held_out: true },
  ];
  const t = (arm, hits) => input(meta(`t-${arm}`, "trigger", arm), [
    kase("trig-01", [run([g("triggered", hits[0])]), run([g("triggered", hits[0])])]),
    kase("trig-02", [run([g("triggered", hits[1])]), run([g("triggered", false)])]),
  ]);
  const md = buildReport([t("B", [true, true]), t("C", [false, false])], triggers);
  // B: recall 2/2, false-trigger 1/2; C: recall 0/2, false-trigger 0/2
  assert.match(md, /\| all 2 \| 2\/2 \(100%\)[^|]*\| 0\/2 \(0%\)[^|]*\| 1\/2 \(50%\)[^|]*\| 0\/2 \(0%\)/);
  assert.match(md, /\| 1 \| yes \| no \| pos \| 2\/2 \| 0\/2 \| C<B \|/);
  assert.match(md, /Prompts: C>B 0, C<B 2, ties 0\./);
});

test("harness expectations", () => {
  const bad = ["o-no-edit", "o-no-repo-writes-bash", "o-no-files-created", "s-cells-filled", "s-no-bare-na", "s-plan-only-close"];
  const mk = (flip) => {
    const graders = [...bad.map((n) => g(n, n === flip)), g("s-dag-written", flip !== "s-dag-written"), g("v-isolated", true)];
    return [input(meta("h", "harness", "B"), [kase("selftest-bad", [run(graders)])])];
  };
  const good = buildReport(mk(null));
  assert.ok(!good.includes("MISMATCH"), good);
  assert.match(good, /\| selftest-bad \| o-no-edit \| 0\/1 \| FAIL \| ok \|/);
  assert.match(buildReport(mk("o-no-edit")), /\| selftest-bad \| o-no-edit \| 1\/1 \| FAIL \| MISMATCH \|/);
});

test("report shape and determinism, loaded from disk", () => {
  const dir = path.join(tmp, "run1");
  fs.mkdirSync(dir);
  const i = input(meta("r1", "behaviour", "B"), [kase("c1", [run([g("o-x", true)])], [run([g("o-x", false)])])]);
  fs.writeFileSync(path.join(dir, "meta.json"), JSON.stringify(i.meta));
  fs.writeFileSync(path.join(dir, "run.json"), JSON.stringify(i.run));
  const nodir = path.join(tmp, "run2");
  fs.mkdirSync(nodir);
  fs.writeFileSync(path.join(nodir, "meta.json"), JSON.stringify(meta("r2", "behaviour", "C")));
  const inputs = [loadInput(dir), loadInput(nodir)];
  const md = buildReport(inputs, []);
  assert.ok(md.startsWith("---\n"));
  for (const h of HEADINGS) assert.ok(md.includes(h), h);
  assert.match(md, /missing run\.json: r2/);
  assert.equal(md, buildReport(inputs, []));
});

test("max-turns runs count as valid and are tallied as capped", () => {
  const ok = [g("o-x", true)];
  const capped = run(ok, { error: "exit 1: Reached maximum number of turns (4)" });
  const i = input(meta("r1", "behaviour", "B"), [kase("c1", [capped, run(ok, { error: "boom" }), run(ok, { turns: 0 })], [])]);
  const md = buildReport([i]);
  assert.match(md, /\| c1 \| not run \| 1\/1 \| not run \|/);
  assert.match(md, /\| behaviour \| B \| 2 \| 1 \| 0 \| 0 \| 0 \| 0 \|/); // errored 2 (boom, zero turns), capped 1
  assert.match(md, /\| Suite \| Arm \| Errored \| Capped \(counted\) \|/);
});

test("skill invocation columns and summary line", () => {
  const inv = (p) => [g("o-x", true), g("i-skill-invoked", p)];
  const b = input(meta("r1", "behaviour", "B"), [kase("c1", [run(inv(true))], [run([g("o-x", true)])]), kase("c2", [run(inv(false))], [run([g("o-x", true)])])]);
  const c = input(meta("r2", "behaviour", "C"), [kase("c1", [run(inv(false))]), kase("c2", [run(inv(false))])]);
  const md = buildReport([b, c]);
  assert.match(md, /\| c1 \|[^\n]*\| 1\/1 \| 0\/1 \|\n/); // B invoked 1/1, C invoked 0/1
  assert.match(md, /\| c2 \|[^\n]*\| 0\/1 \| 0\/1 \|\n/);
  assert.match(md, /Skill invoked \(trap cases\): B 1\/2, C 0\/2/);
});

test("S class counts only invoked runs; cell checks need a written DAG", () => {
  const s = (invoked, dag, cells) => [g("o-x", true), g("i-skill-invoked", invoked), g("s-dag-written", dag), g("s-cells-filled", cells), g("s-no-bare-na", cells), g("s-plan-only-close", true)];
  const i = input(meta("r1", "behaviour", "B"), [kase("c1", [
    run(s(false, false, true)), // not invoked: excluded from S entirely
    run(s(true, false, true)), // invoked, no DAG: cell checks vacuous, not evaluated
    run(s(true, true, true)),
  ], [])]);
  const md = buildReport([i]);
  assert.match(md, /\| c1 \| s-dag-written \| S \| not run \| 1\/3 \|/); // per-case table is unfiltered by invocation
  assert.match(md, /\| c1 \| s-cells-filled \| S \| not run \| 1\/1 \|/); // only the run with a DAG
  assert.match(md, /\| S \| not run \| 5\/6 \(83%\)/); // runs 2+3 only: dag 1/2, close 2/2, cells 1/1, bare-na 1/1
});

test("negative case invocation is read from i-skill-not-invoked and left out of the total", () => {
  const b = input(meta("r1", "behaviour", "B"), [kase("negative-small-change", [run([g("o-x", true), g("i-skill-not-invoked", false)])], [])]);
  const md = buildReport([b]);
  assert.match(md, /\| negative-small-change \|[^\n]*\| 1\/1 \| not run \|\n/);
  assert.match(md, /Skill invoked \(trap cases\): B not run, C not run/);
});
