# tiered-team-orchestration — usage guide

See [`README.md`](README.md) for what this suite does, the pattern diagram, and the
tier-to-vendor mapping. This file is about *how to actually dispatch it* for a given task.

## How to use it

Reach for this when a task is big enough to split across research, implementation, and
review, and you want the expensive reasoning concentrated at the top instead of spent
uniformly across every step. Each file in `agents/` is a role prompt: a YAML frontmatter
block declaring `model` (the tier that role runs at) plus the usual `name`/`description`/
`tools`/`agents` fields, mapping directly onto a Claude Code subagent definition. On another
harness, adapt the frontmatter to that harness's subagent/model-routing mechanism — the
three-tier structure and the prompt bodies underneath don't change.

Dispatch [`agents/01-core-orchestrator.md`](agents/01-core-orchestrator.md) with the task;
it decomposes the work into team-scoped assignments and dispatches
[`agents/02-research-lead.md`](agents/02-research-lead.md),
[`agents/03-coding-lead.md`](agents/03-coding-lead.md), and
[`agents/04-review-lead.md`](agents/04-review-lead.md) in turn. Each lead dispatches its own
Haiku-tier workers ([`05-research-worker.md`](agents/05-research-worker.md),
[`06-coding-worker.md`](agents/06-coding-worker.md),
[`07-review-worker.md`](agents/07-review-worker.md)) and returns one synthesized result to
the Orchestrator. Workers never see the whole task and never talk to each other or to the
Orchestrator directly — only their lead.

## Example

Dispatching the Core Orchestrator for "Add rate limiting to the API":

```
# Initial dispatch to the Core Orchestrator
{
  "goal": "Add rate limiting to the API",
  "repo": "<repo pointer>"
}
```

```
01-Core-Orchestrator (Opus-tier)
  decomposes the goal into three team-scoped assignments:
    research: "How is the API request path structured today? Where would a rate
               limiter hook in, and what's already used for shared state (Redis, etc.)?"
    coding:   "Add a rate-limiting middleware in front of the request handlers,
               configurable per-route, backed by the existing Redis client."
    review:   "Review the rate-limiting change for correctness and — since it sits
               on a trust boundary (public API) — for abuse/bypass risk."
  → dispatches Research Lead
```

```
01-Core-Orchestrator → 02-Research-Lead (Sonnet-tier)
  decomposes the research assignment into 3 narrow lookups, fans them out:
    05-Research-Worker (Haiku) → "Find every request-handling entry point under src/api/."
    05-Research-Worker (Haiku) → "Find the existing Redis client wrapper and its usage."
    05-Research-Worker (Haiku) → "Find any existing throttling/quota code to reuse or avoid duplicating."
  → 3 workers return structured findings (file:line pointers) in parallel
  Research Lead synthesizes:
  { "status": "BRIEF_READY",
    "entry_points": ["src/api/router.py:42", "src/api/router.py:88"],
    "redis_client": "src/infra/redis_client.py:1 (RedisClient)",
    "existing_throttling": "none found" }
  → returns synthesis to Core Orchestrator
```

```
01-Core-Orchestrator → 03-Coding-Lead (Sonnet-tier)
  decomposes the coding assignment into scoped edits using the research synthesis,
  dispatches each to a Coding Worker:
    06-Coding-Worker (Haiku) → "Add RateLimiter class in src/api/rate_limit.py using RedisClient."
    06-Coding-Worker (Haiku) → "Wire RateLimiter into src/api/router.py:42 and :88 as middleware."
    06-Coding-Worker (Haiku) → "Add per-route rate-limit config to src/api/config.py."
  → 3 workers return the edits they made
  Coding Lead synthesizes:
  { "status": "CHANGES_READY",
    "files_changed": ["src/api/rate_limit.py", "src/api/router.py", "src/api/config.py"],
    "summary": "Redis-backed rate limiter, applied at both entry points, configurable per route." }
  → returns synthesis to Core Orchestrator
```

```
01-Core-Orchestrator
  the change touches a trust boundary (public API) → escalates the review dispatch
  to the Opus-tier variant of 04-Review-Lead

01-Core-Orchestrator → 04-Review-Lead (Opus-tier, escalated)
  decomposes the review into focused checks, dispatches each to a Review Worker:
    07-Review-Worker (Haiku) → "Check: does every entry point in router.py actually
                                 go through RateLimiter, or is any path unguarded?"
    07-Review-Worker (Haiku) → "Check: can the rate-limit key be spoofed via a
                                 client-controlled header?"
    07-Review-Worker (Haiku) → "Check: does RedisClient failure fail open or closed?"
  → 3 workers return pass/fail with evidence
  Review Lead synthesizes a verdict:
  { "status": "APPROVED",
    "note": "Redis failure currently fails open — acceptable for v1, flag for follow-up." }
  → returns synthesis to Core Orchestrator
```

```
# Final integration and report from the Core Orchestrator:
DONE — Rate limiting added at both API entry points, Redis-backed, configurable per
route. Reviewed at Opus-tier due to the public-API trust boundary; approved with one
follow-up note (Redis failure currently fails open).
```
