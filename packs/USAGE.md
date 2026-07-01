# packs/ — usage guide

`packs/` is the distributable-plugin workspace of the `ai-personal` monorepo: each
subdirectory bundles one or more skills into a single installable Claude Code plugin,
namespaced as `{pack-name}:{skill-name}` when invoked (e.g. `ponytail:ponytail-review`).
Contrast with `skills/` (a standalone skill used only inside this monorepo) and
`workflows/` (skills that only work together and aren't meant to be installed
elsewhere). See [`README.md`](README.md) for the required `plugin.json` schema and
per-skill structure — this file is about how a pack actually gets built and used, not
how it's laid out.

**Current status: placeholder only.** No pack has been added yet — this file documents
the intended flow so the first one can be dropped in without re-deriving conventions.

## How the pieces fit together

```
packs/{pack-name}/
├── .claude-plugin/plugin.json   ── identifies the installable unit (name, description, version)
├── README.md                     ── what's bundled and why
└── skills/{skill-name}/SKILL.md  ── invoked as {pack-name}:{skill-name}
        │
        ▼
An external project's plugin config (or a marketplace listing) references
packs/{pack-name}/ as a self-contained unit — it does not depend on anything
else in this monorepo, unlike workflows/{name}/.
```

## How to add a pack

1. Create `packs/{pack-name}/.claude-plugin/plugin.json` with `name`, `description`,
   and `version`.
2. Write `packs/{pack-name}/README.md` describing what's bundled and why the skills
   ship together as one plugin.
3. Add one `packs/{pack-name}/skills/{skill-name}/SKILL.md` per skill in the pack,
   following the same frontmatter contract as `skills/{name}/SKILL.md`.
4. Run `bash scripts/validate.sh` to confirm the manifest, README, and each skill's
   `SKILL.md` are all present.
5. Run `bash scripts/catalog.sh` to confirm the pack and its skills appear in the
   generated index.

No example exists yet because no pack has been authored. Follow the structure above
when adding the first one — move a themed group of skills into `packs/` only if it's
actually meant to be installed as a standalone plugin elsewhere; a grouping that's
monorepo-only still belongs in `skills/` or `workflows/`.
