#!/usr/bin/env node
// aggregate.ts — starting-point template for scratch-script (Tier 2).
// Copy into ./scratch/, rename, and adapt: read whatever inputs the task
// needs, do the aggregation/join, write JSON or Markdown to stdout (or a
// ./scratch path).
// ponytail: minimal stub, not a framework — the aggregation logic is the
// task, not this file.

const args = process.argv.slice(2);

// TODO: read/parse `args` (file paths, JSON, etc.) and aggregate them.
const result = { args };

console.log(JSON.stringify(result, null, 2));
