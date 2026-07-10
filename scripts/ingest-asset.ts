import { query } from '@anthropic-ai/claude-agent-sdk';
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// ---------- pure helpers (unit-tested in ingest-asset.test.ts) ----------

export function isKebabCase(s: string): boolean {
  return /^[a-z0-9]+(-[a-z0-9]+)*$/.test(s);
}

export function nextRoleNumber(existingFiles: string[]): string {
  const nums = existingFiles
    .map((f) => /^(\d{2})-/.exec(f))
    .filter((m): m is RegExpExecArray => m !== null)
    .map((m) => parseInt(m[1], 10));
  const next = nums.length ? Math.max(...nums) + 1 : 1;
  return String(next).padStart(2, '0');
}

export function extractFrontmatterField(content: string, field: string): string {
  const block = /^---\n([\s\S]*?)\n---/.exec(content);
  if (!block) return '';
  const line = block[1].split('\n').find((l) => l.startsWith(`${field}:`));
  return line ? line.slice(field.length + 1).trim() : '';
}

export function isMultiHarnessSuite(entries: string[], harnessKeys: string[]): boolean {
  return entries.some((e) => harnessKeys.includes(e));
}

export function insertTableRow(markdown: string, headerLine: string, newRow: string): string {
  const lines = markdown.split('\n');
  const headerIdx = lines.findIndex((l) => l.trim() === headerLine.trim());
  if (headerIdx === -1) throw new Error(`Table header not found: ${headerLine}`);
  const sepIdx = headerIdx + 1;
  let end = sepIdx + 1;
  while (end < lines.length && lines[end].trim().startsWith('|')) end++;
  const dataRows = lines.slice(sepIdx + 1, end);

  const nameOf = (row: string) => {
    const m = /\[([^\]]+)\]/.exec(row);
    return m ? m[1] : row;
  };
  const newName = nameOf(newRow);
  const dedupedRows = dataRows.filter((row) => nameOf(row) !== newName);
  let insertAt = dedupedRows.length;
  for (let i = 0; i < dedupedRows.length; i++) {
    if (nameOf(dedupedRows[i]).localeCompare(newName) > 0) {
      insertAt = i;
      break;
    }
  }
  dedupedRows.splice(insertAt, 0, newRow);
  return [...lines.slice(0, sepIdx + 1), ...dedupedRows, ...lines.slice(end)].join('\n');
}

// ---------- repo context digest (deterministic, no LLM) ----------

function buildDigest(): string {
  const skillsDir = path.join(REPO_ROOT, 'skills');
  const skills = readdirSync(skillsDir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !d.name.startsWith('_'))
    .map((d) => {
      const skillMd = readFileSync(path.join(skillsDir, d.name, 'SKILL.md'), 'utf8');
      return { name: d.name, description: extractFrontmatterField(skillMd, 'description') };
    });

  const suitesDir = path.join(REPO_ROOT, 'suites');
  const suites = readdirSync(suitesDir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !d.name.startsWith('_'))
    .map((d) => {
      const suiteDir = path.join(suitesDir, d.name);
      const readmePath = path.join(suiteDir, 'README.md');
      const firstLine = existsSync(readmePath)
        ? (readFileSync(readmePath, 'utf8').split('\n').find((l) => l.trim()) ?? '')
        : '';
      const agentsDir = path.join(suiteDir, 'agents');
      const roles = existsSync(agentsDir)
        ? readdirSync(agentsDir)
            .filter((f) => f.endsWith('.md'))
            .sort()
            .map((f) => {
              const fm = readFileSync(path.join(agentsDir, f), 'utf8');
              return {
                file: f,
                name: extractFrontmatterField(fm, 'name'),
                description: extractFrontmatterField(fm, 'description'),
              };
            })
        : [];
      return { name: d.name, firstLine, roles };
    });

  return JSON.stringify({ skills, suites }, null, 2);
}

// ---------- LLM calls ----------

