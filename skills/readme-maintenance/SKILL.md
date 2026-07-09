---
name: readme-maintenance
description: Audit and refresh every README in the repo against a quality rubric, one reviewer subagent per workspace
---

# README Maintenance

## Purpose

Keep every README in the repo accurate, consistent, and free of stale references by reviewing them against a fixed quality rubric — one subagent per grouped-asset workspace (root, `skills/`, `suites/`, and any future workspace with a README). Each reviewer verifies every claim in its scope against the real file tree and applies surgical fixes directly, rather than just producing a critique nobody acts on.

## When to invoke

When the user wants to audit or clean up READMEs, after adding a new workspace or a batch of new assets, or as periodic maintenance. Triggers on `/readme-maintenance`, or phrases like "audit the READMEs", "check the READMEs are up to date", "clean up our READMEs".

Usage:

```
/readme-maintenance [workspace-filter]
```

**Arguments:**

- `[workspace-filter]` — Optional. Restrict the audit to one top-level workspace (e.g. `skills`, `suites`) instead of the whole repo.

---

## Rubric

Apply this checklist to every README in scope. It's synthesized from makeareadme.com, the standard-readme spec, awesome-readme, and GitHub's README docs — stable guidance, not re-derived from the web on every run. If the user explicitly asks for refreshed sourcing, fetch current versions of those and diff against this list before proceeding; otherwise use it as-is.

1. Open with the name and one clear sentence on what it is and why it exists — don't make the reader infer purpose from a directory listing.
2. Accuracy over aspiration: every path, filename, command, and table entry must match what's actually in the tree today. Verify with `ls`/`find`/`grep` — never trust the existing prose. Stale references are worse than missing ones.
3. Concrete usage: show the actual invocation/pattern, not just a description of what's possible.
4. Structure for scanning: predictable heading order, tables/lists for enumerable things.
5. State conventions once: link to the root README for cross-cutting conventions (naming, CHANGELOG format, `scripts/validate.sh`/`catalog.sh`) instead of duplicating them.
6. Right-sized: complete beats short, but don't pad. Cut sections that don't apply — this is a personal, single-maintainer asset monorepo with no LICENSE file, so no invented License/Badges/Build-status sections.
7. Family consistency: sibling workspace READMEs should share heading vocabulary and table shape wherever their content is parallel.
8. No dead weight: no speculative roadmap, no decorative badges or visuals that don't carry real information.

---

## Steps

### 1. Discover workspaces in scope

- List top-level directories: `find . -maxdepth 1 -type d -not -path . -not -path './.git'`.
- Keep only those with a `README.md` somewhere inside them; the repo root `README.md` counts as its own workspace.
- If `[workspace-filter]` was given, restrict to that one directory only (drop root from scope unless the filter is omitted).
- For each kept workspace, find every nested `README.md` under it (`find <workspace> -name README.md`) — these belong to the same reviewer as their parent, not a separate one.

### 2. Read the root README once

Read the repo root `README.md` yourself before dispatching anything — it's the source of the cross-cutting conventions (naming, CHANGELOG format, `scripts/validate.sh`/`catalog.sh`) every reviewer needs. Paste the relevant parts directly into each reviewer's prompt so they don't all redundantly re-read it.

### 3. Dispatch one reviewer per workspace

For each workspace, dispatch a subagent — one call per workspace, sent together so they run in parallel if the harness supports it — with:

- Its exact file scope: the workspace's `README.md` plus the nested `README.md` files found in step 1.
- The rubric above, verbatim.
- The relevant root-README conventions from step 2.
- Explicit instruction to verify every claim in its scope against the real repo (paths, filenames, commands, table entries) before editing — reading the existing prose is not verification.
- Instruction to make surgical edits directly: fix what's stale, wrong, or unclear; preserve what already matches house style; don't add sections that don't apply to this repo (License, Badges, Build status).
- Instruction to report — not fix — anything it finds outside its file scope (e.g. a problem in a sibling asset's own `SKILL.md`/`system.md`, not the README itself).
- Instruction to return a concise report: per file, what was wrong and what changed, under 200 words.

### 4. Wait for all reviewers, then verify

- Once every dispatched reviewer has reported back, run `bash scripts/validate.sh` to confirm no structural regression.
- Run `git diff --stat` to get the overall change footprint.

### 5. Report

- Synthesize each workspace's report into one summary for the user: per workspace, what was wrong and what changed.
- Surface, separately, any out-of-scope issues reviewers flagged (e.g. an over-length `SKILL.md` description, a dangling reference in a non-README file) — these need the user's decision, not a silent fix.
- Do not commit. Leave the changes in the working tree for the user to review with `git diff`.
