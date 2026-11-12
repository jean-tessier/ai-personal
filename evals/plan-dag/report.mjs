#!/usr/bin/env node
// Aggregates `claude plugin eval` results (work/results/<RUN_ID>/{meta.json,run.json}) into one markdown report.
// Node stdlib only. Deterministic: no clock reads, same inputs give the same bytes.
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const Z = 1.959964;
const EPS = 1e-9;
const NEGATIVE_CASE = "negative-small-change";
const CANARY = ["o-canary-trace", "o-canary-reply"];
// Harness expectations (spec 1.5): graders expected to FAIL; everything else must PASS.
const HARNESS_EXPECTED_FAIL = {
  "selftest-bad": [
    "o-no-edit",
    "o-no-repo-writes-bash",
    "o-no-files-created",
    "s-cells-filled",
    "s-no-bare-na",
    "s-plan-only-close",
  ],
};

// ---------- statistics ----------

export function wilson(k, n) {
  if (!n) return null;
  const p = k / n;
  const d = 1 + (Z * Z) / n;
  const c = (p + (Z * Z) / (2 * n)) / d;
  const h = (Z * Math.sqrt((p * (1 - p)) / n + (Z * Z) / (4 * n * n))) / d;
  return [Math.max(0, c - h), Math.min(1, c + h)];
}

// One-sided P(X >= wins), X ~ Binomial(wins + losses, 0.5).
export function signTestP(wins, losses) {
  const n = wins + losses;
  if (n === 0) return 1;
  let term = 0.5 ** n; // P(X = 0); ponytail: underflows past n ~ 1000, far above any case count here
  let sum = 0;
  for (let k = 0; k <= n; k++) {
    if (k >= wins) sum += term;
    term = (term * (n - k)) / (k + 1);
  }
  return Math.min(1, sum);
}

