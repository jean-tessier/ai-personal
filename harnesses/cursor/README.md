# harnesses/cursor/

Configuration for the Cursor IDE harness.

## rules/

Cursor rules files. These are both customisation (changing Cursor's default
behaviour) and extension (teaching Cursor project-specific conventions).

File naming convention:
- `{scope}.mdc`           — scoped rule (attach to specific files/dirs)
- `{scope}.cursorrules`   — legacy format

Document the intent of each rule file in a comment block at the top.

## Usage

Copy or symlink rule files from here into your project's `.cursor/rules/`
directory (or project root for `.cursorrules`).
