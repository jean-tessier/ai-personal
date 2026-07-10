// Tier-2 aggregation template. Copy to ./scratch/<task>.ts and fill the TODOs.
// Contract: write FULL data to ./scratch/<task>.json, a COMPACT human summary to
// ./scratch/<task>.md, and print exactly ONE headline line to stdout. Only the
// headline + the compact .md should ever enter the agent's context.
//
// Deterministic by construction: stable sort, no wall-clock, no network.
// Run:  npx tsx ./scratch/<task>.ts     (or: node --experimental-strip-types ...)

import { writeFileSync, mkdirSync } from "node:fs";

const TASK = "TODO-task-name"; // e.g. "dep-usage"
const OUT_DIR = "./scratch";

// 1. TODO: gather sources deterministically (glob files, read JSON, run a CLI via
//    child_process and parse its --json). Keep raw reads OUT of stdout.
type Row = { key: string; count: number };
const rows: Row[] = [
  // TODO: populate from real sources
];

// 2. Aggregate (example: sum by key). Replace with the real join/group.
const byKey = new Map<string, number>();
for (const r of rows) byKey.set(r.key, (byKey.get(r.key) ?? 0) + r.count);

// 3. Stable ordering so output is reproducible run-to-run.
const result = [...byKey.entries()]
  .map(([key, count]) => ({ key, count }))
  .sort((a, b) => b.count - a.count || a.key.localeCompare(b.key));

const total = result.reduce((s, r) => s + r.count, 0);

// 4. Emit: full JSON + compact MD. Neither is printed.
mkdirSync(OUT_DIR, { recursive: true });
writeFileSync(`${OUT_DIR}/${TASK}.json`, JSON.stringify(result, null, 2));
const md =
  `# ${TASK}\n\ntotal: ${total} · groups: ${result.length}\n\n` +
  result.slice(0, 20).map((r) => `- ${r.key}: ${r.count}`).join("\n") + "\n";
writeFileSync(`${OUT_DIR}/${TASK}.md`, md);

// 5. Headline only — the single line the orchestrator reads.
console.log(`${TASK}: total=${total} groups=${result.length} -> ${OUT_DIR}/${TASK}.md`);

// 6. Cross-check reminder: re-derive `total` a second way (e.g. jq over the source)
//    and compare via scripts/crosscheck.sh before trusting it.
