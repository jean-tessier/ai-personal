---
date: 2026-07-01
description: Built a curl+tar+python3 installer (install.sh + harnesses.json) for this repo's own skill/task/workflow catalog, targeting Claude Code and Copilot
status: active
tags: [handoff, archive]
scope: archive.handoffs
---

# Handoff

## What was completed this session

**Task 6 — Live end-to-end fetch test (both harnesses), Parts A and B — the final task of this
effort.** The overall goal ("a single `curl | bash`-able script that lets a user interactively
select catalog assets, an install scope, and one or more target harnesses, then fetches this public
repo and copies the selected assets into the right place per harness") is now met. This is a
**closing handoff** — see "Goal met" below instead of a "Next task" section.

## Completed work

### Files table

| File | What changed |
|---|---|
| `install.sh` | Added a ~6-line guard in `main()`, right after `build_catalog()`: `if [[ ! -f "$SRC/scripts/harnesses.json" ]]; then _fail "..."; exit 1; fi`. This is the only permanent change from Task 6 — everything else (the temporary test-server URL edit) was reverted before finishing. |

No other repo files changed as part of Task 6 itself. All test infrastructure (tarball, HTTP
server) lived under the scratchpad directory and was deleted before finishing.

### Part A — full round-trip against a tarball that has everything

1. Packaged the current working tree (this branch's uncommitted state: `install.sh`,
   `scripts/harnesses.json`, README/`validate.sh` changes, everything) into a `.tar.gz` under the
   scratchpad directory, top-level directory renamed to `ai-personal-main` via bsdtar's `-s`
   rename flag (macOS stock `tar` is bsdtar, not GNU tar — no `--transform`), excluding `.git`.
2. Served it with `python3 -m http.server 8917 --bind 127.0.0.1` from the scratchpad, confirmed
   reachable (`HTTP 200`).
3. Temporarily edited `fetch_source()`'s `url=` line to point at
   `http://127.0.0.1:8917/ai-personal-main.tar.gz`.
4. Ran the real (no `--local`) `install.sh --dry-run --harness claude-code --scope project
   --assets skills`, then the same with `--harness copilot`. **Result: both matched the known-good
   `--local`-based results exactly** — all 6 skills (`atomic-commits`, `create-adr`,
   `create-changelog`, `fix-validation`, `readme-maintenance`, `yaml-frontmatter`) resolved to
   `.claude/skills/{name}` for claude-code and `.github/skills/{name}` for copilot, zero files
   written (dry-run). The real `curl`+`tar` fetch path is proven equivalent to the `--local`
   shortcut used by every prior task's testing.
5. Reverted the URL edit (confirmed via `grep` for the codeload URL — `install.sh` is untracked so
   `git diff` shows nothing regardless; verified textually instead), killed the HTTP server
   (`lsof -ti tcp:8917 | xargs kill`, confirmed stopped), and deleted the scratchpad tarball/server
   directory.

### Part B — real public network reachability

1. Ran the real, completely unmodified `install.sh --dry-run --harness claude-code --scope
   project --assets skills` against the actual public `codeload.github.com/jean-tessier/
   ai-personal/tar.gz/main`.
2. **Observed the expected crash**: since `origin/main` predates this whole effort (still at
   `1763ef7`), the fetched tree has no `scripts/harnesses.json`. The result was a genuine crash,
   not a clean failure — a raw Python `FileNotFoundError` traceback printed twice (once from the
   `harness_exists` call, once from `harness_keys` inside the error message's own `$(...)`)
   *before* the script's own `_fail`/`exit 1` line ever ran.
3. Since it was a crash, not a clean failure: added the documented ~3-line guard (see Files table
   above) right after `build_catalog()` in `main()`, using an explicit `if...fi` (per the
   `set -euo pipefail` / bare `cond && action` gotcha this repo's scripts already avoid elsewhere).
4. **Re-ran the same command after the fix**: now prints a single clean line —
   `FAIL  fetched tree is missing scripts/harnesses.json — nothing to install` — and exits 1, no
   traceback. Before/after both captured directly in this session's tool output.

### Verification

| Check | Result |
|---|---|
| Part A: both harnesses' dry-run output via real fetch vs. known-good `--local` results | Match — 6 skills, correct destination paths, zero files written |
| Part A: temporary URL edit reverted | Confirmed via `grep` — only the real `codeload.github.com` URL remains in `fetch_source()` |
| Part B: crash observed against real public `origin/main` (missing `scripts/harnesses.json`) | Confirmed — raw `FileNotFoundError` traceback, printed twice, before any `_fail` line |
| Part B: guard fix | Confirmed — same command now prints one clean `FAIL` line, exit 1, no traceback |
| `bash -n install.sh` | Syntax OK |
| `bash scripts/validate.sh` | Exit 0, "All checks passed." — `── harnesses ──` section still `ok` for both harnesses (label, scopes, mapping); same pre-existing eval-suite warnings, no regression |
| Local HTTP server | Killed (`lsof -ti tcp:8917` returns nothing after) |
| Scratchpad test artifacts | Deleted (`scratchpad/task6/` no longer exists) |
| `git status --short` | Only `README.md`/`scripts/validate.sh` modified (Task 5) and `handoff.md`/`install.sh`/`scripts/harnesses.json` untracked (Tasks 2–6) — nothing left over from Task 6's throwaway test infra |

## Phase state table

| Task | Status | Notes |
|---|---|---|
| Task 1 — Brainstorm installer spec | ✅ Done | Decisions recorded |
| Task 2 — Build `scripts/harnesses.json` | ✅ Done | claude-code omits agents+mcp too (verified against live docs); see ADR-0004 |
| Task 3 — Build `install.sh` core (fetch, selection, copy) | ✅ Done | Fetch/select/copy all working; data-driven manifest design, see ADR-0003 |
| Task 4 — Picker UX (`fzf`/`gum` + `read`-loop fallback) | ✅ Done | Flag-driven path provably unchanged; picker gated on TTY; test seam + stubs documented |
| Task 5a — README updates | ✅ Done | `## Installing` section added, cross-checked against real flags/keys |
| Task 5b — `validate.sh` integration | ✅ Done | New `── harnesses ──` section, verified against real file + a broken scratch copy |
| Task 6 — Live end-to-end fetch test (both harnesses) | ✅ Done (this session) | Part A: real curl+tar fetch verified equivalent to `--local` for both harnesses. Part B: crash-on-missing-manifest found against real public `origin/main` and fixed with a 3-line guard. |

## Goal met

This effort built a single, dependency-light (`curl` + `tar` + `python3`, no `git` needed at
install time) installer for this repo's own catalog of Claude Code skills, tasks, and workflows:

- **`install.sh`** (repo root) — fetches a tarball of this repo (or a `--local` path, for testing),
  builds an in-memory asset catalog via the existing `scripts/catalog.sh`, resolves which asset
  categories a chosen harness/scope actually supports, lets the user pick specific items
  interactively (via `fzf`, `gum`, or a numbered fallback prompt) when running in a real terminal
  with no `--assets` flag, and copies the result into place — or, with `--dry-run`, just reports
  what it would do.
- **`scripts/harnesses.json`** — a data-only manifest describing each supported harness's label,
  install scopes, and destination-path templates per asset category. Adding a harness is a JSON
  edit, never a code change (ADR-0003). Two harnesses are declared today: `claude-code` (scopes
  `project`→`.claude`, `user`→`~/.claude`; supports `skills`, `tasks`, `workflows`) and `copilot`
  (scope `project`→`.github` only; supports `skills` only). Neither harness's mapping includes
  `agents` or `mcp` — this repo's storage shapes for those two categories don't match either
  harness's native format (ADR-0004), a finding that held even for `claude-code`, this repo's own
  daily driver, not just for the more obviously-different `copilot`.
- **`README.md`**'s `## Installing` section and **`scripts/validate.sh`**'s `── harnesses ──`
  section — user-facing docs and structural CI-style linting for the manifest, so a malformed
  harness entry fails validation rather than failing silently at install time.
- **This session's Task 6** proved the one piece of the pipeline no prior task had exercised for
  real: the actual `curl`+`tar` network fetch (Part A), and what happens when that fetch targets a
  tree that predates this whole effort (Part B) — which surfaced and fixed a genuine
  crash-vs-clean-error gap.

Nothing further is planned under this effort's original task list. Any new work (the v2 deferrals
below, or anything else) is new, separate scoping — not a fabricated "Task 7."

## Open items

| # | Item | Status |
|---|---|---|
| 1 | Flatten pack skills into the `skills` mapping key, or give packs their own `packs` key? | ✅ Resolved — flattened into `skills` (ADR-0005) |
| 2 | Public entrypoint location: repo-root `install.sh` vs. `scripts/install.sh`? | ✅ Resolved — repo-root `install.sh` |
| 3 | Non-interactive/scriptable flags for CI use — v1 or v2? | ✅ Resolved — v1, implemented |
| 4 | Installed-assets manifest for future uninstall/update support | Deferred to v2 — captured in `docs/memory/deferred-items.md` |
| 5 | `claude-code.mapping` omits `agents` and `tools`/`mcp` | ✅ Resolved — confirmed via Context7 and live smoke tests (ADR-0004) |
| 6 | `tasks` category name carries a stray `.md` from `catalog.sh`'s file-basename vs. `harnesses.json`'s `{name}.md` template | ✅ Resolved defensively — untested against real data since `prompts/tasks/` is currently empty; re-check once real tasks exist (captured in `docs/memory/deferred-items.md`) |
| 7 | Testing Task 4's interactive picker paths without a real TTY in this sandbox | ✅ Resolved — `INSTALL_FORCE_INTERACTIVE=1` env var seam + fzf/gum `PATH` stubs, all demonstrated |
| 8 | `curl \| bash` (piped, no explicit `--assets`) never gets the interactive picker | ✅ Resolved — documented in README's `## Installing` section; known, intentional limitation |
| 9 | This branch's files are now committed locally (5 commits, via `/atomic-commits`) but not pushed — `origin/main` is still at `1763ef7` | Partially resolved — committed 2026-07-01; whether/when to push remains the user's call, not any task's to decide. Task 6 was completed working around the pre-commit state (Part A used a local test server; Part B deliberately exercised the real, unmodified public repo and found/fixed the missing-manifest crash as a result). |
| 10 | Part B's missing-manifest guard | ✅ Resolved — added, shown to turn a raw `FileNotFoundError` traceback into a single clean `_fail` line |

## Standing rules (unchanged, carried forward for whoever reads this next)

- This handoff is **terminal** for the originally-locked task list (Tasks 1 through 6). Do not
  invent a "Task 7" from this document alone — any genuinely new work should start from a fresh
  scoping conversation, using the Open items above as candidate starting points.
- Do NOT commit or push on this branch's behalf — that remains the user's call (Open item 9).
- Ingestion into `docs/adrs/` (ADR-0003, ADR-0004, ADR-0005) and `docs/memory/`
  (`vendor-agnostic-installer.md`, plus carried-forward entries in `deferred-items.md`) was
  performed this session per the `ingest-handoff` skill. This `handoff.md` stays in place as the
  session record — it was not archived or deleted.
