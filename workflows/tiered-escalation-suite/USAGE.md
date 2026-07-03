# tiered-escalation-suite — usage guide

See [`README.md`](README.md) for what this suite does, its components, and conventions.
This file is about *how to actually deploy and run it* in a target project.

## How to use it

Reach for this when you want a GitHub Copilot/VS Code repo to get a capability-scoped
agent setup — a read-only Surveyor, a diff-gated Transformer, and a Verifier subagent —
governed by hard gates (diff-before-apply, `make check`, cross-checks) instead of
prose-only discipline. This is a deploy-and-open workflow, not a dispatch-a-prompt one:
there's no Claude Code entry point, because none of these files are read by Claude
Code — they're Copilot-native (`.agent.md`, `.github/skills/*/SKILL.md`,
`.github/hooks/*.json`).

1. Copy the payload into the target repo's root:
   ```bash
   cp -R workflows/tiered-escalation-suite/.github       <target-repo>/.github
   cp -R workflows/tiered-escalation-suite/.vscode        <target-repo>/.vscode
   cp -R workflows/tiered-escalation-suite/.devcontainer  <target-repo>/.devcontainer
   cp -R workflows/tiered-escalation-suite/scripts        <target-repo>/scripts
   cp -R workflows/tiered-escalation-suite/scratch        <target-repo>/scratch
   cp    workflows/tiered-escalation-suite/Makefile       <target-repo>/Makefile
   cp    workflows/tiered-escalation-suite/.gitignore     <target-repo>/.gitignore
   ```
   Merge `Makefile` / `.gitignore` / `.vscode/settings.json` by hand instead of
   overwriting if the target repo already has one. Skip `.devcontainer/` if you'd
   rather install the toolchain on the host (step 2 below) than in a container.

2. Get the toolchain the agents shell out to onto the machine that will run them —
   either a devcontainer, or the bare host:
   - **Devcontainer** (reproducible, no host installs): open the target repo in VS
     Code and "Reopen in Container" — `.devcontainer/Dockerfile` builds the same
     `scripts/install-prereqs.sh` toolchain into the image. If the target repo builds
     a Java and/or Angular/Ionic stack, set `INSTALL_JAVA`/`INSTALL_WEB` to `"true"`
     in `.devcontainer/devcontainer.json`'s `build.args` before building.
   - **Host** (no container): run the installer directly, then confirm readiness:
     ```bash
     bash scripts/install-prereqs.sh              # preview first with: --dry-run
     bash scripts/install-prereqs.sh --java --web # if the target repo builds both stacks
     bash scripts/preflight.sh                    # non-zero exit = not ready to encode
     ```

3. Open the target repo in VS Code with Copilot **agent mode** (skills don't load in Ask
   mode), and enable the Preview flags for hooks + custom-agent-as-subagent per the
   current Copilot release notes.

4. Dispatch by capability, in prose — there's no slash-command entry point:
   - Read-only (find / count / map / aggregate) → **Surveyor**.
   - Mutating (rewrite / rename / codemod) → **Transformer**.
   - Never address **Verifier** directly — Transformer hands off to it after every apply.

## Example

Asking the Transformer to rename an API call across a TypeScript codebase:

```
# Dispatch to Transformer:
"Rename fetchUser to getUser everywhere in src/."

Transformer consults trigger-semantics → volume/repetition trigger met → Tier 1
  → runs the astgrep-rewrite skill's bundled script:
    .github/skills/astgrep-rewrite/scripts/preview-rewrite.sh \
      'fetchUser($$$A)' 'getUser($$$A)' ts
    → writes scratch/handoff/pending.diff and prints it for review

# PreToolUse hook (block-apply-without-diff.json) now sees pending.diff exists,
# so the apply command is allowed to run:
ast-grep -p 'fetchUser($$$A)' -r 'getUser($$$A)' --lang ts --update-all

# PostToolUse hook (run-make-check.json) fires automatically:
make check → exit 0

# Transformer hands off to Verifier, which never reports to the user directly:
Verifier re-runs `make check`, cross-checks the callsite count two independent ways
  (ast-grep --json | jq length   vs.   rg -c 'fetchUser\(' | awk -F: '{s+=$2} END{print s}')
  via scripts/crosscheck.sh, and validates any scratch/handoff/*.json against
  scripts/handoff.schema.json via scripts/validate-handoff.sh
  → returns "pass"

# Only now does Transformer report success back to the user.
```

If a task instead asks "how many places call `fetchUser`?", the orchestrator contract
routes it to **Surveyor** (read-only genre) instead — it never touches `edit_file`.
