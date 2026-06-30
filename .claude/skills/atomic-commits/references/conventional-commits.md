# Conventional Commits reference (World 1)

Use this when the repository is in World 1. Format:

```
type(optional scope): description

optional body

optional footer(s)
```

## Choosing the type

The spec itself only defines `feat` and `fix`; the rest of the standard list comes from the Angular convention via `@commitlint/config-conventional`. Pick the **most specific correct** one:

- **feat** — a new user-facing capability. Drives a MINOR version bump.
- **fix** — a bug fix. Drives a PATCH bump.
- **docs** — documentation only.
- **style** — formatting, whitespace, semicolons; no behavior change.
- **refactor** — code change that neither fixes a bug nor adds a feature.
- **perf** — a performance improvement.
- **test** — adding or correcting tests.
- **build** — build system or external dependencies (npm, bundler, Docker).
- **ci** — CI configuration and scripts.
- **chore** — maintenance that fits nothing above. Use as a last resort, not a default dumping ground.
- **revert** — reverts a previous commit; body starts `This reverts commit <sha>.`

**Disambiguation that trips people up:**
- Touched only test files? → `test`, even if it was "for" a feature.
- Touched only docs/markdown? → `docs`.
- Behavior-preserving restructuring? → `refactor`, not `fix`.
- A dependency bump? → `build` (or `chore` if the repo treats deps as chores — match local history).
- If a change honestly fits two types, that is a signal it should be **two commits**. Split it.

The decisive question for `feat` vs `fix` vs everything else: *does an end user use or need to know about this change?* If yes, it is almost always `feat` or `fix`.

## Scope

An optional noun in parentheses naming the affected area: `feat(parser):`, `fix(auth):`. Derive it from the top-level module, package, or directory the change touches. Some repos enumerate a fixed scope list (Angular does) — if so, use one of theirs; check recent history or the commitlint config. Scope is optional in the spec, but including it is usually the single most useful thing for someone later scanning the log or chasing an incident, so prefer to include it when there is a clear one.

## Breaking changes

A breaking change can ride on **any** type and forces a MAJOR bump. Signal it two ways (use both when you can):

1. A `!` before the colon: `feat(api)!: drop support for v1 tokens`.
2. A `BREAKING CHANGE:` footer describing the break and the migration:
   ```
   feat(api)!: require auth on all endpoints

   BREAKING CHANGE: unauthenticated requests now return 401. Clients must
   send a bearer token; see MIGRATION.md.
   ```
`BREAKING CHANGE` must be uppercase (the one trailer allowed to contain a space; `BREAKING-CHANGE` is an accepted synonym).

## SemVer mapping

- `fix:` → PATCH
- `feat:` → MINOR
- any `BREAKING CHANGE` / `!` → MAJOR
- other types → no implicit release effect unless they carry a breaking change.

## Footers / trailers

Follow the git trailer convention — `Token: value`, with hyphens instead of spaces in the token:
- `Closes #123` / `Fixes #123` — auto-closes the issue on GitHub.
- `Refs #123` — references without closing.
- `Co-authored-by: Name <email>` — credits a co-author (use the email tied to their account).
- `Signed-off-by: Name <email>` — DCO attestation; only when the workflow requires it.

## Length / linter cap

Aim for a ≤50-character subject, but the binding constraint is the repo's linter. `@commitlint/config-conventional` defaults to a **100-character** cap on the whole first line (type + scope + description), with body and footer lines also capped at 100. If a `commitlint` config sets different values, honor those. When a linter or `commit-msg` hook exists, validate against it before committing.

## Worked examples

```
fix(parser): handle empty config files

An empty file previously threw instead of yielding an empty config.
Closes #501
```

```
refactor(auth): extract token validation into TokenGuard

No behavior change. Isolates the validation logic so the upcoming
refresh-token work has a single place to hook in.
```

```
feat(cli)!: rename --output to --out

BREAKING CHANGE: the --output flag is removed. Use --out. The old name
silently mapped to a different option, causing surprising overwrites.
```