const ROLE_FRONTMATTER_EXAMPLES = `Example 1 (suites/hub-and-spoke-orchestration/agents/01-orchestrator.md):
---
name: orchestrator
description: Owns the loop counter and routes every agent by its emitted status; invokes the merge gate on green; escalates to the Arbiter on k-trip
model: claude-sonnet-5
tools: [dispatch-agent, merge-gate]
agents: [planner, explorer, coder, executor, reviewer, arbiter, scribe]
user-invocable: true
argument-hint: Goal statement, repo pointer, trunk ref, config (k-trip threshold and dispatch cap); receives worker results keyed by status and routes deterministically
disable-model-invocation: true
---

Example 2 (suites/tiered-team-orchestration/agents/01-core-orchestrator.md):
---
name: core-orchestrator
description: Owns the goal end to end; plans, decomposes into team assignments, and routes to tiered leads without touching files or commands itself
model: claude-opus-4-8
tools: [dispatch-agent]
agents: [research-lead, coding-lead, review-lead]
user-invocable: true
argument-hint: Goal statement, repo pointer, and constraints; receives each lead's synthesized result and decides the next dispatch or DONE/ESCALATE
disable-model-invocation: true
---

The body after the frontmatter is the role's persona and procedure: what it owns, what it must
never do, how it reads inputs from the roles that dispatch to it, and what it hands back (status
keyword, payload shape) to whichever role dispatches it.`;

const CLASSIFY_SCHEMA = {
  type: 'object',
  properties: {
    category: { enum: ['skill', 'suite-component', 'unsupported'] },
    reason: { type: 'string' },
    proposed_name: { type: 'string' },
    target_suite: { type: 'string' },
    target_suite_is_new: { type: 'boolean' },
  },
  required: ['category', 'reason', 'proposed_name', 'target_suite', 'target_suite_is_new'],
};

const SKILL_GEN_SCHEMA = {
  type: 'object',
  properties: {
    description: { type: 'string' },
    skill_md_body: { type: 'string' },
    usage_md: { type: 'string' },
    top_level_summary: { type: 'string' },
    harness: { enum: ['vendor-agnostic', 'this repo'] },
  },
  required: ['description', 'skill_md_body', 'usage_md', 'top_level_summary', 'harness'],
};

const SUITE_COMPONENT_GEN_SCHEMA = {
  type: 'object',
  properties: {
    description: { type: 'string' },
    model: { enum: ['claude-opus-4-8', 'claude-sonnet-5', 'claude-haiku-4-5-20251001'] },
    tools: { type: 'array', items: { type: 'string' } },
    agents: { type: 'array', items: { type: 'string' } },
    user_invocable: { type: 'boolean' },
    argument_hint: { type: 'string' },
    disable_model_invocation: { type: 'boolean' },
    role_md_body: { type: 'string' },
    suite_readme: { type: 'string' },
    suite_usage: { type: 'string' },
    suite_top_level_summary: { type: 'string' },
    suite_harness: { type: 'string' },
  },
  required: [
    'description',
    'model',
    'tools',
    'agents',
    'user_invocable',
    'argument_hint',
    'disable_model_invocation',
    'role_md_body',
  ],
};

async function runQuery(systemPrompt: string, prompt: string, schema: Record<string, unknown>, model: string): Promise<any> {
  let structured: unknown;
  let lastText = '';
  for await (const message of query({
    prompt,
    options: {
      systemPrompt,
      model,
      outputFormat: { type: 'json_schema', schema },
      settingSources: [],
      allowedTools: ['Read', 'Glob', 'Grep'],
      cwd: REPO_ROOT,
      maxTurns: 20,
    },
  }) as any) {
    if (message.type === 'result') {
      if (message.subtype === 'success') {
        structured = message.structured_output;
        lastText = message.result;
      } else {
        throw new Error(`Claude query failed (${message.subtype}): ${(message.errors ?? []).join('; ') || 'no details'}`);
      }
    }
  }
  if (structured === undefined) {
    throw new Error(`No structured output returned. Raw result: ${lastText}`);
  }
  return structured;
}

