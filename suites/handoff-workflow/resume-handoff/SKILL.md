---
name: resume-handoff
description: Use at the start of a session to resume multi-session work from handoff.md — read the handoff, execute its "Next task" to the definition of done, keep the handoff current as you go, then re-write it for the following session. Triggers on "resume", "continue from the handoff", "pick up where we left off", "/resume-handoff", or a session that begins by referencing @handoff.md. Pairs with the handoff-document skill (the write side) to form a loop of sessions that runs until the handoff's goal is met.
---

# Resume Handoff

## The session loop

This skill is the **resume side** of a two-skill loop. `handoff-document` writes `handoff.md`;
this skill consumes it, does the work, and hands off again. Conceptually:

```
        ┌──────────────────────── next session ────────────────────────┐
        ▼                                                               │
  /resume-handoff  ──►  execute the "Next task"  ──►  handoff-document  ┘
  (read handoff.md)     (to its Definition of Done)   (re-write handoff.md
                                                        for the next session)

  The loop repeats, each session instructed by the last via handoff.md,
  and TERMINATES when handoff.md shows the overall goal is met.
```

Each invocation is **one turn of the crank**: orient → execute → re-handoff. You are both the
worker for *this* handoff and the author of the *next* one. The next session should be able to
start with zero re-orientation — that is the contract you inherit and the contract you leave.

## When to use

- The first action in a fresh session (typically right after `/clear`) that is meant to continue
  ongoing work — especially if the opening prompt references `@handoff.md`.
- Any time the user says "resume", "continue the handoff", "pick up where we left off", "keep going".

If there is no `handoff.md` at the project root, there is nothing to resume: say so, and point to
the `handoff-document` skill to create the first one (or just start the work and hand off at the end).

## Steps

### 1. Load and absorb the handoff

- Read `handoff.md` at the project root in full.
- Follow its **"Read before coding"** list (the ordered docs/files it names) — that list exists
  precisely so you don't have to re-explore. Read those before touching code.
- Extract, explicitly: **what was completed last session**, the **Next task** (goal, files,
  constraints, tests, **Definition of done**, what's NOT in scope), the **Open items**, and any
  **standing caveats**. These govern the rest of the session.

### 2. Confirm the plan and clear blockers

- Restate the Next task and your intended approach in one short paragraph so the user can correct
  course before you build.
- Resolve any **Open items that block the Next task** first. If the handoff marks a decision as
  "open — resolve before starting", make a recommendation and get the user's call (or proceed on
  the documented default if one is given). Do not silently skip a blocking decision.
- Track the work with a todo list when the task is multi-step.

### 3. Execute to the Definition of Done

- Do the Next task, honoring its **Key constraints** and **standing caveats** as hard rules
  (they flag rework, not style). Respect the **NOT in scope** list — do not over-build.
- Write/extend the tests the handoff specifies; **verify** (run the suite / build / the app) and
  report results faithfully. The task is not done until its Definition of Done is checkably met.

### 4. Keep the handoff live as you work

- Treat `handoff.md` as the durable record of state, not a one-shot at the end. Update it at
  meaningful milestones — a sub-task completes, scope shifts, a new blocker or decision appears —
  so that if the session is cut short, what remains is still a usable handoff.
- This is cheap insurance: an interrupted session should never leave the next one stranded.

### 5. Re-handoff for the next session

When the Next task is complete (or the session is ending), **invoke the `handoff-document` skill**
to re-write `handoff.md` for the following session. Do not hand-roll the structure — that skill owns
the required sections (Completed work, Phase state table, Next task, Open items). Your job here is to
feed it accurate inputs:

- Move the just-finished task to ✅ in the phase state table; promote the next one to 🔜.
- Write the new **Next task** section with enough detail to start cold — read-order, constraints,
  data shapes, specific tests, Definition of done, and what's out of scope.
- Carry forward unresolved **Open items**; drop resolved ones (note the outcome).
- Convert any relative dates to absolute; reflect the real commit/branch state.

Follow the project's commit conventions: commit only when the user asks, and match how the repo has
been committing (branch vs. main, granularity). The handoff itself is usually left uncommitted for
the next session to pick up unless the user says otherwise.

### 6. Know when to stop the loop

The loop has a terminating condition — **the overall goal stated in `handoff.md` / the roadmap**.
Before writing another "Next task", check whether the goal is actually met:

- If the phase state table shows all planned work done and nothing meaningful remains, **declare the
  goal met**. Summarize what the whole effort achieved, and write a closing handoff that records
  completion (no fabricated next task) rather than inventing busywork to keep the loop alive.
  Then invoke the **`ingest-handoff` skill** to promote the handoff's durable content into
  `docs/adrs/` and `docs/memory/` for long-term persistence.
- If work remains, hand off the next increment and let the next session resume.

## Edge cases

- **No `handoff.md`:** nothing to resume — say so; offer to create the first handoff via
  `handoff-document`, or to just begin and hand off at the end.
- **Handoff disagrees with reality** (a named file/decision no longer exists, tests already fail on
  arrival): surface the discrepancy before acting on the stale instruction; fix or re-plan rather
  than blindly following it.
- **Next task is ambiguous or the goal is unclear:** ask one focused question rather than guessing —
  a wrong turn here costs the next session too.
- **Scope creep:** if mid-task you discover larger work, capture it as an Open item / future-phase
  candidate in the handoff instead of expanding this session's scope.

## Quick reference

| Step | What it answers |
|---|---|
| 1 Load | What was done, what's next, the rules and the goal |
| 2 Confirm | Is the plan right, and are blocking decisions resolved? |
| 3 Execute | Is the Next task done to its Definition of Done, verified? |
| 4 Keep live | If interrupted now, is the handoff still usable? |
| 5 Re-handoff | Can the next session start cold? (via handoff-document) |
| 6 Stop? | Is the overall goal met — end the loop, or hand off again |
