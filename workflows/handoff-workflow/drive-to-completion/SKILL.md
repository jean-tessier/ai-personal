---
name: drive-to-completion
description: Orchestrate subagents to run the full handoff loop (resume → execute → handoff → repeat) autonomously until every task in the original handoff is done. Only returns control to the developer once all originally-planned tasks are complete. Use when the user says "drive this to completion", "run this autonomously", "keep going until done", or "/drive-to-completion".
---

# Drive to Completion

## Purpose

Autonomously execute all remaining tasks in `handoff.md` using a subagent-per-session loop,
surfacing back to the developer only when the original scope is exhausted or a genuine
human-gate is hit.

```
  /drive-to-completion
        │
        ▼
  Phase 1: Upfront analysis & clarification  ← ASK ALL QUESTIONS HERE
        │
        ▼
  Phase 2: Lock the original task set
        │
        ▼
  ┌─── Phase 3: Spawn execution subagent ◄──────┐
  │         (resume-handoff + handoff-document)  │
  │                   │                          │
  │         Task done, handoff updated           │
  │                   │                          │
  │         Phase 4: Check completion ───────────┘
  │                   │  (tasks remain)
  │                   │  (all done)
  └───────────────────▼
             Phase 5: Completion report → developer
```

---

## Phase 1 — Upfront Analysis and Clarification

**This is the only phase where you ask the developer questions. Do it comprehensively now,
because every subagent will proceed without stopping to ask.**

1. Read `handoff.md` in full.
2. Read every file listed under "Read before coding" in the Next task section.
3. Build a complete picture of:
   - The **overall goal** — what does "done" mean for this effort?
   - Every task in the phase state table (✅ done, 🔜 next, ⬜ remaining).
   - Every **Open item** in the handoff.
   - Any ambiguity in the Next task's Key constraints, Definition of done, or data shapes.
   - Any external dependency that could block a subagent (credentials, config, external service).

4. **Compose one consolidated question block** covering every uncertainty. Group by task so the
   developer can answer in a single reply. Use `AskUserQuestion` when the decision is truly
   theirs (architecture choices, priority calls, access credentials). Otherwise, state your
   intended default and proceed if the developer does not object.

5. **Do not start Phase 3 until** all blocking open items are resolved or have documented defaults.
   Non-blocking items can be carried as Open items into the handoff — note the default you'll use.

---

## Phase 2 — Lock the Original Task Set

After clarification, record the **exact list of tasks that were NOT ✅ at the time this skill
was invoked**. This is the completion check set — you will compare against it after each
subagent to know whether to loop or stop.

Capture:
- Task names/IDs exactly as written in the phase state table.
- The overall goal statement.
- Any per-task decisions made during clarification that future subagents must honor.

Keep this list in working memory for the duration of this skill's execution.

---

## Phase 3 — Spawn an Execution Subagent

Spawn an `Agent` with a **complete, self-contained brief** so it can execute one full
`resume-handoff → handoff-document` turn without asking questions.

### What to include in the subagent prompt

Every subagent prompt must contain all of the following:

**1. The full `resume-handoff` skill instructions** (copy them verbatim — the subagent
   has no access to skill context from this session).

**2. The full `handoff-document` skill instructions** (same reason).

**3. The current contents of `handoff.md`** (read it fresh before each spawn, since the
   previous subagent may have updated it).

**4. Decisions made during clarification** — list every answer from Phase 1 that affects
   the next task. The subagent must not re-ask these; it must use the answers you give it.

**5. Standing rules that override defaults:**
   - "Proceed on documented defaults. Do NOT ask the user questions unless you hit a
     complete hard block (missing file that doesn't exist, compile error you cannot fix,
     auth credential you cannot obtain). If you hit a hard block, stop and write a clear
     blocker note into `handoff.md` under Open items, then update `handoff.md` and exit."
   - "Do NOT expand scope. Respect the NOT-in-scope list in the handoff exactly."
   - "Run the full test suite and TypeScript check before marking the task done."
   - "The task is complete only when its Definition of Done checkboxes are all met."

**6. The locked task list from Phase 2** — so the subagent knows what the full remaining
   scope looks like, even though it only executes the Next task this turn.

**7. An explicit exit contract:**
   - On success: re-write `handoff.md` via `handoff-document` instructions, commit if the
     project convention says so, then exit.
   - On hard block: write blocker to `handoff.md` open items, exit.
   - On ambiguity in a non-blocking area: pick the documented default, note the choice in
     the handoff, continue.

### Subagent prompt template