async function classify(sourceContent: string, digest: string, model: string): Promise<any> {
  const systemPrompt = `You are classifying a source file for ingestion into "ai-personal", a Claude Code asset repo.

Repo taxonomy:
- "skill" = a standalone, independently-invocable procedure. Lives at skills/{name}/SKILL.md. Something a user or agent runs on demand for a bounded task (e.g. "write commit messages", "create an ADR").
- "suite-component" = a single agent/role definition meant to be dispatched as one spoke in a multi-agent orchestration system. Not independently invocable by a user; only makes sense as part of a set (references or is referenced by sibling roles, has a narrow persona like "orchestrator"/"planner"/"reviewer"/"worker"). Lives at suites/{suite-name}/agents/NN-{role-name}.md.
- "unsupported" = the input isn't a usable prompt/skill/agent-definition at all (unrelated prose, empty, too ambiguous to name confidently). Always explain why in "reason".

Existing assets in this repo (JSON digest):
${digest}

Decide the category. If suite-component, decide target_suite: reuse an EXACT existing suite name from the digest if the input's persona/role clearly belongs alongside its existing roles, otherwise propose a new kebab-case suite name and set target_suite_is_new=true. If skill, leave target_suite as an empty string and target_suite_is_new=false.

proposed_name must be kebab-case (lowercase letters, digits, single hyphens between words), matching this repo's naming convention, and must not collide with an existing name in the digest unless you intend to extend an existing suite with a new role.`;

  const prompt = `Source file to classify:\n---\n${sourceContent}\n---`;
  return runQuery(systemPrompt, prompt, CLASSIFY_SCHEMA, model);
}

async function generateSkill(sourceContent: string, name: string, model: string): Promise<any> {
  const skillExample = readFileSync(path.join(REPO_ROOT, 'skills/fix-validation/SKILL.md'), 'utf8');
  const systemPrompt = `You are generating a new skill for the "ai-personal" Claude Code asset repo, to be written at skills/${name}/.

Repo conventions (follow exactly):
- SKILL.md frontmatter is exactly two fields: name, description. description must be a single line, under 120 characters, no colon, no wrapping quotes.
- skill_md_body is everything AFTER the frontmatter block — do NOT include the "---\nname: ...\n---" lines yourself, the caller assembles those separately. Start skill_md_body directly with "# Title" then "## Purpose".
- skill_md_body follows the real example below: a "# Title" heading, "## Purpose" section, a "## When to invoke" section (trigger phrases + a usage line showing the slash-command form and its arguments), then "## Steps" (a numbered procedure).
- usage_md gives invocation guidance (trigger phrases) and one worked example, distinct from SKILL.md's procedure.
- top_level_summary is ONE sentence (not multiple), comparable in length to description, reused verbatim in two workspace index tables — it must read naturally as a single table cell, not a paragraph.
- harness is "vendor-agnostic" unless this skill can ONLY operate on the ai-personal repo's own structure (e.g. it shells out to this repo's own scripts/validate.sh or edits this repo's own docs/adrs/ index) — that is rare. Default to "vendor-agnostic" for anything that would work the same in any project (like the real example below, which still gets "this repo" only because it hardcodes scripts/validate.sh).
- Do not generate a CHANGELOG.md — the caller creates it with a header only, per convention (new skills start with an empty log, never a fabricated entry).

Real example SKILL.md for reference (note its frontmatter is shown only so you match the body's tone/structure — do not repeat frontmatter lines in your own skill_md_body):
${skillExample}`;

  const prompt = `Source content to turn into a skill named "${name}":\n---\n${sourceContent}\n---`;
  return runQuery(systemPrompt, prompt, SKILL_GEN_SCHEMA, model);
}

