# create-adr — usage guide

See [`SKILL.md`](SKILL.md) for the full procedure this skill follows. This file is
about *how to actually invoke it* and what a run looks like.

## How to use it

Run `/create-adr <title> [context-and-rationale]` when a project needs an architectural
decision recorded. It reads the target project's `docs/specs/adr-template-spec.md` and
`docs/specs/yaml-frontmatter-spec.md` for formatting rules, computes the next `ADR-XXXX`
number from existing files in `docs/adrs/`, asks one clarifying question if context is too
sparse, then writes the ADR and updates `docs/adrs/INDEX.md`.

```
/create-adr adopt React Server Components when building full-stack application features

→ writes docs/adrs/ADR-0001-react-server-components.md
  ---
  status: proposed
  decision_date: 2026-06-30
  description: Adopt React Server Components for server-side rendering and data fetching
  ---
  ## Context
  Building full-stack features; needed to reduce client-side JavaScript...
  ## Decision
  We will adopt React Server Components for all new server-side rendering routes.
  ## Consequences
  Positive: reduced JS bundle, simpler async code
  Negative: requires React 18.3+, steeper learning curve
  Neutral: existing client components coexist

→ adds a row to docs/adrs/INDEX.md
→ reminds you to flip status to `accepted` once formally decided
```
