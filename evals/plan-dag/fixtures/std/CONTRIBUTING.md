# Contributing

- Keep each pull request at or under 200 changed lines (additions plus deletions, tests included). Split anything
  larger into several PRs.
- Every PR needs one approving review and a green CI run (`.github/workflows/ci.yml`) before it is merged.
- A maintainer squash-merges approved PRs into `main`. There is no deploy pipeline in this repository; the
  operations team deploys tagged releases by hand.
- Read the architecture decisions in `docs/adrs/` before proposing structural changes.