async function generateSuiteComponent(
  sourceContent: string,
  roleName: string,
  suite: string,
  isNew: boolean,
  existingRosterDigest: string,
  model: string,
): Promise<any> {
  const systemPrompt = `You are generating one role/agent prompt file for the "ai-personal" Claude Code asset repo, to be written at suites/${suite}/agents/NN-${roleName}.md (the NN prefix is assigned by the caller, not you).

Repo conventions (follow exactly) — role frontmatter has exactly these 8 fields, bare-word YAML arrays (no quotes), no trailing period on description/argument-hint:
name, description, model (one of: claude-opus-4-8, claude-sonnet-5, claude-haiku-4-5-20251001 — pick by role complexity/cost tier), tools (array of tool names), agents (array of OTHER role names in this suite this role can dispatch to; empty array if this is a leaf worker), user-invocable (boolean), argument-hint (string), disable-model-invocation (boolean).

role_md_body is everything AFTER the frontmatter block — do NOT include the "---\nname: ...\n---" lines yourself, the caller assembles those separately from the other fields you return. Start role_md_body directly with the role's persona/procedure prose.

${ROLE_FRONTMATTER_EXAMPLES}

${
  isNew
    ? `This is the FIRST role of a brand-new suite named "${suite}". Also produce suite_readme (full suites/${suite}/README.md content: what the suite does, the role of each component, the entry point) and suite_usage (full suites/${suite}/USAGE.md content: how to invoke it, step-by-step, with a worked example), plus suite_top_level_summary (ONE sentence for an index table, comparable in length to description — not a paragraph) and suite_harness (one short label, e.g. "Claude Code").`
    : `This role joins the EXISTING suite "${suite}". Its current roster:\n${existingRosterDigest}\n\nKeep this role's agents: cross-references and tone consistent with its siblings. Do not produce suite_readme/suite_usage/suite_top_level_summary/suite_harness — leave them out.`
}`;

  const prompt = `Source content to turn into a role definition named "${roleName}":\n---\n${sourceContent}\n---`;
  return runQuery(systemPrompt, prompt, SUITE_COMPONENT_GEN_SCHEMA, model);
}

// ---------- deterministic write layer ----------

function runValidate(): void {
  console.log('\nRunning scripts/validate.sh...');
  try {
    const out = execFileSync('bash', ['scripts/validate.sh'], { cwd: REPO_ROOT, encoding: 'utf8' });
    console.log(out);
  } catch (err: any) {
    console.log(err.stdout ?? '');
    console.error(err.stderr ?? '');
    console.error('validate.sh reported failures — review before committing.');
  }
}

async function handleSkill(
  classification: any,
  sourceContent: string,
  model: string,
  dryRun: boolean,
  force: boolean,
): Promise<void> {
  const name = classification.proposed_name;
  const skillDir = path.join(REPO_ROOT, 'skills', name);
  if (existsSync(skillDir) && !force) {
    console.error(`skills/${name}/ already exists. Re-run with --force to overwrite, or --name to pick a different name.`);
    process.exit(1);
  }

  const generated = await generateSkill(sourceContent, name, model);

  const skillMd = `---\nname: ${name}\ndescription: ${generated.description}\n---\n\n${generated.skill_md_body.trim()}\n`;
  const usageMd = `${generated.usage_md.trim()}\n`;
  const changelogMd = '# Changelog\n\nFormat: `YYYY-MM-DD · {model-version} · {what changed and why}`\n';

  const files: Array<[string, string]> = [
    [path.join(skillDir, 'SKILL.md'), skillMd],
    [path.join(skillDir, 'USAGE.md'), usageMd],
    [path.join(skillDir, 'CHANGELOG.md'), changelogMd],
  ];

  const tableEdits = [
    {
      file: path.join(REPO_ROOT, 'skills/README.md'),
      header: '| Skill | Description |',
      row: `| [${name}](${name}/SKILL.md) | ${generated.description} |`,
    },
    {
      file: path.join(REPO_ROOT, 'skills/USAGE.md'),
      header: '| Skill | Description | Usage guide |',
      row: `| [${name}](${name}/SKILL.md) | ${generated.top_level_summary} | [USAGE.md](${name}/USAGE.md) |`,
    },
    {
      file: path.join(REPO_ROOT, 'README.md'),
      header: '| Skill | What it does | Harness |',
      row: `| [${name}](skills/${name}/SKILL.md) | ${generated.top_level_summary} | ${generated.harness} |`,
    },
  ];

  if (dryRun) {
    console.log('\n--- DRY RUN: files that would be written ---');
    for (const [file, content] of files) console.log(`\n# ${path.relative(REPO_ROOT, file)}\n${content}`);
    console.log('\n--- DRY RUN: table rows that would be inserted ---');
    for (const e of tableEdits) console.log(`${path.relative(REPO_ROOT, e.file)}: ${e.row}`);
    return;
  }

  mkdirSync(skillDir, { recursive: true });
  for (const [file, content] of files) writeFileSync(file, content);
  for (const e of tableEdits) {
    const md = readFileSync(e.file, 'utf8');
    writeFileSync(e.file, insertTableRow(md, e.header, e.row));
  }

  console.log(`\nWrote skills/${name}/ (SKILL.md, USAGE.md, CHANGELOG.md) and updated 3 README tables.`);
}

