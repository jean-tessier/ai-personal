# Message quality reference

The universal craft of a good commit message, independent of dialect. These rules have near-unanimous backing across Tim Pope (2008), Chris Beams' seven rules (2014), the Pro Git book, the Linux kernel docs, and Google's engineering practices.

## The seven rules, with the reason each exists

1. **Separate subject from body with a blank line.** Git treats the first line as the subject and everything after the blank line as the body; `log`, `shortlog`, and `rebase` depend on it.
2. **Limit the subject to ~50 characters.** Keeps `git log --oneline` and host UIs readable, and forces you to name a single change. If you can't, you're probably committing too much.
3. **Capitalize the subject — or match the repo.** Beams says capitalize; the Angular/Conventional-Commits camp says lowercase. There is no universal winner, so conform to the repository's existing history.
4. **No trailing period in the subject.** It wastes a character that the 50-char budget can't spare.
5. **Use the imperative mood.** "Add", not "Added"/"Adds". Test: *"If applied, this commit will ___."* It also matches messages `git merge` and `git revert` generate.
6. **Wrap the body at ~72 columns.** Git indents the body in `git log`, so 72 keeps it inside an 80-column terminal.
7. **Use the body to explain what and why, not how.** The diff shows how. Only the message can record motivation and context.

## The "why" is the whole point

A diff tells the reader what changed; only the message can tell them why. That "why" is almost never recoverable from the code, which is exactly why it must be written down. When you write a body, spend it on:
- the problem this change solves;
- why this approach over an obvious alternative;
- side effects or non-obvious consequences;
- anything a competent reader who has forgotten today's context would need.

Pull the motivation from real signals — the linked issue or PR, the ticket, the branch name, code comments, or what the user said. If you cannot find it, write a precise *what* and keep the body short. **Never invent a rationale.** A plausible-sounding fabricated "why" is worse than none: it misleads every future reader and corrupts the record that `git blame` and incident responders rely on.

## Inferring the change type from a diff

When you need to classify a change (for a Conventional Commits type, or just to understand it), read these signals:
- New files / new functions / new exported symbols → likely a feature.
- Edits to error handling, null/bounds checks, off-by-one, conditionals → likely a fix.
- Only test files changed → a test change.
- Only docs/markdown changed → a docs change.
- Whitespace / formatting only → a style change.
- Same behavior, reorganized code (renames, extractions, moves) → a refactor.
- Dependency manifests, lockfiles, build config, CI YAML → build/ci.
- Removed or renamed public signatures, changed config keys, dropped options → likely breaking.

Infer the *what* confidently from the diff; infer the *why* only from real context, never from imagination.

## When a body is warranted

- **Subject-only is fine** for genuinely trivial, self-explanatory changes (a typo fix, a version bump, an obvious one-liner). Forcing a body onto these adds noise.
- **Write a body** when the change is non-obvious, has side effects, fixes a subtle bug, involved a real decision, or affects behavior or compatibility — i.e. whenever the "why" isn't self-evident from the subject alone.
- Either way, **match the repository's norm.** Some teams write bodies on almost every commit; others rarely do. Conform.

## Anti-patterns to avoid

- **Vague or empty subjects:** `fix bug`, `update`, `changes`, `stuff`, `wip`, `misc`, `asdf`, `minor fixes`. They tell a future reader nothing.
- **Restating the diff / explaining how:** `Change line 42 from 5 to 10`, `Refactor load_data to use a comprehension`. Say *why* instead: `Raise timeout to 10s for slow regions`.
- **Past tense or gerunds:** `Fixed…`, `Fixing…` — breaks the imperative rule.
- **A subject that needs the word "and":** a strong sign the commit is non-atomic. Split it.
- **Mixing concerns in one commit:** whitespace + logic, two unrelated features, a refactor + the feature it enabled.
- **Bare ticket IDs as the only content:** `JIRA-1234`. Git is decentralized; don't make the reader leave the repo to learn what changed. Put the ID in a footer and describe the change in the subject.
- **A fabricated rationale.** Covered above — the worst of all, because it looks helpful.

## Worked good / bad examples

**Explaining why beats restating the change:**
- Bad: `Set retries to 3`
- Good: `Retry failed uploads up to 3 times` + a body noting that transient S3 5xx errors were failing whole batches.

**Specific beats vague:**
- Bad: `fix login`
- Good: `Reject login when account is locked` + a body on the security report that prompted it.

**Atomic beats kitchen-sink:**
- Bad: `Add search, fix pagination, bump deps`
- Good: three commits — `Add full-text search to issues list`, `Fix off-by-one in pagination`, `Bump lodash to 4.17.21`.

**Honest "what" beats invented "why":**
- If you truly don't know why a constant was changed, write `Set default page size to 50` — not a confident fictional story about user research that may never have happened.
