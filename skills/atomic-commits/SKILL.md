---
name: atomic-commits
description: Generate clean, atomic git commits from a user's working changes. Inspect the diff, split unrelated changes into separate commits, detect the repository's commit dialect (Conventional Commits, Changesets, kernel-style trailers, or plain prose), and write a message that explains why the change was made, not just what changed. Use this skill whenever the user wants to record changes in git, asks for a commit message, or says things like "commit this", "write a commit message", "stage and commit", "split these into commits", or "clean up my commit history" — even if they never say the word "atomic". Also use it when choosing a Conventional Commits type, adding a changeset for a release, or deciding whether a change should be one commit or several.
---

# Atomic Commits

Turn a working tree full of changes into well-formed, atomic commits whose messages a teammate (or the author, a year later) will thank you for. The hard part is rarely the syntax — it is deciding what belongs in one commit and recovering the *why* that the diff cannot show.

Three ideas drive everything below:

1. **One logical change per commit.** This is what makes `git revert`, `git bisect`, `git blame`, and code review actually work. Most "bad commit" problems are really "too many concerns in one commit" problems.
2. **Explain why, not how.** The diff already shows *what* changed; the reader can read code. Only the message can record the motivation, the context, and the alternatives you rejected. This is the highest-value content and the part you must not fabricate.
3. **Match the repository, don't impose on it.** Capitalization, whether to use a `type:` prefix, whether releases are driven by commits or by changeset files — these differ per project. Detect the local convention and conform to it.

## Workflow

### 1. Survey what actually changed

Run `git status` and read the full diff before writing anything:

```
git status
git diff              # unstaged changes
git diff --staged     # already-staged changes
```

Read the diff to understand the change on its own terms. Do not just paraphrase the user's one-line framing — they may have touched more than they remember. Note every distinct concern you see (a feature, an unrelated typo fix, a formatting sweep, a dependency bump). You will need that inventory in the next step.

If the diff is large, also skim `git diff --stat` to see the shape of it (which files, how much) before reading hunks.

### 2. Decide atomicity — is this one commit or several?

Ask: *does this working tree contain more than one logical change?* Tell-tale signs of a non-atomic mix:

- A functional change **and** a whitespace/formatting sweep in the same files.
- Two unrelated features, or a feature plus a bug fix that has nothing to do with it.
- A refactor of existing code **and** the new feature that the refactor was preparing for.
- Changes spanning unrelated modules with no shared purpose.

A useful test: try to write the subject line. If you cannot say what the commit does in roughly 50 characters without the word "and", it is probably two commits.

When the tree is mixed, **split it** rather than cramming. Stage one concern at a time:

```
git add -p              # stage selected hunks interactively
git add path/to/file    # or stage whole files that belong together
```

Then produce one message per commit. If the split is non-trivial or you are unsure how the user wants it grouped, propose the grouping in plain language and confirm before committing. Recommending a clean split is almost always more valuable than silently producing one sprawling commit.

If the change genuinely is one concern, stage it and move on.

### 3. Detect the repository's commit dialect

The right output depends on which of four "worlds" the repo lives in. **Run the detection script first**, then interpret its signals:

```
bash scripts/detect_dialect.sh
```

It reports the signals (config files present, prefix rate in recent history, trailer usage, changeset setup) and a suggested world. You make the final call. The four worlds, in brief:

- **World 1 — Conventional Commits.** Emit `type(scope): subject`. Most common in JS/TS and tooling-heavy repos.
- **World 2 — Changesets.** The primary artifact is a **changeset file** in `.changeset/`, not the subject line. Never infer the version bump from a commit prefix here.
- **World 3 — Trailer / kernel-style.** Plain imperative subject, body, and structured footer trailers (`Fixes:`, `Signed-off-by:`, etc.). No `type:` prefix.
- **World 4 — Prose (default).** Just a well-formed imperative message. Use this when no other signal is present.

Read `references/dialects.md` for the full signal tables, precedence rules for ambiguous cases, and the exact output format each world expects — especially World 2, where the deliverable changes shape.

### 4. Write the message

Apply the **universal hard rules** (below) in every world, then layer the dialect-specific format on top.

- For Conventional Commits format details (choosing the right type, scope, breaking-change notation, the linter header cap), read `references/conventional-commits.md`.
- For deeper guidance on writing the body, inferring intent, and the anti-patterns to avoid, read `references/message-quality.md`.