async function handleSuiteComponent(
  classification: any,
  sourceContent: string,
  model: string,
  dryRun: boolean,
  force: boolean,
): Promise<void> {
  const suite = classification.target_suite;
  const isNew = classification.target_suite_is_new;
  const suiteDir = path.join(REPO_ROOT, 'suites', suite);
  const agentsDir = path.join(suiteDir, 'agents');

  if (isNew && existsSync(suiteDir) && !force) {
    console.error(
      `suites/${suite}/ already exists but classification said "new". Re-run with --suite ${suite} to target it as an existing suite, or --force.`,
    );
    process.exit(1);
  }
  if (!isNew && !existsSync(suiteDir)) {
    console.error(`suites/${suite}/ does not exist but classification said "existing". Re-run with --suite <name> to fix.`);
    process.exit(1);
  }

  if (existsSync(suiteDir)) {
    const harnessKeys = Object.keys(JSON.parse(readFileSync(path.join(REPO_ROOT, 'scripts/harnesses.json'), 'utf8')));
    if (isMultiHarnessSuite(readdirSync(suiteDir), harnessKeys)) {
      console.error(
        `suites/${suite}/ is a multi-harness suite (ADR-0006) — ingest-asset does not support writing into it. Place the component manually in the correct variant subdirectory.`,
      );
      process.exit(1);
    }
  }

  const roleName = classification.proposed_name;
  const existingFiles = existsSync(agentsDir) ? readdirSync(agentsDir).filter((f) => f.endsWith('.md')) : [];
  const collidingFile = existingFiles.find(
    (f) => extractFrontmatterField(readFileSync(path.join(agentsDir, f), 'utf8'), 'name') === roleName,
  );
  if (collidingFile && !force) {
    console.error(`A role named "${roleName}" already exists in suites/${suite}/agents/. Re-run with --name to pick a different role name, or --force.`);
    process.exit(1);
  }
  const roleFile = collidingFile
    ? path.join(agentsDir, collidingFile)
    : path.join(agentsDir, `${nextRoleNumber(existingFiles)}-${roleName}.md`);

  let existingRosterDigest = '';
  if (!isNew) {
    existingRosterDigest = existingFiles
      .sort()
      .map((f) => {
        const fm = readFileSync(path.join(agentsDir, f), 'utf8');
        return `- ${f}: name=${extractFrontmatterField(fm, 'name')}, description=${extractFrontmatterField(fm, 'description')}`;
      })
      .join('\n');
  }

  const generated = await generateSuiteComponent(sourceContent, roleName, suite, isNew, existingRosterDigest, model);

  const frontmatter = [
    '---',
    `name: ${roleName}`,
    `description: ${generated.description}`,
    `model: ${generated.model}`,
    `tools: [${generated.tools.join(', ')}]`,
    `agents: [${generated.agents.join(', ')}]`,
    `user-invocable: ${generated.user_invocable}`,
    `argument-hint: ${generated.argument_hint}`,
    `disable-model-invocation: ${generated.disable_model_invocation}`,
    '---',
    '',
  ].join('\n');
  const roleMd = frontmatter + generated.role_md_body.trim() + '\n';

  const files: Array<[string, string]> = [[roleFile, roleMd]];
  const tableEdits: Array<{ file: string; header: string; row: string }> = [];

  if (isNew) {
    files.push([path.join(suiteDir, 'README.md'), `${generated.suite_readme.trim()}\n`]);
    files.push([path.join(suiteDir, 'USAGE.md'), `${generated.suite_usage.trim()}\n`]);
    tableEdits.push(
      {
        file: path.join(REPO_ROOT, 'suites/README.md'),
        header: '| Suite | Description |',
        row: `| [${suite}](${suite}/README.md) | ${generated.suite_top_level_summary} |`,
      },
      {
        file: path.join(REPO_ROOT, 'suites/USAGE.md'),
        header: '| Asset | One-line description | Usage guide |',
        row: `| [${suite}](${suite}/README.md) | ${generated.suite_top_level_summary} | [USAGE.md](${suite}/USAGE.md) |`,
      },
      {
        file: path.join(REPO_ROOT, 'README.md'),
        header: '| Suite | What it does | Harness |',
        row: `| [${suite}](suites/${suite}/README.md) | ${generated.suite_top_level_summary} | ${generated.suite_harness} |`,
      },
    );
  }

  if (dryRun) {
    console.log('\n--- DRY RUN: files that would be written ---');
    for (const [file, content] of files) console.log(`\n# ${path.relative(REPO_ROOT, file)}\n${content}`);
    if (tableEdits.length) {
      console.log('\n--- DRY RUN: table rows that would be inserted ---');
      for (const e of tableEdits) console.log(`${path.relative(REPO_ROOT, e.file)}: ${e.row}`);
    }
    if (!isNew) {
      console.log(
        `\nReminder: suites/${suite}/README.md and USAGE.md are NOT auto-updated for existing suites — review/update their "role of each component" prose by hand.`,
      );
    }
    return;
  }

  mkdirSync(agentsDir, { recursive: true });
  for (const [file, content] of files) writeFileSync(file, content);
  for (const e of tableEdits) {
    const md = readFileSync(e.file, 'utf8');
    writeFileSync(e.file, insertTableRow(md, e.header, e.row));
  }

  console.log(
    `\nWrote suites/${suite}/agents/${path.basename(roleFile)}${isNew ? ' plus a new suite README.md/USAGE.md and 3 index table rows' : ''}.`,
  );
  if (!isNew) {
    console.log(
      `Reminder: suites/${suite}/README.md and USAGE.md are NOT auto-updated — review/update their "role of each component" prose by hand (or via /readme-maintenance).`,
    );
  }
}

