# Changelog

Format: `YYYY-MM-DD · {model-version} · {what changed and why}`

2026-07-08 · Claude Sonnet 5 · Dropped auto-fix/manual-authorship handling for packs, agent
prompts, MCP manifests, and eval alignment — those categories were removed from the repo, so
`scripts/validate.sh` no longer emits their FAIL/warn lines.