If you are splitting into several commits, write each message to stand on its own — a reader seeing it in isolation in `git log` should understand it.

### 5. Validate, then commit

Before committing, sanity-check the message:

- Subject is imperative, within the length budget, no trailing period.
- Body (if present) explains *why* and wraps at ~72 columns.
- If a commit-message linter is configured (a `commitlint` config, a `commit-msg` hook), the message conforms — run it if you can.

Then act according to what the user asked for:

- If they asked you to **commit** ("commit this", "stage and commit"), commit it. State the message you used in one line so they can see it. Use a here-doc or a file to preserve the body and blank line:
  ```
  git commit -F - <<'EOF'
  subject line here

  Body paragraph explaining why.
  EOF
  ```
- If they only asked for a **message**, output the message and stop — do not commit.
- If you split into multiple commits or made any non-obvious grouping decision, show the plan and the messages and confirm before committing.

## Universal hard rules

These hold in every dialect; they descend from near-unanimous authority (Tim Pope, Chris Beams' seven rules, the Pro Git book, the Linux kernel, Google's engineering practices).

- **Subject in the imperative mood:** "Add retry logic", not "Added"/"Adds"/"Adding". The test: *"If applied, this commit will ___."* It also matches what `git merge` and `git revert` generate.
- **Subject ≤ 50 characters** as a target; treat ~72 as the hard ceiling. If it won't fit, you are likely committing too much.
- **No trailing period** on the subject — it wastes scarce characters.
- **Blank line between subject and body.** Git parses the first line as the subject; tools like `log`, `shortlog`, and `rebase` rely on that blank line.
- **Body explains what and why, never how.** Wrap it at ~72 columns. A body is warranted whenever the change is non-obvious, has side effects, or involved a real decision; trivial, self-explanatory changes can be subject-only.
- **One logical change per commit.** (See step 2.)

## Recovering the "why" — and never fabricating it

The motivation is usually *not* in the diff, which is exactly why it belongs in the message. Pull it from whatever real signal exists: a linked issue or PR, the ticket ID, the branch name, comments in the code, or what the user told you. 

If the motivation genuinely cannot be determined, write a precise, honest *what* and keep the body minimal. Do **not** invent a rationale — a confident-sounding fabricated "why" is worse than an honest "what", because it misleads every future reader and poisons the historical record.

## Git safety

Committing is local and reversible, so committing a clear change the user asked for is fine. But some operations are destructive or rewrite shared history — never do these unless the user explicitly and specifically asks:

- **Never** `push`, `push --force`, or publish. Recording a commit is not the same as sharing it.
- **Never** rewrite already-pushed history (rebase, `commit --amend`, reset) on shared branches.
- **Never** run destructive resets or `git clean` that discard the user's uncommitted work.
- **Scan the diff for secrets** before committing — API keys, tokens, passwords, private keys, `.env` contents. If you spot one, stop and warn the user instead of committing it.

When in doubt about an irreversible action, describe what you would do and let the user confirm.

## Quick examples

**Restating the diff (bad) vs. explaining why (good):**
- Bad: `Change timeout from 5 to 10`
- Good: `Increase API timeout to 10s for slow regions` — and, in the body, *why* 5s was insufficient.

**Vague (bad) vs. specific (good):**
- Bad: `fix bug`, `update`, `changes`, `wip`
- Good: `fix(auth): reject expired tokens on refresh`

**Non-atomic (bad) vs. split (good):**
- Bad: one commit titled `Add export feature and fix login and reformat`
- Good: three commits — `feat(export): add CSV export`, `fix(auth): handle empty password`, `style: reformat user module`

## Reference files

- `references/dialects.md` — the four-world detection model: signal tables, precedence for ambiguous repos, and the exact output each world expects (including the Changesets file format). Read this in step 3.
- `references/conventional-commits.md` — Conventional Commits specifics: type taxonomy and how to choose, scope, breaking changes, SemVer mapping, footer trailers, and linter caps. Read this when the repo is World 1.
- `references/message-quality.md` — the seven rules with rationale, how to infer change type from a diff, when a body is warranted, the full anti-pattern list, and worked good/bad examples. Read this whenever you want to raise message quality.
- `scripts/detect_dialect.sh` — gathers the dialect signals from the repo. Run it in step 3.