```
You are executing one turn of a multi-session handoff loop. You must complete exactly the
"Next task" in handoff.md to its Definition of Done, then re-write handoff.md for the
following session. You must NOT ask questions — use documented defaults and proceed.

## Resume-Handoff Instructions (follow these exactly)
[PASTE FULL resume-handoff SKILL.md CONTENT HERE]

## Handoff-Document Instructions (follow these for re-writing handoff.md)
[PASTE FULL handoff-document SKILL.md CONTENT HERE]

## Current handoff.md
[PASTE FULL handoff.md CONTENT HERE]

## Decisions from upfront clarification (HONOR THESE — do not re-ask)
[LIST EVERY DECISION FROM PHASE 1]

## Standing rules
- Proceed on documented defaults. Do NOT ask the user questions unless you hit a hard block.
- A hard block = a missing file that cannot be created, a required credential not obtainable,
  or a compile/test failure you cannot resolve after reasonable effort.
- On hard block: add a clear blocker note to handoff.md Open items and exit.
- On ambiguity: pick the documented default, note it in the handoff under Open items, continue.
- Do NOT expand scope beyond the Next task and its Definition of Done.
- The task is done only when EVERY Definition of Done criterion is verified and checkable.
- Run tsc --noEmit and the test suite before marking done. Report counts.
- Re-write handoff.md using the handoff-document structure before exiting.

## Original task list (context only — execute only the Next task this turn)
[LIST ALL TASKS FROM PHASE 2 WITH THEIR ORIGINAL STATUS]
```

---

## Phase 4 — Check Completion and Decide Whether to Loop

After each subagent returns:

1. Read `handoff.md` fresh.

2. Compare the phase state table against the **locked task list** from Phase 2.

3. **If all originally-locked tasks are now ✅:** proceed to Phase 5.

4. **If a blocker was written:** surface it to the developer. Quote the exact blocker from the
   handoff Open items. Ask the one question needed to unblock, then resume the loop with Phase 3
   once you have the answer. This is the only mid-loop developer interrupt that is acceptable.

5. **If tasks remain and no blocker:** loop back to Phase 3 immediately. Read handoff.md fresh
   to get the updated Next task before composing the next subagent prompt.

6. **Safety cap:** if you have spawned 20 subagents without completing all tasks, pause and
   surface a status summary to the developer. Something may be wrong (runaway scope, repeated
   failures). Show them the phase state table and ask how to proceed.

---

## Phase 5 — Completion Report

When all originally-locked tasks are ✅:

1. Read the final `handoff.md`.
2. Write a concise completion report to the developer:
   - What the effort accomplished (one paragraph, goal-level).
   - A table of every completed task with a one-line outcome note.
   - Any Open items that were deferred to a future phase (not your scope, not a failure).
   - Whether any test failures, type errors, or regressions were found and how they were resolved.
3. Do NOT invent a "Phase N+1" or fabricate follow-up work. If the goal is met, say so.
4. Invoke the **`ingest-handoff` skill** to promote the handoff's durable content into the
   project's long-term stores (`docs/adrs/` for decisions, `docs/memory/` for operational facts).
5. Ask if the developer wants a final commit or PR, then stop.

---

## Edge cases

| Situation | Response |
|---|---|
| `handoff.md` doesn't exist | Say so; offer to run `handoff-document` first, then invoke this skill |
| Handoff goal is vague | Resolve in Phase 1 before proceeding |
| Subagent introduces scope creep | Reject; add the deferred work as an Open item; re-run Phase 3 for the correct next task |
| Subagent updates phase table incorrectly | Read the actual files to verify; use code/test output as ground truth |
| Task depends on an external service not available | Treat as a hard block; surface immediately |
| A task's Definition of Done conflicts with the handoff goal | Raise in Phase 1; don't silently pick one |

---

## What makes subagent briefs fail (avoid these)

| Mistake | Why it fails |
|---|---|
| Omitting the skill instructions | Subagent doesn't know the handoff format |
| Omitting Phase 1 decisions | Subagent re-asks, or picks a different default |
| Stale handoff.md in the prompt | Subagent re-does already-completed work |
| Vague standing rules | Subagent asks questions mid-execution |
| No exit contract | Subagent keeps going past Definition of Done |
| No hard-block definition | Subagent either never stops or silently skips failures |

---

## Quick reference

| Phase | What you do |
|---|---|
| 1 Analyze | Read everything; ask ALL questions at once |
| 2 Lock | Snapshot incomplete tasks; record decisions |
| 3 Spawn | Brief subagent fully; include both skills + handoff + decisions + rules |
| 4 Check | Compare phase table to locked set; loop or surface blocker |
| 5 Report | Declare done; summarize; stop |
