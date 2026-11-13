---
tags: [review-loop]
max_turns: 100
timeout_seconds: 2400
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash, Agent]
---

/review-loop feature/coupons against main. Use Sonnet as the reviewer instead of Opus, and no Haiku: Sonnet does the mechanical fixes too. Cap it at 2 rounds.
