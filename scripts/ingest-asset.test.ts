import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isKebabCase, nextRoleNumber, insertTableRow, extractFrontmatterField, isMultiHarnessSuite } from './ingest-asset.ts';

test('isKebabCase accepts valid names', () => {
  assert.equal(isKebabCase('atomic-commits'), true);
  assert.equal(isKebabCase('a'), true);
  assert.equal(isKebabCase('a1-b2'), true);
});

test('isKebabCase rejects invalid names', () => {
  assert.equal(isKebabCase('Atomic-Commits'), false);
  assert.equal(isKebabCase('atomic_commits'), false);
  assert.equal(isKebabCase('atomic--commits'), false);
  assert.equal(isKebabCase('-atomic'), false);
  assert.equal(isKebabCase(''), false);
});

test('nextRoleNumber starts at 01 for an empty suite', () => {
  assert.equal(nextRoleNumber([]), '01');
});

test('nextRoleNumber increments past the highest existing prefix', () => {
  assert.equal(nextRoleNumber(['01-orchestrator.md', '02-planner.md', '07-scribe.md']), '08');
});

test('nextRoleNumber ignores non-numbered files', () => {
  assert.equal(nextRoleNumber(['00-shared-protocol.md', '01-orchestrator.md']), '02');
});

test('insertTableRow inserts alphabetically among existing rows', () => {
  const md = [
    '# skills/',
    '',
    '| Skill | Description |',
    '|-------|-------------|',
    '| [atomic-commits](atomic-commits/SKILL.md) | a |',
    '| [fix-validation](fix-validation/SKILL.md) | b |',
    '',
    '## Next section',
  ].join('\n');
  const updated = insertTableRow(md, '| Skill | Description |', '| [create-adr](create-adr/SKILL.md) | c |');
  const lines = updated.split('\n');
  assert.equal(lines[4], '| [atomic-commits](atomic-commits/SKILL.md) | a |');
  assert.equal(lines[5], '| [create-adr](create-adr/SKILL.md) | c |');
  assert.equal(lines[6], '| [fix-validation](fix-validation/SKILL.md) | b |');
  assert.equal(lines[8], '## Next section');
});

test('insertTableRow appends when the new row sorts last', () => {
  const md = ['| Skill | Description |', '|---|---|', '| [atomic-commits](x) | a |'].join('\n');
  const updated = insertTableRow(md, '| Skill | Description |', '| [yaml-frontmatter](y) | z |');
  assert.equal(updated.split('\n')[3], '| [yaml-frontmatter](y) | z |');
});

test('insertTableRow throws on a missing header', () => {
  assert.throws(() => insertTableRow('no tables here', '| Skill | Description |', '| [x](x) | y |'));
});

test('insertTableRow replaces an existing row for the same name instead of duplicating it', () => {
  const md = [
    '| Skill | Description |',
    '|-------|-------------|',
    '| [atomic-commits](atomic-commits/SKILL.md) | a |',
    '| [fix-validation](fix-validation/SKILL.md) | b |',
  ].join('\n');
  const updated = insertTableRow(md, '| Skill | Description |', '| [fix-validation](fix-validation/SKILL.md) | updated |');
  const lines = updated.split('\n');
  assert.equal(lines.length, 4);
  assert.equal(lines[3], '| [fix-validation](fix-validation/SKILL.md) | updated |');
});

test('extractFrontmatterField reads a field from a frontmatter block', () => {
  const content = '---\nname: foo\ndescription: bar baz\n---\n\nBody';
  assert.equal(extractFrontmatterField(content, 'name'), 'foo');
  assert.equal(extractFrontmatterField(content, 'description'), 'bar baz');
  assert.equal(extractFrontmatterField(content, 'missing'), '');
});

test('isMultiHarnessSuite is true when an entry matches a harness key', () => {
  const entries = ['README.md', 'USAGE.md', 'claude-code', 'copilot'];
  assert.equal(isMultiHarnessSuite(entries, ['claude-code', 'copilot']), true);
});

test('isMultiHarnessSuite is false for a flat suite with an agents/ dir', () => {
  const entries = ['README.md', 'USAGE.md', 'agents'];
  assert.equal(isMultiHarnessSuite(entries, ['claude-code', 'copilot']), false);
});