// ---------- CLI ----------

function printUsageAndExit(): never {
  console.error(
    'Usage: node scripts/ingest-asset.ts <path-to-source-file> [--name <kebab-case>] [--suite <name>] [--dry-run] [--force] [--model <alias>]',
  );
  process.exit(1);
}

function parseArgs(argv: string[]) {
  const [sourcePath, ...rest] = argv;
  if (!sourcePath || sourcePath.startsWith('--')) printUsageAndExit();

  const opts = { name: undefined as string | undefined, suite: undefined as string | undefined, dryRun: false, force: false, model: 'sonnet' };
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === '--name') {
      if (++i >= rest.length) printUsageAndExit();
      opts.name = rest[i];
    } else if (a === '--suite') {
      if (++i >= rest.length) printUsageAndExit();
      opts.suite = rest[i];
    } else if (a === '--dry-run') {
      opts.dryRun = true;
    } else if (a === '--force') {
      opts.force = true;
    } else if (a === '--model') {
      if (++i >= rest.length) printUsageAndExit();
      opts.model = rest[i];
    } else {
      console.error(`Unknown flag: ${a}`);
      printUsageAndExit();
    }
  }
  return { sourcePath: sourcePath as string, ...opts };
}

async function main(): Promise<void> {
  const { sourcePath, name: nameOverride, suite: suiteOverride, dryRun, force, model } = parseArgs(process.argv.slice(2));

  const resolvedSource = path.resolve(sourcePath);
  if (!existsSync(resolvedSource)) {
    console.error(`Source file not found: ${resolvedSource}`);
    process.exit(1);
  }
  const sourceContent = readFileSync(resolvedSource, 'utf8');
  if (!sourceContent.trim()) {
    console.error('Source file is empty.');
    process.exit(1);
  }

  if (!existsSync(path.join(REPO_ROOT, 'scripts/validate.sh'))) {
    console.error(`Could not find scripts/validate.sh under ${REPO_ROOT} — is this running inside the ai-personal repo?`);
    process.exit(1);
  }

  const digest = buildDigest();
  const classification = await classify(sourceContent, digest, model);

  if (nameOverride) classification.proposed_name = nameOverride;
  if (suiteOverride) {
    if (classification.category !== 'unsupported') classification.category = 'suite-component';
    classification.target_suite = suiteOverride;
    classification.target_suite_is_new = !existsSync(path.join(REPO_ROOT, 'suites', suiteOverride));
  }

  if (classification.category === 'unsupported') {
    console.error(`Not ingestable: ${classification.reason}`);
    process.exit(1);
  }

  if (!isKebabCase(classification.proposed_name)) {
    console.error(`Proposed name "${classification.proposed_name}" is not kebab-case. Re-run with --name <kebab-case>.`);
    process.exit(1);
  }

  console.log(
    `Classified as: ${classification.category} → "${classification.proposed_name}"` +
      (classification.category === 'suite-component'
        ? ` in suite "${classification.target_suite}"${classification.target_suite_is_new ? ' (new)' : ''}`
        : ''),
  );
  console.log(classification.reason);

  if (classification.category === 'skill') {
    await handleSkill(classification, sourceContent, model, dryRun, force);
  } else {
    await handleSuiteComponent(classification, sourceContent, model, dryRun, force);
  }

  if (dryRun) {
    console.log('\nDry run — nothing was written.');
    return;
  }

  runValidate();
  console.log('\nNothing was committed. Review with `git diff`/`git status`, then commit (e.g. via the atomic-commits skill) if it looks right.');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(err instanceof Error ? err.message : err);
    process.exit(1);
  });
}
