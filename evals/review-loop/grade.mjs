// Collects facts from one eval run and grades them against the case's graders/ (node stdlib only).
//   node evals/review-loop/grade.mjs <arm-dir> [repo-dir]
// <arm-dir> is work/iteration-N/<case>/<with_skill|without_skill>/ and holds transcript.jsonl, scaffold-head.txt and
// wall.txt. With [repo-dir] (the run's fixture repo), facts.json, outputs/ and timing.json are (re)built first;
// without it, grading reuses facts.json, so graders can change after the temp repo is gone.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const [armDir, repo] = process.argv.slice(2);
if (!armDir) { console.error('usage: grade.mjs <arm-dir> [repo-dir]'); process.exit(64); }
// armDir is <case>/<arm> or, with repeats, <case>/<arm>/run-<i>
const parts = path.resolve(armDir).split(path.sep);
const ai = parts.findLastIndex(p => /^with(out)?_skill$/.test(p));
const caseName = parts[ai - 1], armName = parts[ai], caseDir = parts.slice(0, ai).join(path.sep);
const read = (f, d = '') => { try { return fs.readFileSync(f, 'utf8'); } catch { return d; } };
const run = (cmd, args, opts = {}) => spawnSync(cmd, args, { encoding: 'utf8', ...opts });

function role(desc = '', prompt = '') {
  const d = desc.toLowerCase(), p = prompt.slice(0, 600).toLowerCase();
  if (/\bfix/.test(d) || /you are fixing/.test(p)) return 'fixer';
  if (/review/.test(d) || /you are reviewing|code review|review (the|this)/.test(p)) return 'reviewer';
  return 'other';
}

