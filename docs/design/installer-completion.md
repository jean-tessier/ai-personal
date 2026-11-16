---
date: 2026-11-15
description: Design for finishing install.sh, with translate as data, ADR-0008 placements, install record, uninstall, --ref, tests
status: implemented
tags: [installer, design, harnesses]
---

# Installer completion — design

**Status:** accepted 2026-11-15; every owner question is decided (see [Decisions](#10-decisions)).
Nothing here is built yet. The slice plan lives in the DAG file
`.claude/state/installer-completion-dag.md` (git-excluded). Checked read-only on 2026-11-15 against
`main` at `918c6d8`.

**Labels used below:** **[D#n]** is from `docs/memory/deferred-items.md` row *n*; **[gap]** was
found while reading for this design and is not in the tracker yet.

## 1. Current state (verified)

| Fact | Evidence |
|---|---|
| `install.sh` is merged and green: 21 test functions, 59 assertions, all passing | `bash scripts/test-install.sh` → `59 passed, 0 skipped` (78 s locally) |
| `main` is the release channel. `curl …/main/install.sh \| bash` fetches `main`'s tree, so every merge ships to users right away | `install.sh:25-27` (`REF="main"`), `fetch_source()` |
| Branch protection: two required checks (`validate, test, typecheck`, `installer behavioral tests`), must be up to date, 0 approvals, conversations resolved | `gh api …/branches/main/protection` |
| `make check` does **not** run `scripts/test-install.sh`. CI runs it as a separate job | `Makefile`, `.github/workflows/ci.yml` |
| **[D#9]** The Copilot translation gate is hardcoded in one helper (`is_copilot_suite_category`, `install.sh:41`) and called from 3 places (`:342`, `:497`, `:515`) | source |
| **[gap] Latent bug:** `resolve_dependencies()` pass 2 (`install.sh:422-435`) checks only `mapping`. It skips the per-item plugin-shaped filter that `select_assets()` applies. For `--harness copilot`, a dependency on a non-plugin-shaped suite would be copied whole into `.github/suites/…`. No fixture triggers it today: the only `dependencies.json` names skills | source, `suites/handoff-workflow/dependencies.json` |
| **[gap]** A fetch failure exits with curl's or tar's own code (for example 22), not the documented `1`, and prints no `_fail` line | `install.sh:21`, `:198-199` under `set -e` |
| **[gap]** The real `fetch_source()` path (curl → tar → top-dir detection) has no automated test. Every test passes `--local` | `scripts/test-install.sh:57-61`; memory doc "It still doesn't exercise…" |
| **[D#10]** No test covers a dependency whose category has no mapping for the harness, or one with an unrecognized category | `install.sh:424-431` vs. `test_deps_*` |
| **[D#22]** ADR-0008 is schema only. `harnesses.json` has no `resourceKinds`, no suite has `manifest.json`, and `catalog.sh`/`validate.sh`/`install.sh` don't read one | `scripts/harnesses.json`; `ls suites/*/manifest.json` → none |
| **[D#6]** Nothing records what was installed, so uninstall and update are impossible | source |
| **[D#11] is stale:** `feature/asset-dependency-manifest` merged as PR #9 (`ae695d6`, 2026-07-16) | `gh pr list --state merged` |
| **[D#8] is stale:** `origin/main` contains the installer commits (`6e532b2` …) | `git branch -r --contains 6e532b2` |
| **[gap] Doc drift** | see below |

Doc drift found:

- `README.md` § Installing: the flag table has no `--yes-deps`. It says dependencies come from
  `plugin.json`'s `dependencies` (wrong since ADR-0009: they come from `dependencies.json`). It
  says nothing about the fail-closed rule for non-interactive runs.
- `CLAUDE.md` (lines 72-76) and `suites/README.md` (lines 73-74) both say that dependency
  auto-include needs a plugin-shaped suite. Since ADR-0009 it applies to any asset.
- `docs/memory/vendor-agnostic-installer.md` line 26 links `ADR-0007-colocated-dependency-manifest.md`,
  which doesn't exist (it was renumbered to ADR-0009). Its "Known, accepted gaps" section still
  says `copilot.mapping omits suites`.
- ADR-0007's own `## Status` says only "Accepted". `INDEX.md` notes that ADR-0009 supersedes its
  dependency half, but the ADR itself doesn't.

## 2. Goals and non-goals

**Goals:** close D#6 (install record plus `--uninstall`), D#9, D#10 and D#22. Add `--ref`. Close
the untested-fetch gap. Clean the tracker (D#8, D#11). Fix the drift, the fetch exit code and the
latent bug above. Leave `install.sh` data-driven per ADR-0003, with no harness-name branching left.

**Non-goals (considered, not planned):**

| Idea | Why not now | Add when |
|---|---|---|
| `--update` (overwrite pristine files, keep edited ones) | owner declined (Q4); `--force` re-install covers unmodified installs | an owner edit gets clobbered by `--force` |
| Real-network CI job for the README one-liner | owner declined (Q5); stubbed-curl tests cover the fetch path | a codeload change breaks users unnoticed |
| Item-level non-interactive selection (`--assets skills/atomic-commits`) | not asked for. The picker covers interactive runs | a scripted user needs one asset |
| Format-aware merge (JSON deep-merge, `.gitignore` union) | most code and the most risk to user config; owner chose skip-or-`--force` (Q2) | skip-with-notice proves too weak in practice |
| `validate.sh`'s hardcoded `for variant in claude-code copilot` (line 142) | lint-only, harmless | a third harness ships a variant dir |
| Delete stale local branches (`feature/asset-dependency-manifest`, `feature/vendor-agnostic-installer`, …) | deleting is the owner's call | owner asks |

## 3. Shared groundwork: one place decides where an item goes [gap]

Today three code paths each re-derive "can this item go to this harness, and where": the
`select_assets()` loop, `resolve_dependencies()` pass 2, and `apply_selection()`'s
`is_copilot_suite_category` re-checks. D#9, D#22 and D#6 all have to change that same decision.
So the first, behaviour-preserving refactor slice extracts **one function, `plan_item`**, that
both `select_assets()` and `resolve_dependencies()` call. It also fixes the selection row format
once:

```
asset<TAB>src_rel<TAB>dest<TAB>mode<TAB>transform
skills/atomic-commits  skills/atomic-commits  .claude/skills/atomic-commits  item  -
```

- `asset` is the repo-relative asset path. It is the dedupe key (today the dedupe greps
  `src_rel`). `category`/`name` come from `${asset%%/*}` and `${asset##*/}`.
- `dest` is **root-anchored** in `resolve_root()`'s own convention: relative means the project
  root (`$PWD`), and `~/` means `$HOME`. For mapping rows this is `<scope root>/<template>`.
  ADR-0008 `resourceKinds` templates already use this convention, and the install manifest
  stores it unchanged.
- `mode` is `item` for mapping rows (today's whole-directory skip-or-replace). The placement
  slices add `copy` and `merge`.
- `transform` is the post-copy rewrite, or `-` for none. The refactor fills it from the existing
  hardcoded check. The transforms-as-data slice then swaps that one call site for data.

The latent bug is fixed first, in its own small slice, by applying the existing eligibility check
in `resolve_dependencies()` pass 2. An ineligible dependency is **warned and skipped**, the same as
a dependency in an unmapped category (ADR-0009, Positive #3); the owner accepted this narrowing
(Q1) and ADR-0011 records it. The refactor then routes dependencies through `plan_item` with that
behaviour already under test, so it stays behaviour-preserving.

## 4. D#9: Copilot translation as data

**Schema:** an optional per-harness `translate` object, `category → transform name`, as a
sibling of `mapping`. `mapping` values stay plain strings, so the change is additive:

```json
"copilot": {
  "mapping":   { "skills": "skills/{name}", "suites": "suites/{name}" },
  "translate": { "suites": "copilot-plugin" }
}
```

**install.sh:** a two-function registry keyed by **transform name, never harness name**:

```bash
transform_eligible() { case "$1" in copilot-plugin) _json plugin_shaped "$2" "$3" ;; *) return 1 ;; esac; }
transform_apply()    { case "$1" in copilot-plugin) translate_to_copilot "$4" ;; esac; }
```

`plan_item` looks up `_json translate "$HARNESS" "$category"`. If a transform is set and the item
isn't eligible, it warns and skips. The row then carries the transform name, and
`apply_selection()` calls `transform_apply` after the copy. `is_copilot_suite_category` and every
`"copilot"` literal are deleted. An unknown transform name gets a warning and the item is
skipped; `validate.sh` catches it first.

**validate.sh:** `translate` keys must be a subset of that harness's `mapping` keys, and values
must come from the known set (`copilot-plugin`; a comment points at the install.sh registry).

**ADR (decided, Q1):** new ADR-0011, written in the transforms slice. It partially supersedes
ADR-0007 (the gate mechanism moves into data) and reconciles ADR-0003: "never branch on a harness
name" is restored, and "adding a harness is a JSON edit" holds for harnesses that reuse an
existing transform; a *new kind of transform* still needs install.sh code. It also records that
ineligible dependencies are warned and skipped.

**Rejected alternatives:**
- (a) Won't fix: just amend ADR-0007. Costs 0 lines but leaves the ADR-0003 violation in place.
- (b) Express translation through ADR-0008 manifests. The placement vocabulary can't rename
  `*.md` → `*.agent.md`, and ADR-0008 says single-harness suites are unaffected.

## 5. D#22: ADR-0008 suite manifest

ADR-0008 already fixes the schema. This section covers only the implementation choices it left
open.

### 5.1 Data and lint (inert)

- **`harnesses.json`:** add the `resourceKinds` maps exactly as ADR-0008 shows them (§6 below).
  Nothing reads them yet.
- **`validate.sh` harness lint:**
  - `resourceKinds` scope keys must be a subset of the harness's `scopes`.
  - Kinds must be in `{agents, skills, instructions, hooks, config}`.
  - Template placeholders must be in `{suite, basename, relpath}`.
  - **[gap, ADR-0003 Negative #1]** `mapping` keys must be a subset of `{skills, suites}`, so a
    typo'd key fails instead of silently reading as "unsupported".
- **`validate.sh` per suite:** an optional `manifest.json` must be valid JSON, keyed by
  `harnesses.json` keys, with values that are arrays of `{kind, src, mode}`, where:
  - `kind` is in the vocabulary and defined in that harness's `resourceKinds` for at least one
    scope;
  - `mode` is `copy` or `merge`;
  - `src` exists under the suite, is not absolute, and has no `..` segment.
- **`catalog.sh`:** add `"manifest": <verbatim JSON>|null` per suite. It is read the same way as
  `read_dependencies_json()`, so a malformed file fails the catalog build cleanly. install.sh
  keeps reading the catalog only (ADR-0007 Neutral).

### 5.2 Engine: `copy` placements (inert, since no suite has a manifest yet)

`plan_item` checks for a suite manifest first. ADR-0008's precedence rule:

1. Manifest keys the harness: emit one row per expanded placement, with no `mapping.suites` and no
   `translate`.
2. Manifest exists but omits the harness: warn and skip.
3. No manifest: today's path, unchanged.

Expansion happens in a new `_json placements <suite> <harness> <scope>` mode (python; it walks
`$SRC`):

| Kind | Items | Destination |
|---|---|---|
| `agents`, `skills`, `hooks` | each immediate child of `src` | `{basename}` = that child's name |
| `config` | `src` itself (file or directory) | `{relpath}` = its path relative to `dirname(src)` |
| `instructions` | `src` | the fixed template |

`{suite}` is the suite's directory name. A kind missing for the chosen scope gets a notice and is
skipped (by omission). Suite-root docs are never placed.

**Safety choice (made on the owner's behalf; see the DAG's decision log):** placement `copy` works
**per file**. An existing file is skipped unless `--force` is set, and `--force` overwrites file by
file. It **never removes a directory**. Mapping rows keep today's whole-directory replace, since
`skills/{name}` is installer-owned. Without this rule, a `config` placement such as `{relpath}` =
`scripts` would `rm -rf ./scripts` in the user's project under `--force`.

Until merge mode lands, `merge` rows get a note ("merge mode not yet supported, skipped").

### 5.3 `merge` semantics (decided, Q2)

Per file. A target file that doesn't exist is created. One that exists is **skipped with a
notice unless `--force`** (then it is overwritten, file by file), and every skipped path is listed
once at the end, so the user can merge by hand (as `suites/tier-layered-teams/USAGE.md` already
says to). A directory is never removed. Created files go into the install record. About 40 lines.
Recorded as ADR-0013, together with the per-file placement copy rule (§5.2).

Rejected: a `<file>.ai-personal-new` sidecar per conflict (more files to track and uninstall), and
format-aware merge (about 150+ lines, real risk of corrupting user config).

### 5.4 Switch-on: migrate `tier-layered-teams`

- Add `suites/tier-layered-teams/manifest.json` (ADR-0008's example; it matches the current tree,
  see below).
- Update `suites/tier-layered-teams/USAGE.md` (no more manual `cp -R` and no more "dead weight"),
  `suites/README.md`, `README.md` § Installing, and `CLAUDE.md`'s drop-in-payload sentence.
- Add status notes to ADR-0008 (implemented) and ADR-0006 (dead-weight tradeoff resolved).
- Update the memory doc and strike D#22.

Tree check: `copilot/` has `.github/{agents,skills,hooks,copilot-instructions.md}`, `.vscode/`,
`Makefile`, `scripts/`, `.gitignore` and `scratch/`. `claude-code/` has `agents/` and
`.claude-plugin/`. That is one-to-one with ADR-0008's placements.

**User-visible consequences (accepted as documented limitations, Q3):** the migration documents
both in the suite's `USAGE.md` and in README § Installing.
- A claude-code install no longer copies the suite-root `README.md`/`USAGE.md`/`PROTOCOL.md` or
  `copilot/`. `claude-code/agents/00-escalation-protocol.md` line 3 links
  `../../PROTOCOL.md` as its "canonical source" provenance note, and that link will dangle in
  installed copies. The content is mirrored in the file itself, so nothing functional breaks.
  Keeping the link working would mean placing `PROTOCOL.md`, which contradicts ADR-0008's
  "suite-root docs are never installed".
- `--harness copilot` with suites selected (including the all-categories default of a piped run)
  will now create `Makefile`, `scripts/`, `.vscode/`, `.gitignore` and `scratch/` in the target
  project root. Create-only, never clobbering, but new.

## 6. `harnesses.json` after every slice

```json
{
  "claude-code": {
    "label": "Claude Code",
    "scopes": { "project": ".claude", "user": "~/.claude" },
    "mapping": { "skills": "skills/{name}", "suites": "suites/{name}" },
    "resourceKinds": {
      "project": {
        "agents": ".claude/suites/{suite}/agents/{basename}",
        "config": ".claude/suites/{suite}/{relpath}"
      },
      "user": {
        "agents": "~/.claude/suites/{suite}/agents/{basename}",
        "config": "~/.claude/suites/{suite}/{relpath}"
      }
    }
  },
  "copilot": {
    "label": "GitHub Copilot / VS Code",
    "scopes": { "project": ".github" },
    "mapping": { "skills": "skills/{name}", "suites": "suites/{name}" },
    "translate": { "suites": "copilot-plugin" },
    "resourceKinds": {
      "project": {
        "agents": ".github/agents/{basename}",
        "skills": ".github/skills/{basename}",
        "hooks": ".github/hooks/{basename}",
        "instructions": ".github/copilot-instructions.md",
        "config": "{relpath}"
      }
    }
  }
}
```

Schema rules:
- `label`, `scopes` and `mapping` are required (unchanged).
- `translate` and `resourceKinds` are optional. Leaving either out means "none" (compatibility by
  omission).
- **No key carries the install-manifest location.** It is always `<scope root>/.ai-personal-install.json`
  (config for a value that never changes is not needed).

The three schema-touching items land in an order that avoids collisions:
1. `resourceKinds` and the `mapping` key lint (data only).
2. `translate`.
3. Neither of those is touched by the manifest work.

## 7. D#6: installed-assets manifest

### 7.1 Format

`<scope root>/.ai-personal-install.json`, for example `.claude/.ai-personal-install.json`,
`~/.claude/.ai-personal-install.json` or `.github/.ai-personal-install.json`:

```json
{
  "version": 1,
  "harness": "claude-code",
  "scope": "project",
  "source": { "repo": "jean-tessier/ai-personal", "ref": "main" },
  "assets": {
    "skills/atomic-commits": {
      "installedAt": "2026-11-15T18:00:00Z",
      "files": {
        ".claude/skills/atomic-commits/SKILL.md": "sha256:9f2c…",
        ".claude/skills/atomic-commits/USAGE.md": "sha256:1c7a…"
      }
    },
    "suites/tier-layered-teams": {
      "installedAt": "2026-11-15T18:00:00Z",
      "files": {
        ".github/agents/coding-lead.agent.md": "sha256:…",
        "Makefile": "sha256:…"
      }
    }
  }
}
```

- **One manifest per scope root.** claude-code and copilot never share one, because their roots
  differ.
- **File granularity, with root-anchored paths** (same convention as `dest`). This one shape
  covers whole-directory mapping rows, per-file placements, and merge-created files.
- **Hashes are taken after any transform**, so they describe what is actually on disk.
- `version` is the only forward-compatibility hook; uninstall refuses an unknown version.
- `source.ref` is the `--ref` value (default `main`, §7.4); it is `null` under `--local`.

### 7.2 Writer

- `apply_selection()` appends `asset<TAB>dest` for every row or file it **actually writes**. Rows
  skipped because the destination exists are not logged, and merge mode logs only files it
  created.
- After the loop, a new `_json record` mode expands directories, hashes the files (python
  `hashlib`, since python3 is already required), and merges the result into any existing
  manifest:
  - per asset, `files` is updated (new or overwritten paths replaced, others kept);
  - `installedAt` is refreshed.
- `--dry-run` writes nothing. A user's own pre-existing skill with the same name is skipped and
  therefore never recorded.

### 7.3 Uninstall (decided, Q4)

`install.sh --harness H --scope S --uninstall [--assets cats] [--dry-run] [--force]`.

1. Load the manifest. If there is none, print a note and exit 0.
2. Take every recorded asset in the chosen categories (default all).
3. For each recorded file:
   - missing: forget it;
   - hash matches: delete it;
   - differs: keep it, warn, and keep its record. `--force` deletes it anyway.
4. Prune empty parent directories from the bottom up. Never remove the scope root, the project
   root or `$HOME`.
5. Drop assets that have no files left, and delete the manifest once it is empty.

Rules:
- **Path guard:** refuse any recorded path that is absolute, contains `..`, or is `~/`-anchored in
  a project-scope manifest. The manifest is a user-editable file, so this is a trust boundary.
- Dependencies are not removed transitively: they are their own recorded assets, removed only if
  their category is selected.
- Ponytail: uninstall still runs the normal fetch, because it needs `harnesses.json` for the scope
  root. That wastes a download but keeps one code path.

### 7.4 `--ref`: pin the fetched tree (decided, Q6)

`install.sh … --ref <tag|branch|sha>` sets `REF` (default stays `main`), so the codeload URL
becomes `…/tar.gz/<ref>`. Rules:

- The value goes into a URL, so it must match `^[A-Za-z0-9._/-]+$` and contain no `..`;
  anything else exits 1.
- `--ref` with `--local` exits 1, the same as `--yes-deps` with `--no-deps` (a pin silently
  ignored would surprise).
- The piped one-liner runs `main`'s `install.sh` against the pinned tree. README tells users to
  fetch `install.sh` from the same ref (`…/<ref>/install.sh`); refs older than the `--ref` slice
  are not supported.
- Tests reuse the stubbed `curl` from §8: the stub sees the ref in the URL, and a bad ref exits 1.
- The memory doc's Task-3 decision against `--ref` is recorded as reversed. The other half of
  that decision (no URL-override flag) still holds.

It lands after the fetch tests (it reuses their stub) and before the install record (which
stores it as `source.ref`).

## 8. Tests and gaps

- **[D#10] `test_deps_unsupported_category_warns`:** a synthetic harness that maps only `suites`,
  plus a fixture suite that depends on `skills/x` and `prompts/y`, run with `--yes-deps`. Expect:
  exit 0, both warnings, nothing under `skills/`. It covers behaviour that already works, so the
  acceptance check is a sabotage check.
- **[gap] Fetch path without network:**
  - Put a stub `curl` on the sandbox `PATH`. It records its arguments and writes a tarball built
    from a staged copy of `scripts/ skills/ suites/` under a `ai-personal-main/` top directory.
    Use portable `tar -czf -C`; no bsdtar `-s` and no `git archive`, so it works on macOS, Ubuntu
    CI and the `--network none` Docker run.
  - Assert the codeload URL, the extraction, and the install.
  - No URL-override flag. That honours the earlier "scope creep" decision.
  - No real-network CI job (Q5): the stub is the only fetch test.
- **[gap] Fetch failure exit code** (its own red-first slice, after the fetch tests): a stub that
  exits 22. Assert exit 1, a `fetch failed` line, and no traceback, via a 4-line
  `if ! curl …; then _fail …; exit 1; fi` guard (same for `tar`) in `fetch_source()`.
- **Gate (decided, Q7):** every installer slice is accepted on
  `make check && bash scripts/test-install.sh`. `make check` itself is not changed.

## 9. Ordering, interactions, risks, ADRs

**Ordering constraints:**

1. The dependency-eligibility fix comes before the refactor, so the refactor needs no test edits.
2. The refactor (§3) comes before transforms (§4), the placement engine (§5.2) and the manifest
   writer (§7.2). All three edit the same decision point and row format.
3. Data and lint (§5.1) come before transforms (both edit `harnesses.json` and `validate.sh`).
   Transforms come before the placement engine, because the precedence rule ("a manifest beats
   `translate`") needs `translate` to exist as data.
4. The engine comes before merge, and merge comes before the migration. The migration is the
   only switch-on for D#22.
5. Fetch tests come before `--ref` and the fetch-failure fix (both reuse the stub). `--ref` comes
   before the manifest writer, which records it.
6. The manifest writer comes before the placement engine and uninstall. It adds one
   `record_write` call; every later write path (placement copy, merge) calls it itself.
7. D#10's test and the docs and tracker hygiene don't depend on anything.

**Risks:**

| Risk | Mitigation |
|---|---|
| `main` is the release channel; a bad merge breaks `curl \| bash` at once | required checks; small slices; inert first, switch-on last; the fetch tests |
| Stacked edits to `install.sh` conflict, and strict up-to-date protection forces rebases | row format fixed in the refactor; slices touch separate functions; the orchestrator rebases |
| bash 3.2, BSD awk and Windows CRLF pitfalls | every new python heredoc piped through `tr -d '\r'`; temp files, not arrays; explicit `if/fi` guards (memory doc) |
| Data loss in user trees (`--force` on placements, uninstall, merge) | per-file copy that never removes a directory; merge skips existing files without `--force`; hash-checked uninstall; path guard |
| The migration changes behaviour for existing users of both harnesses | accepted (Q3); called out in README and USAGE |
| `--ref` runs `main`'s `install.sh` against an older tree | README says to fetch `install.sh` from the same ref; refs before `--ref` unsupported |
| ADR numbers collide with parallel work | numbers pre-assigned in the DAG; check `docs/adrs/` before writing |
| `test-install.sh` runtime grows (78 s now, about 2 min after) | acceptable; runs per installer slice, not in `make check` (Q7) |
| ADR-0007's root `plugin.json` assumption for Copilot is still unverified | unchanged; out of scope |

**ADRs:**

| ADR | Action | Slice |
|---|---|---|
| ADR-0011 (new) | Per-harness `translate` transforms as data; ineligible dependencies warned and skipped. Partially supersedes 0007, reconciles 0003 | transforms |
| ADR-0012 (new) | Installed-assets manifest: location, format, `source.ref`, ownership and uninstall policy | manifest writer |
| ADR-0013 (new) | ADR-0008 merge semantics (skip existing unless `--force`) and per-file placement copy | merge |
| ADR-0007 | Status note: dependency half superseded by 0009 (missing today); gate mechanism superseded by 0011 | docs hygiene, transforms |
| ADR-0008 | Status note: implemented; merge semantics in 0013 | migration |
| ADR-0006 (already superseded) | Note: dead-weight tradeoff resolved | migration |
| ADR-0003, ADR-0009 | Not superseded. 0011 records the narrowing (new *transforms* need code; ineligible dependencies are skipped) | transforms |

No skill changes in this plan, so there are no `skills/*/CHANGELOG.md` entries. Suites carry no
CHANGELOG.

## 10. Decisions

Owner, 2026-11-15:

1. **Q1:** the Copilot gate becomes `translate` data in `harnesses.json`; ineligible dependencies
   are warned and skipped. ADR-0011 partially supersedes ADR-0007 and reconciles ADR-0003.
2. **Q2:** `merge` skips existing files with a notice unless `--force`. ADR-0013.
3. **Q3:** migrate tier-layered-teams as-is; the dangling `PROTOCOL.md` link and the Copilot
   project-root writes are documented limitations.
4. **Q4:** install record (D#6, ADR-0012) plus `--uninstall`; no `--update`.
5. **Q5:** stubbed-curl fetch tests only; no real-network CI job.
6. **Q6:** add `--ref` (default `main`), recorded in the install record (§7.4).
7. **Q7:** installer tests run in each installer slice's acceptance check; `make check` unchanged.
8. **Q8:** the DAG lives at `.claude/state/installer-completion-dag.md`, excluded locally via
   `.git/info/exclude`.

The DAG holds the slices, models, waves and the decisions made on the owner's behalf. Open
pre-flight items: who merges (recommended: the owner), push and `gh pr create` permissions, and how
reviewers load `review-loop` (not installed; recommended: read `skills/review-loop/SKILL.md` from
the repo).

## 11. As built (2026-11-16)

The plan above shipped as PRs #13–#27 (plus follow-ups). Where the implementation differs from or adds to
the design:

- **SEC1 (not in the plan):** the `--uninstall` adversarial review found that `install.sh` and
  `catalog.sh` ran `python3` with the current directory on `sys.path`, so a `json.py` in a project root
  would run when the installer ran there. Every invocation now uses `python3 -I`, and `validate.sh`
  fails on a bare `python3`.
- **Uninstall record lookup:** an early build searched for the record near `$PWD`/`$HOME`; review showed
  a foreign record could drive it (a cloned repo's record deleting `~/.zshrc`). It follows §7.3: uninstall
  fetches the tree, reads only `<scope root>/.ai-personal-install.json` (its real parent must stay inside
  `$PWD` or `$HOME`), and a missing record is a note with exit 0.
- **Uninstall guards beyond ADR-0012's first list:** control characters (including Unicode format
  characters) and any `.git` segment, also reached through a symlink, abort the whole uninstall; files are
  compared by device and inode so case-insensitive file systems cannot fool the claim and record checks;
  non-regular files are never read; user-scope paths are confined to the scope root (`~/.claude/`).
  Project-scope paths may sit at the project root (Copilot `config`).
- **Install record:** each asset entry also stores its own `ref`; the top-level `source.ref` is the last
  install. The record is validated, checked against the run's harness and scope, and written atomically
  before and while files are placed, so a failure never leaves placed files unrecorded.
- **Placement engine:** a manifest crash fails closed (it never falls back to the whole-directory copy);
  tabs and other control characters in `src` are refused; destinations follow ADR-0012's text rules.
  `--force` replaces an existing file (so the payload's exec bit survives) and `--dry-run --force` says
  "would overwrite". `merge` leaves existing files untouched and lists them once, one path per line.
- **Left for later:** a round-trip test that installs and then uninstalls the real `tier-layered-teams`
  suite; the README `curl | bash` example does not pass `--yes-deps`, so the default all-categories run
  fails closed without a terminal; `--update` was declined (Q4).
