# yaml-frontmatter — usage guide

See [`SKILL.md`](SKILL.md) for the full procedure this skill follows. This file is
about *how to actually invoke it* and what a run looks like.

## How to use it

Four modes, all sourced from `docs/specs/yaml-frontmatter-spec.md` in the target project; if that file doesn't exist yet, copy the bundled `references/yaml-frontmatter-spec.md` template into `docs/specs/` as a starting point and customize it.

```
/yaml-frontmatter                       # validate the current file in conversation
/yaml-frontmatter add <filepath>        # add missing frontmatter
/yaml-frontmatter update <filepath>     # fix non-conforming frontmatter
/yaml-frontmatter check-all             # audit every .md file under docs/
```

Also triggers on "validate the frontmatter", "add frontmatter to", "fix the frontmatter on",
or "audit all docs frontmatter". For `add`/`update` it always proposes the frontmatter block
and waits for confirmation before writing; the body is never touched.

```
/yaml-frontmatter add docs/adr/adr-042.md

(file starts with "# Decision: Migrate to Service Mesh", no frontmatter)

→ proposes:
  ---
  date: 2026-06-30
  description: Decision to migrate the platform to a service mesh for traffic management
  status: draft
  tags: [architecture, service-mesh, infrastructure]
  scope: adr
  ---
→ you confirm → block is prepended, body unchanged
```