function collect() {
  const events = read(path.join(armDir, 'transcript.jsonl')).split('\n')
    .map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
  const agents = [];
  for (const e of events) {
    if (e.type !== 'assistant' || e.parent_tool_use_id) continue;
    for (const c of e.message?.content ?? []) {
      if (c.type !== 'tool_use') continue;
      if (c.name === 'Agent' || c.name === 'Task') {
        const { description = '', prompt = '', model = 'inherit', subagent_type = '' } = c.input ?? {};
        agents.push({ kind: 'Agent', model, subagent_type, description, role: role(description, prompt), head: prompt.slice(0, 200) });
      } else if (c.name === 'SendMessage') {
        const text = JSON.stringify(c.input ?? {});
        agents.push({ kind: 'SendMessage', model: '(continued)', description: '', role: /review|round|verdict|resolved/i.test(text) ? 'reviewer' : 'other', head: text.slice(0, 200) });
      }
    }
  }
  const results = events.filter(e => e.type === 'result');
  const last = results.at(-1) ?? {};
  const text = [...results].reverse().find(r => String(r.result ?? '').trim())?.result ?? '';

  const git = (...a) => run('git', a, { cwd: repo }).stdout.trim();
  const head = read(path.join(armDir, 'scaffold-head.txt')).trim();
  const status = git('status', '--porcelain');
  const gitFacts = {
    branch: git('rev-parse', '--abbrev-ref', 'HEAD'),
    commitsAdded: Number(git('rev-list', '--count', `${head}..HEAD`)) || 0,
    clean: status === '', status,
  };

  const hidden = {};
  const h = run(process.execPath, ['--test', '--test-reporter=tap', path.join(HERE, 'fixtures/coupons/hidden.test.mjs')],
    { env: { ...process.env, TARGET: repo } });
  for (const m of (h.stdout ?? '').matchAll(/^\s*(not )?ok \d+ - (.+?)\s*$/gm)) hidden[m[2]] = !m[1];
  const npmTest = run(process.execPath, ['--test'], { cwd: repo }).status === 0;

  const src = read(path.join(repo, 'src/coupons.js'));
  const names = [];
  for (const m of src.matchAll(/^import\s+(.+?)\s+from\s+['"][^'"]+['"]/gm)) {
    for (const part of m[1].replace(/[{}]/g, ',').split(',')) {
      const n = part.trim().split(/\s+as\s+/).pop().trim();
      if (n && n !== '*') names.push(n);
    }
  }
  const code = src.replace(/^import\s.*$/gm, '');
  const unusedImports = names.filter(n => !new RegExp(`\\b${n}\\b`).test(code));
  const testDir = path.join(repo, 'test');
  const couponTests = fs.existsSync(testDir) && fs.readdirSync(testDir, { recursive: true })
    .some(f => read(path.join(testDir, String(f))).includes('applyCoupon'));

  const [start, end] = read(path.join(armDir, 'wall.txt')).trim().split(/\s+/).map(Number);
  const facts = {
    case: caseName, arm: armName, text, agents, git: gitFacts, hidden, npmTest, unusedImports, couponTests,
    cost: last.total_cost_usd ?? null, modelUsage: last.modelUsage ?? {}, subagentStats: last.subagent_stats ?? null,
    terminal: { subtype: last.subtype ?? null, is_error: last.is_error ?? null, terminal_reason: last.terminal_reason ?? null },
    wallSeconds: end && start ? end - start : null,
  };
  fs.writeFileSync(path.join(armDir, 'facts.json'), JSON.stringify(facts, null, 2) + '\n');

  const out = path.join(armDir, 'outputs');
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, 'final-reply.md'), text + '\n');
  const cell = s => String(s).replace(/\s+/g, ' ').replace(/\|/g, '\\|');
  fs.writeFileSync(path.join(out, 'agent-calls.md'), ['| # | Call | Role (heuristic) | Model | Description | Prompt start |', '|---|---|---|---|---|---|',
    ...agents.map((a, i) => `| ${i + 1} | ${a.kind} | ${a.role} | ${a.model} | ${cell(a.description)} | ${cell(a.head.slice(0, 140))} |`)].join('\n') + '\n');
  fs.writeFileSync(path.join(out, 'git-log.txt'), git('log', '--format=%h %s%n%b', `${head}~1..HEAD`) + '\n\nstatus:\n' + (status || '(clean)') + '\n');
  fs.writeFileSync(path.join(out, 'branch-diff.txt'), git('diff', 'main...HEAD') + '\n');
  const usage = Object.entries(facts.modelUsage).map(([m, u]) => `- ${m}: $${(u.costUSD ?? 0).toFixed(2)}, ${u.outputTokens ?? 0} output tokens`);
  fs.writeFileSync(path.join(out, 'checks.md'), [
    '## Hidden behaviour checks', ...Object.entries(hidden).map(([k, v]) => `- ${v ? 'PASS' : 'FAIL'} ${k}`),
    '', `## Repo state`, `- node --test: ${npmTest ? 'pass' : 'FAIL'}`, `- unused imports in src/coupons.js: ${unusedImports.join(', ') || 'none'}`,
    `- test file mentions applyCoupon: ${couponTests}`, `- branch ${gitFacts.branch}, ${gitFacts.commitsAdded} commits added, tree ${gitFacts.clean ? 'clean' : 'DIRTY'}`,
    '', '## Run', `- cost $${facts.cost}, wall ${facts.wallSeconds}s, ${JSON.stringify(facts.terminal)}`, ...usage,
    `- subagent stats: ${JSON.stringify(facts.subagentStats)}`,
  ].join('\n') + '\n');

  const tok = Object.values(facts.modelUsage).reduce((s, u) => s + (u.inputTokens ?? 0) + (u.outputTokens ?? 0)
    + (u.cacheReadInputTokens ?? 0) + (u.cacheCreationInputTokens ?? 0), 0);
  fs.writeFileSync(path.join(armDir, 'timing.json'), JSON.stringify({
    total_tokens: tok, duration_ms: (facts.wallSeconds ?? 0) * 1000, total_duration_seconds: facts.wallSeconds ?? 0, total_cost_usd: facts.cost,
  }, null, 2) + '\n');
  return facts;
}

const f = repo ? collect() : JSON.parse(read(path.join(armDir, 'facts.json'), 'null'));
if (!f) { console.error(`grade.mjs: no facts.json in ${armDir}; pass the repo dir`); process.exit(3); }

const eff = m => (m === 'inherit' ? 'opus' : m);
const reviewerAgents = f.agents.filter(a => a.kind === 'Agent' && a.role === 'reviewer');
const reviews = f.agents.filter(a => a.role === 'reviewer').length;
const fixers = f.agents.filter(a => a.kind === 'Agent' && a.role === 'fixer');
const H = f.hidden, hk = Object.keys(H), allHidden = hk.length === 5 && hk.every(k => H[k]);
const models = list => list.map(a => eff(a.model)).join(', ') || 'none';
const verdict = /\bSATISFIED\b|not satisfied/i.test(f.text);
const satisfied = /\bSATISFIED\b/.test(f.text) && !/NOT SATISFIED|not satisfied/i.test(f.text);
const committed = f.git.commitsAdded > 0 && f.git.clean && f.git.branch === 'feature/coupons';

