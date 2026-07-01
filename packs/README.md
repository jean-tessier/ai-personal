# packs/

Distributable bundles of skills, packaged as installable Claude Code plugins. A pack
groups one or more independently-invocable skills that ship together as one plugin
(namespaced `{pack-name}:{skill-name}` at invocation, e.g. `ponytail:ponytail-review`) —
as distinct from `skills/` (a standalone skill used only within this monorepo) and
`workflows/` (skills that only function together and break apart if separated).

## Packs vs. skills vs. workflows

| Dimension | `skills/{name}/` | `workflows/{name}/` | `packs/{name}/` |
|---|---|---|---|
| Invocable alone | Yes | No — components reference each other | Yes, per skill |
| Distributable outside this repo | No — monorepo-internal | No | Yes — installable as a Claude Code plugin |
| Skills reference each other | N/A | Yes, by design | No — bundled for packaging, not coupling |

## Structure per pack

```
{pack-name}/
├── .claude-plugin/
│   └── plugin.json     # Plugin manifest: name, description, version
├── README.md            # What this pack bundles and why they're grouped together
└── skills/
    └── {skill-name}/
        ├── SKILL.md      # The skill: procedure, constraints, examples
        ├── CHANGELOG.md  # Date · model-version · what changed and why
        └── examples/     # Invocation examples or input/output pairs
```

Each `{skill-name}/` follows the exact same shape and frontmatter contract as a
standalone skill — see [`skills/README.md`](../skills/README.md). The only difference
is packaging: a pack's skills ship together as one plugin instead of being invoked
directly by their bare name.

## plugin.json schema

```json
{
  "name": "pack-name",
  "description": "One sentence — what this pack bundles and why.",
  "version": "0.1.0"
}
```

`name` becomes the plugin namespace prefix (`{name}:{skill-name}`) every skill in the
pack is invoked under. Optional fields (`author`, `homepage`, `keywords`) may be added
if a pack needs them — not required for `scripts/validate.sh` to pass.

## Naming

Kebab-case for both the pack directory and every skill inside it, same rule as
`skills/{name}/`.

## Available packs

_(none yet — this workspace is a scaffold; see [`USAGE.md`](USAGE.md) for how to add the first one)_