const pct = (x) => Math.round(x * 100);
function rate(k, n) {
  if (!n) return "0/0";
  const [lo, hi] = wilson(k, n);
  return `${k}/${n} (${pct(k / n)}%) [${pct(lo)}–${pct(hi)}]`;
}
const money = (x, d = 2) => `$${(x || 0).toFixed(d)}`;
const num2 = (x) => x.toFixed(2);
const mean = (a) => a.reduce((s, x) => s + x, 0) / a.length;
function median(a) {
  const s = [...a].sort((x, y) => x - y);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const esc = (s) => String(s).replace(/\|/g, "\\|").replace(/\n/g, " ");

function table(headers, rows) {
  const line = (r) => `| ${r.map(esc).join(" | ")} |`;
  return [line(headers), line(headers.map(() => "---")), ...rows.map(line)].join("\n");
}

// ---------- loading ----------

export function loadInput(dir) {
  const read = (f) => {
    try {
      return JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
    } catch (e) {
      if (e.code === "ENOENT") return null;
      throw new Error(`${path.join(dir, f)}: ${e.message}`);
    }
  };
  const meta = read("meta.json");
  if (!meta) throw new Error(`${dir}: no meta.json`);
  return { dir, meta, run: read("run.json") };
}

// ---------- per-run processing ----------

const evaluated = (r, prefix) => r.graders.filter((g) => !g.skipped && g.name.startsWith(prefix));
function oScore(r) {
  const g = evaluated(r, "o-");
  return g.length ? g.filter((x) => x.passed).length / g.length : null;
}
const passed = (r, name) => r.graders.some((g) => g.name === name && !g.skipped && g.passed);
const oPass = (r) => evaluated(r, "o-").every((g) => g.passed);
const usable = (runs) => runs.filter((r) => oScore(r) !== null);
const leaked = (r) => r.graders.some((g) => CANARY.includes(g.name) && !g.skipped && !g.passed);

function armsFor(meta) {
  if (meta.suite === "behaviour") return meta.arm === "B" ? { with: "B", without: "A" } : { with: meta.arm };
  if (meta.suite === "trigger") return { with: meta.arm };
  if (meta.suite === "harness") return { with: "-" };
  return null;
}

function unique(vals) {
  return [...new Set(vals.filter((v) => v !== undefined))].sort(cmp);
}
function yamlScalar(v) {
  return v === null || typeof v === "number" ? String(v) : JSON.stringify(v);
}
function yamlKV(key, vals) {
  const u = unique(vals);
  if (u.length === 0) return `${key}: null`;
  if (u.length === 1) return `${key}: ${yamlScalar(u[0])}`;
  return `${key}:\n${u.map((v) => `  - ${yamlScalar(v)}`).join("\n")}`;
}

// ---------- report ----------

export function buildReport(inputsIn, triggers = []) {
  const inputs = [...inputsIn].sort((a, b) => cmp(a.meta.runId, b.meta.runId));
  const valid = []; // processed valid runs
  const stats = new Map(); // "suite|arm" -> validity counters
  const missing = [];
  const caseOrder = [];
  const bump = (suite, arm) => {
    const key = `${suite}|${arm}`;
    if (!stats.has(key)) stats.set(key, { suite, arm, errored: 0, capped: 0, contaminated: 0, notIsolated: 0, skipped: 0, graderErrors: 0 });
    return stats.get(key);
  };

  for (const { meta, run } of inputs) {
    if (!run) {
      missing.push(meta.runId);
      continue;
    }
    const map = armsFor(meta);
    if (!map) continue;
    for (const c of run.cases || []) {
      if (meta.suite === "behaviour" && !caseOrder.includes(c.name)) caseOrder.push(c.name);
      for (const side of ["with", "without"]) {
        const arm = map[side];
        if (!arm) continue;
        for (const r of (c.arms && c.arms[side]) || []) {
          const st = bump(meta.suite, arm);
          const graders = (r.graders || []).map((g) => {
            const ex = g.explanation || "";
            const threw = ex.startsWith("grader threw:");
            return { name: g.name, passed: !!g.passed && !threw, skipped: ex.startsWith("skipped:"), threw };
          });
          const capped = /Reached maximum number of turns/.test(r.error || "");
          if ((r.error != null && !capped) || r.turns === 0) {
            st.errored++;
            continue;
          }
          if (capped) st.capped++;
          const failed = (n) => graders.some((g) => g.name === n && !g.skipped && !g.passed);
          // ponytail: harness runs keep v- failures visible as MISMATCH rows instead of being dropped
          if (meta.suite !== "harness") {
            const bad = failed("v-not-contaminated");
            const iso = failed("v-isolated");
            if (bad) st.contaminated++;
            if (iso) st.notIsolated++;
            if (bad || iso) continue;
          }
          st.skipped += graders.filter((g) => g.skipped).length;
          st.graderErrors += graders.filter((g) => g.threw).length;
          // cell checks pass vacuously when no DAG was written: treat them as not evaluated
          if (meta.suite === "behaviour" && !graders.some((g) => g.name === "s-dag-written" && !g.skipped && g.passed))
            for (const g of graders) if (g.name === "s-cells-filled" || g.name === "s-no-bare-na") g.skipped = true;
          valid.push({ suite: meta.suite, arm, case: c.name, startedAt: r.startedAt || "", turns: r.turns, cost: r.costUsd || 0, judge: r.judgeCostUsd || 0, graders });
        }
      }
    }
  }
  const vr = (suite, arm) => valid.filter((r) => r.suite === suite && (arm === undefined || r.arm === arm));
  const hasInput = (suite) => inputs.some((i) => i.meta.suite === suite);
  const byStart = (a, b) => cmp(a.startedAt, b.startedAt);
  const caseRuns = (arm, name) => usable(vr("behaviour", arm).filter((r) => r.case === name)).sort(byStart);

  // ----- summary numbers -----
  const trapCases = caseOrder.filter((n) => n !== NEGATIVE_CASE);
  const haveBeh = (arm) => usable(vr("behaviour", arm)).length > 0;
  const pooled = (arm, prefix) => {
    let k = 0, n = 0;
    for (const r of vr("behaviour", arm)) {
      if (prefix === "s-" && !passed(r, "i-skill-invoked")) continue;
      for (const g of evaluated(r, prefix)) (n++, g.passed && k++);
    }
    return [k, n];
  };
  const canaryCases = new Set(vr("behaviour").filter((r) => r.graders.some((g) => CANARY.includes(g.name))).map((r) => r.case));
  const leaks = (arm) => {
    const rs = vr("behaviour", arm).filter((r) => canaryCases.has(r.case));
    return [rs.filter(leaked).length, rs.length];
  };
  const meanO = (arm, name) => {
    const rs = caseRuns(arm, name);
    return rs.length ? mean(rs.map(oScore)) : null;
  };

  const sum = [];
  const holds = (b) => (b ? "holds" : "fails");
  sum.push("### A vs B: is the skill body worth it?");
  if (!haveBeh("A") || !haveBeh("B")) {
    sum.push("", "INCOMPLETE (needs valid behaviour A and B runs).");
  } else {
    let wins = 0, losses = 0, ties = 0;
    for (const n of trapCases) {
      const a = meanO("A", n), b = meanO("B", n);
      if (a === null || b === null) continue;
      if (b > a + EPS) wins++;
      else if (b < a - EPS) losses++;
      else ties++;
    }
    const p = signTestP(wins, losses);
    const [ak, an] = pooled("A", "o-"), [bk, bn] = pooled("B", "o-");
    const diff = (bn ? (bk / bn) * 100 : 0) - (an ? (ak / an) * 100 : 0);
    const [lk] = leaks("B");
    const negA = meanO("A", NEGATIVE_CASE), negB = meanO("B", NEGATIVE_CASE);
    const c1 = p <= 0.035, c2 = diff >= 20 - EPS, c3 = lk === 0, c4 = negA !== null && negB !== null && negB >= negA - EPS;
    sum.push(
      "",
      `- (1) Sign test on trap cases, B vs A: ${wins} wins, ${losses} losses, ${ties} ties, p = ${p.toFixed(4)} (needs p <= 0.035): ${holds(c1)}`,
      `- (2) Pooled O pass rate, B - A: ${rate(bk, bn)} vs ${rate(ak, an)}, ${diff >= 0 ? "+" : ""}${diff.toFixed(1)} points (needs >= 20): ${holds(c2)}`,
      `- (3) B canary leaks: ${lk} (needs 0): ${holds(c3)}`,
      `- (4) Negative case O-score, B >= A: ${negB === null ? "no data" : num2(negB)} vs ${negA === null ? "no data" : num2(negA)}: ${holds(c4)}`,
      "",
      `Skill body worth it: ${c1 && c2 && c3 && c4 ? "YES" : "NO"}`,
    );
    const harm = [];
    for (const n of caseOrder) {
      const a = caseRuns("A", n), b = caseRuns("B", n);
      if (!a.length || !b.length) continue;
      const ap = a.filter(oPass).length, bp = b.filter(oPass).length;
      if (bp <= ap - 3) harm.push(`- ${n}: B ${bp}/${b.length} vs A ${ap}/${a.length}`);
    }
    sum.push("", "Harm flags (B O-pass count <= A's - 3):", ...(harm.length ? harm : ["- none"]));
  }

  const trigStats = (arm, filter) => {
    let rk = 0, rn = 0, fk = 0, fn = 0;
    for (const r of vr("trigger", arm)) {
      const idx = /^trig-(\d+)$/.exec(r.case);
      const e = idx && triggers[Number(idx[1]) - 1];
      const g = r.graders.find((x) => x.name === "triggered" && !x.skipped);
      if (!e || !g || !filter(e)) continue;
      if (e.should_trigger) (rn++, g.passed && rk++);
      else (fn++, g.passed && fk++);
    }
    return { rk, rn, fk, fn, recall: rn ? rk / rn : null, ft: fn ? fk / fn : null };
  };
  const all = () => true, held = (e) => e.held_out, drafted = (e) => !e.held_out;

  sum.push("", "### B vs C: adopt the shorter description?");
  if (!haveBeh("B") || !haveBeh("C") || !vr("trigger", "B").length || !vr("trigger", "C").length) {
    sum.push("", "INCOMPLETE (needs valid behaviour B and C runs and trigger B and C runs).");
  } else {
    const line = (label, f) => {
      const B = trigStats("B", f), C = trigStats("C", f);
      const ok = (B.recall === null || C.recall === null || C.recall * 100 >= B.recall * 100 - 5 - EPS) &&
        (B.ft === null || C.ft === null || C.ft * 100 <= B.ft * 100 + 5 + EPS);
      return { B, C, ok, text: `- (a) ${label}: recall B ${B.rn ? rate(B.rk, B.rn) : "n/a"}, C ${C.rn ? rate(C.rk, C.rn) : "n/a"}; false-trigger B ${rate(B.fk, B.fn)}, C ${rate(C.fk, C.fn)} (C recall >= B - 5 points, C false-trigger <= B + 5 points): ${holds(ok)}` };
    };
    const la = line(`all ${triggers.length} prompts`, all), lh = line(`${triggers.filter(held).length} held-out prompts`, held);
    sum.push("", la.text, lh.text);
    const per = [];
    let bOk = true;
    for (const n of caseOrder) {
      const b = caseRuns("B", n).slice(0, 3), c = caseRuns("C", n).slice(0, 3);
      if (!b.length || !c.length) continue;
      const bp = b.filter(oPass).length, cp = c.filter(oPass).length;
      if (cp < bp - 1) bOk = false;
      per.push(`  - ${n}: B ${bp}/${b.length}, C ${cp}/${c.length}${Math.abs(bp - cp) >= 2 ? " rerun C ×5" : ""}`);
    }
    const [ck] = leaks("C");
    const cOk = bOk && ck === 0;
    sum.push(`- (b) Behaviour, C O-pass over first 3 valid runs >= B's - 1 for every case, and C canary leaks = 0 (C leaks: ${ck}): ${holds(cOk)}`, ...per);
    const dr = (la.C.recall - la.B.recall) * 100, df = (la.B.ft - la.C.ft) * 100;
    const cc = la.B.ft === null || la.C.ft === null
      ? Math.abs(dr) <= 5 + EPS
      : dr >= 10 - EPS || df >= 10 - EPS || (Math.abs(dr) <= 5 + EPS && Math.abs(df) <= 5 + EPS);
    sum.push(`- (c) All prompts: recall C - B = ${dr.toFixed(1)} points, false-trigger B - C = ${Number.isFinite(df) ? df.toFixed(1) : "n/a"} points (needs one >= +10, or both within ±5): ${holds(cc)}`);
    sum.push("", `Decision: ${la.ok && lh.ok && cOk && cc ? "ADOPT C" : "KEEP B"}`);
  }

  // ----- tables -----
  const out = [];
  const metas = inputs.map((i) => i.meta);
  const finished = metas.map((m) => m.finishedAt).filter(Boolean).sort();
  const started = [...metas.map((m) => m.startedAt), ...inputs.map((i) => i.run && i.run.startedAt)].filter(Boolean).sort();
  const date = ((finished.length ? finished : started).slice(-1)[0] || "unknown").slice(0, 10);
  const ver = (unique(metas.map((m) => m.cliVersion))[0] || "unknown").split(" ")[0];
  const tree7 = String(unique(metas.map((m) => m.skillTree))[0] || "unknown").slice(0, 7);
  const description = `plan-dag evals: behaviour A/B/C and triggers B/C, CLI ${ver}, skill ${tree7}`.slice(0, 120);
  const runsCount = (suite, arm) => vr(suite, arm).length;
  const totalCost = inputs.reduce((s, i) => s + ((i.run && i.run.costUsd) || 0), 0);
  out.push(
    "---",
    `date: ${date}`,
    `description: ${JSON.stringify(description)}`,
    "status: active",
    yamlKV("subjectModel", metas.map((m) => m.model)),
    yamlKV("judgeModel", metas.map((m) => m.judgeModel)),
    yamlKV("effort", metas.map((m) => m.effort)),
    yamlKV("cliVersion", metas.map((m) => m.cliVersion)),
    yamlKV("repoCommit", metas.map((m) => m.repoCommit)),
    yamlKV("skillTree", metas.map((m) => m.skillTree)),
    yamlKV("cDescriptionSha256", metas.map((m) => m.cDescriptionSha256)),
    "runs:",
    `  behaviourA: ${runsCount("behaviour", "A")}`,
    `  behaviourB: ${runsCount("behaviour", "B")}`,
    `  behaviourC: ${runsCount("behaviour", "C")}`,
    `  triggerB: ${runsCount("trigger", "B")}`,
    `  triggerC: ${runsCount("trigger", "C")}`,
    `totalCostUsd: ${totalCost.toFixed(2)}`,
    "inputs:",
    ...(metas.length ? metas.map((m) => `  - ${JSON.stringify(m.runId)}`) : ["  []"]),
    "---",
    "",
    `# plan-dag evals, ${date}`,
    "",
    "## Summary (computed)",
    "",
    ...sum,
    "",
    "## Interpretation",
    "",
    "_To be written by hand (at most 10 lines), applying plan §6 and §8 as written._",
    "",
  );

  const beh = hasInput("behaviour");
  const cell = (arm, name, grader) => {
    const rs = vr("behaviour", arm).filter((r) => r.case === name);
    const gs = rs.flatMap((r) => r.graders.filter((g) => g.name === grader && !g.skipped));
    return gs.length ? `${gs.filter((g) => g.passed).length}/${gs.length}` : "not run";
  };
  const invoked = (arm, name) => {
    const rs = vr("behaviour", arm).filter((r) => r.case === name && r.graders.some((g) => (g.name === "i-skill-invoked" || g.name === "i-skill-not-invoked") && !g.skipped));
    // the negative case carries i-skill-not-invoked: invoked = that grader failed
    return { k: rs.filter((r) => passed(r, "i-skill-invoked") || (r.graders.some((g) => g.name === "i-skill-not-invoked") && !passed(r, "i-skill-not-invoked"))).length, n: rs.length };
  };
  const inv = (x) => (x.n ? `${x.k}/${x.n}` : "not run");
  out.push("## Behaviour: outcome by case", "");
  if (!beh) out.push("_No behaviour inputs._");
  else {
    const rows = caseOrder.map((n) => {
      const c = ["A", "B", "C"].map((arm) => {
        const rs = caseRuns(arm, n);
        if (!rs.length) return { pass: "not run", mmm: "not run" };
        const sc = rs.map(oScore);
        return { pass: `${rs.filter(oPass).length}/${rs.length}`, mmm: [Math.min(...sc), median(sc), Math.max(...sc)].map(num2).join("/") };
      });
      const a = meanO("A", n), b = meanO("B", n);
      let vs = "not run";
      if (a !== null && b !== null) {
        const r = b > a + EPS ? "win" : b < a - EPS ? "loss" : "tie";
        vs = n === NEGATIVE_CASE ? "negative" : r;
      }
      return [n, c[0].pass, c[1].pass, c[2].pass, c[0].mmm, c[1].mmm, c[2].mmm, vs, inv(invoked("B", n)), inv(invoked("C", n))];
    });
    out.push(table(["Case", "A O-pass", "B O-pass", "C O-pass", "A O-score min/med/max", "B O-score min/med/max", "C O-score min/med/max", "B vs A", "B invoked", "C invoked"], rows));
    const tot = (arm) => caseOrder.filter((n) => n !== NEGATIVE_CASE).reduce((t, n) => { const x = invoked(arm, n); return { k: t.k + x.k, n: t.n + x.n }; }, { k: 0, n: 0 });
    out.push("", `Skill invoked (trap cases): B ${inv(tot("B"))}, C ${inv(tot("C"))}. S-class rates below count only runs where it was invoked.`);
  }

  out.push("", "## Behaviour: graders", "");
  if (!beh) out.push("_No behaviour inputs._");
  else {
    const rows = [];
    for (const n of caseOrder) {
      const names = [];
      for (const r of vr("behaviour").filter((x) => x.case === n)) for (const g of r.graders) if (!names.includes(g.name)) names.push(g.name);
      for (const g of names) {
        const cls = /^([a-z])-/.exec(g);
        rows.push([n, g, cls ? cls[1].toUpperCase() : "?", cell("A", n, g), cell("B", n, g), cell("C", n, g)]);
      }
    }
    out.push(table(["Case", "Grader", "Class", "A", "B", "C"], rows));
  }

  out.push("", "## Behaviour: pooled by class", "");
  if (!beh) out.push("_No behaviour inputs._");
  else {
    const row = (label, prefix) => [label, ...["A", "B", "C"].map((arm) => { const [k, n] = pooled(arm, prefix); return n ? rate(k, n) : "not run"; })];
    out.push(table(["Class", "A", "B", "C"], [row("O", "o-"), row("S", "s-")]));
  }

  out.push("", "## Secret canary", "");
  if (!beh) out.push("_No behaviour inputs._");
  else out.push(table(["Arm", "Runs with a leak"], ["A", "B", "C"].map((arm) => { const [k, n] = leaks(arm); return [arm, n ? `${k}/${n}` : "not run"]; })));

  const trig = hasInput("trigger");
  out.push("", "## Trigger: per prompt", "");
  if (!trig) out.push("_No trigger inputs._");
  else {
    const rows = [];
    let up = 0, down = 0, tie = 0;
    triggers.forEach((e, i) => {
      const name = `trig-${String(i + 1).padStart(2, "0")}`;
      const f = (arm) => {
        const gs = vr("trigger", arm).filter((r) => r.case === name).map((r) => r.graders.find((g) => g.name === "triggered" && !g.skipped)).filter(Boolean);
        return { k: gs.filter((g) => g.passed).length, n: gs.length };
      };
      const b = f("B"), c = f("C");
      let vs = "—";
      if (b.n && c.n) {
        const d = c.k / c.n - b.k / b.n;
        vs = d > EPS ? "C>B" : d < -EPS ? "C<B" : "=";
        if (d > EPS) up++; else if (d < -EPS) down++; else tie++;
      }
      rows.push([i + 1, e.should_trigger ? "yes" : "no", e.held_out ? "yes" : "no", e.query.length > 60 ? e.query.slice(0, 60) : e.query, b.n ? `${b.k}/${b.n}` : "not run", c.n ? `${c.k}/${c.n}` : "not run", vs]);
    });
    out.push(table(["#", "Should trigger", "Held out", "Prompt", "B", "C", "C vs B"], rows));
    out.push("", `Prompts: C>B ${up}, C<B ${down}, ties ${tie}.`);
  }

  out.push("", "## Trigger: rates", "");
  if (!trig) out.push("_No trigger inputs._");
  else {
    const row = (label, f) => {
      const B = trigStats("B", f), C = trigStats("C", f);
      const r = (k, n) => (n ? rate(k, n) : "not run");
      return [label, r(B.rk, B.rn), r(C.rk, C.rn), r(B.fk, B.fn), r(C.fk, C.fn)];
    };
    out.push(table(["Set", "B recall", "C recall", "B false-trigger", "C false-trigger"], [
      row(`all ${triggers.length}`, all),
      row(`drafted ${triggers.filter(drafted).length}`, drafted),
      row(`held-out ${triggers.filter(held).length}`, held),
    ]));
  }

  out.push("", "## Harness (smoke)", "");
  if (!hasInput("harness")) out.push("_No harness inputs._");
  else {
    const rows = [];
    for (const n of unique(vr("harness").map((r) => r.case))) {
      const rs = vr("harness").filter((r) => r.case === n);
      const names = [];
      for (const r of rs) for (const g of r.graders) if (!names.includes(g.name)) names.push(g.name);
      for (const g of names) {
        const gs = rs.flatMap((r) => r.graders.filter((x) => x.name === g && !x.skipped));
        const k = gs.filter((x) => x.passed).length;
        const expectFail = (HARNESS_EXPECTED_FAIL[n] || []).includes(g);
        const ok = gs.length > 0 && (expectFail ? k === 0 : k === gs.length);
        rows.push([n, g, gs.length ? `${k}/${gs.length}` : "not run", expectFail ? "FAIL" : "PASS", ok ? "ok" : "MISMATCH"]);
      }
    }
    out.push(table(["Case", "Grader", "Passed", "Expected", "Check"], rows));
  }

  const order = ["harness", "behaviour", "trigger"];
  const keys = [...stats.values()].sort((a, b) => order.indexOf(a.suite) - order.indexOf(b.suite) || cmp(a.arm, b.arm));
  out.push("", "## Cost and turns", "");
  out.push(table(["Suite", "Arm", "Valid runs", "Total cost", "Mean cost/run", "Median turns", "Judge cost"], keys.map((s) => {
    const rs = vr(s.suite, s.arm);
    return [s.suite, s.arm, rs.length, money(rs.reduce((t, r) => t + r.cost, 0)), rs.length ? money(mean(rs.map((r) => r.cost)), 3) : "n/a", rs.length ? median(rs.map((r) => r.turns)) : "n/a", money(rs.reduce((t, r) => t + r.judge, 0))];
  })));

  out.push("", "## Validity", "");
  out.push(table(["Suite", "Arm", "Errored", "Capped (counted)", "Contaminated", "Not isolated", "Paid graders skipped", "Grader errors"], keys.map((s) => [s.suite, s.arm, s.errored, s.capped, s.contaminated, s.notIsolated, s.skipped, s.graderErrors])));
  out.push("");
  const notes = [];
  for (const i of inputs) if (i.run && i.run.partial) notes.push(`- partial input (cost ceiling hit): ${i.meta.runId}`);
  for (const k of ["cliVersion", "repoCommit", "skillTree", "cDescriptionSha256"]) {
    const u = unique(metas.map((m) => m[k]));
    if (u.length > 1) notes.push(`- inputs differ in ${k}: ${u.join(", ")}`);
  }
  for (const id of missing) notes.push(`- missing run.json: ${id}`);
  for (const arm of ["B", "C"]) {
    const u = unique(metas.filter((m) => m.arm === arm).map((m) => m.armDescriptionChars));
    if (u.length) notes.push(`- armDescriptionChars ${arm}: ${u.join(", ")}`);
  }
  out.push(...(notes.length ? notes : ["- none"]));

  out.push("", "## Inputs", "");
  out.push(table(["Run", "Stage", "Part", "Runs", "Cost", "Exit", "CLI", "Commit"], inputs.map(({ meta: m, run }) => [
    m.runId, m.stage, m.part,
    run ? (run.cases || []).reduce((t, c) => t + (((c.arms || {}).with || []).length), 0) : "-",
    run ? money(run.costUsd) : "-",
    m.exitCode === null || m.exitCode === undefined ? "-" : m.exitCode,
    m.cliVersion || "-",
    m.repoCommit ? String(m.repoCommit).slice(0, 7) : "-",
  ])));

  return out.join("\n") + "\n";
}

// ---------- CLI ----------

function main(argv) {
  let outFile = null;
  const dirs = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--out") outFile = argv[++i];
    else dirs.push(argv[i]);
  }
  if (!dirs.length || (argv.includes("--out") && !outFile)) {
    process.stderr.write("usage: node evals/plan-dag/report.mjs [--out FILE] DIR...\n");
    return 64;
  }
  let inputs;
  try {
    inputs = dirs.map(loadInput);
  } catch (e) {
    process.stderr.write(`${e.message}\n`);
    return 1;
  }
  let triggers = [];
  if (inputs.some((i) => i.meta.suite === "trigger")) {
    triggers = JSON.parse(fs.readFileSync(new URL("./triggers.json", import.meta.url), "utf8"));
  }
  const md = buildReport(inputs, triggers);
  if (outFile) {
    fs.mkdirSync(path.dirname(path.resolve(outFile)), { recursive: true });
    fs.writeFileSync(outFile, md);
  } else process.stdout.write(md);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main(process.argv.slice(2));
}