const checks = {
  'o-expiry-fixed': () => [H['expiry: a valid coupon applies'] && H['expiry: an expired coupon is ignored'], JSON.stringify(H)],
  'o-case-insensitive': () => [!!H['case: lowercase codes work'], JSON.stringify(H)],
  'o-integer-cents': () => [!!H['cents: the result is always an integer'], JSON.stringify(H)],
  'o-typo-fixed': () => [!!H['typo: unknown code message says Invalid'], JSON.stringify(H)],
  'o-unused-imports': () => [f.unusedImports.length === 0, `unused: ${f.unusedImports.join(', ') || 'none'}`],
  'o-coupon-tests': () => [f.couponTests && f.npmTest, `test mentions applyCoupon: ${f.couponTests}; node --test passes: ${f.npmTest}`],
  'o-opus-reviewer': () => [reviewerAgents.length > 0 && reviewerAgents.every(a => eff(a.model) === 'opus'), `reviewer agents: ${models(reviewerAgents)}`],
  'o-sonnet-reviewer': () => [reviewerAgents.length > 0 && reviewerAgents.every(a => eff(a.model) === 'sonnet'), `reviewer agents: ${models(reviewerAgents)}`],
  'o-tiered-fixers': () => [fixers.some(a => eff(a.model) === 'haiku') && fixers.some(a => eff(a.model) === 'sonnet') && !fixers.some(a => eff(a.model) === 'opus'), `fixer agents: ${models(fixers)}`],
  'o-no-haiku': () => [!f.agents.some(a => a.kind === 'Agent' && eff(a.model) === 'haiku'), `all agents: ${models(f.agents.filter(a => a.kind === 'Agent'))}`],
  'o-sonnet-fixers': () => [fixers.length > 0 && fixers.every(a => eff(a.model) === 'sonnet'), `fixer agents: ${models(fixers)}`],
  'o-behaviour-fixed': () => [allHidden, JSON.stringify(H)],
  'o-no-churn': () => [reviews <= 2 && allHidden, `reviews: ${reviews}; hidden all pass: ${allHidden}`],
  'o-verdict-reported': () => [verdict, f.text.slice(0, 160)],
  'o-satisfied': () => [satisfied, f.text.slice(0, 160)],
  's-committed-clean': () => [committed, `${f.git.commitsAdded} commits on ${f.git.branch}, tree ${f.git.clean ? 'clean' : 'dirty: ' + f.git.status}`],
  's-clean-tree': () => [f.git.clean, f.git.clean ? 'clean' : f.git.status],
  's-round-cap': t => { const cap = Number(/at most (\d+) fix rounds/.exec(t)[1]); return [reviews <= cap + 1, `reviews (Agent + SendMessage): ${reviews}, cap ${cap}`]; },
};

const gdir = path.join(HERE, 'cases', caseName, 'graders');
const expectations = fs.readdirSync(gdir).filter(n => n.endsWith('.md')).sort().map(n => {
  const textBody = read(path.join(gdir, n)).split(/^---$/m).slice(2).join('---').trim();
  const key = n.replace(/^\d+-/, '').replace(/\.md$/, '');
  if (!checks[key]) return { text: textBody, passed: false, evidence: `no scripted check for ${key}` };
  const [passed, evidence] = checks[key](textBody);
  return { text: textBody, passed: !!passed, evidence };
});
const passed = expectations.filter(e => e.passed).length;
fs.writeFileSync(path.join(armDir, 'grading.json'), JSON.stringify({
  expectations,
  summary: { passed, failed: expectations.length - passed, total: expectations.length, pass_rate: +(passed / expectations.length).toFixed(2) },
}, null, 2) + '\n');

const body = read(path.join(HERE, 'cases', caseName, 'prompt.md')).split(/^---$/m).slice(2).join('---').trim();
fs.writeFileSync(path.join(caseDir, 'eval_metadata.json'), JSON.stringify({
  eval_name: caseName, prompt: body, assertions: expectations.map(e => e.text),
}, null, 2) + '\n');
console.log(`${caseName}/${f.arm}: ${passed}/${expectations.length} · $${f.cost} · ${f.wallSeconds}s`);
