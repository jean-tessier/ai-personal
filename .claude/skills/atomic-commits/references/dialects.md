# Commit dialects: the four-world model

A repository's commit history follows one of four broad conventions. Detect which before writing, because the dialect changes not just the subject format but, in one case, the *primary artifact* you produce. Run `scripts/detect_dialect.sh` to gather signals, then use this file to interpret them and to format the output.

## Contents
- World 1 — Conventional Commits
- World 2 — Changesets
- World 3 — Trailer / kernel-style
- World 4 — Prose (default)
- Precedence and ambiguous repos

---

## World 1 — Conventional Commits

**Signals.** Any one of these is strong evidence:
- A commitlint config (`commitlint.config.*`, `.commitlintrc*`).
- A semantic-release or Release Please config (`.releaserc*`, `release.config.js`, `release-please-config.json`).
- A Commitizen config (`.czrc`, `cz.json`, or `config.commitizen` in `package.json`).
- `@commitlint/*`, `semantic-release`, `standard-version`, or `commitizen` in `package.json`.
- Absent config, a high share (≈50% or more) of recent `git log` subjects matching `type(scope): subject`.

**Output.** `type(scope): subject`, lowercase type, then a blank line and an optional body, then optional footer trailers. Example:
```
feat(parser): support nested config blocks

Recursive blocks let teams group related keys without a flat namespace.
Closes #214
```
Choose the most specific correct type, scope from the touched module, and mark breaking changes with both `!` and a `BREAKING CHANGE:` footer. Keep the header within the linter cap (commitlint defaults to 100 characters for the whole first line). The full type taxonomy and breaking-change rules are in `references/conventional-commits.md`.

---

## World 2 — Changesets

This is the one world where "write a commit" stops meaning "write a subject line." Changesets decouples versioning from commit messages: the version bump and the user-facing changelog entry are declared in a reviewed markdown file, not inferred from a `feat:`/`fix:` prefix. Treat the **changeset file as the primary deliverable**.

**Signals.**
- A `.changeset/` directory (usually with `config.json`).
- `@changesets/cli` in `devDependencies`.
- `changesets/action` in CI workflows; recurring "Version Packages" PRs in history.

**Output.** Create a changeset file at `.changeset/<short-slug>.md`. Its front matter lists each affected package and its bump level; the body is a concise, user-facing summary of the change (written for the people reading the changelog, not for developers reading the diff):

```
---
"@acme/parser": minor
"@acme/core": patch
---

Add support for nested config blocks, letting teams group related keys.
```

Infer the affected package(s) from which package directories the diff touches, and the bump from the nature of the change (new capability → minor; bug fix → patch; incompatible change → major). The simplest way to create one is the tool's own prompt, `npx changeset`, but writing the file directly is fine and often faster.

**Critically, never infer the version bump from a commit prefix in this world** — the changeset declaration is the source of truth, and a prefix-derived bump would compete with it. The commit message itself can follow the repo's secondary style (often relaxed Conventional Commits or plain prose); keep it correct but secondary.

---

## World 3 — Trailer / kernel-style

Common in the Linux kernel, Git itself, and other patch/mailing-list projects. Metadata lives in structured **footer trailers**, parsed by `git interpret-trailers`, rather than in a subject prefix.

**Signals.**
- Frequent `Signed-off-by:`, `Fixes: <sha>`, `Reviewed-by:`, `Acked-by:`, `Reported-by:`, or `Cc:` lines in recent commit bodies.
- A `CONTRIBUTING` file or `SubmittingPatches` doc that requires DCO sign-off.
- CI or a hook that enforces the DCO.

**Output.** A plain imperative subject with **no** type prefix, a body wrapped near 72–74 columns explaining motivation, then trailers:
```
Fix race when two workers flush the same buffer

Under load, two workers could enter flush() concurrently and double-free
the page. Guard the flush path with the existing buffer lock; the extra
contention is negligible at observed concurrency.

Fixes: 9a1c2f3b4d5e ("Add buffered writer")
Reported-by: Dana Lee <dana@example.org>
Reviewed-by: Sam Ortiz <sam@example.org>
Signed-off-by: Author Name <author@example.org>
```
Link a bug fix to the commit that introduced it with `Fixes: <12-char-sha> ("subject")`. Add `Signed-off-by:` (via `git commit -s`) **only** when the user directs it — it is a legal attestation under the Developer Certificate of Origin, not decoration.

---

## World 4 — Prose (default)

The fallback when no other signal is present, and the highest-prestige style among many senior engineers. A well-formed imperative message with no machine-readable prefix.

**Signals.** None of the above; recent history shows clean imperative subjects without prefixes and no release-automation config.

**Output.** The universal hard rules and nothing more: imperative subject ≤50/72, blank line, a body explaining *why* when the change isn't self-evident. Match the repository's observed capitalization and its norm for whether bodies are usually present.
```
Cache compiled templates between requests

Re-parsing on every request dominated p99 latency under load. The
template set is small and stable, so an in-process LRU is sufficient.
```

---

## Precedence and ambiguous repos

Signals often coexist. Resolve with these rules:

- **An active release mechanism beats commit phrasing.** A `.changeset/` directory plus `@changesets/cli` means World 2 even if subjects also look like Conventional Commits — the changeset file is what drives the release. Treat the commit subject as secondary.
- **Config beats history.** An explicit commitlint/semantic-release config means World 1 even if a few recent subjects drifted.
- **When signals are weak or conflicting, default to World 4** and conform to the dominant pattern in the most recent ~20–50 commits.
- **When genuinely unclear, say so.** Tell the user which signals you found and which world you propose, and let them confirm rather than silently imposing Conventional Commits. Imposing a heavy convention on a repo that does not use it is a common and annoying failure mode.
