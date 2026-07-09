#!/usr/bin/env bash
# Preflight doctor: presence + version for the toolchain the agents shell out to.
# Same ethos as `make check` but for the tools themselves. A non-zero exit means
# "not ready to encode" — a missing hard-gate binary does not fail loudly at runtime,
# it silently no-ops, so verify presence up front.
set -uo pipefail
miss=0

check() {  # $1 = binary, $2 = version flag ; a miss fails preflight
  if command -v "$1" >/dev/null 2>&1; then
    printf '  ok    %-9s %s\n' "$1" "$("$1" $2 2>&1 | head -1)"
  else
    printf '  MISS  %-9s (not found)\n' "$1"; miss=1
  fi
}
check_soft() {  # optional tool: report, never fail preflight
  if command -v "$1" >/dev/null 2>&1; then
    printf '  ok    %-9s %s\n' "$1" "$("$1" $2 2>&1 | head -1)"
  else
    printf '  --    %-9s (optional, not found)\n' "$1"
  fi
}

echo "Core search / structural:"
for b in rg fd ast-grep jq tokei comby make node npm; do check "$b" --version; done

# ast-grep sg-collision guard
if command -v sg >/dev/null 2>&1 && ! sg --version 2>&1 | grep -qi 'ast-grep'; then
  echo "  WARN  sg resolves to a non-ast-grep binary (util-linux). Use 'ast-grep' or alias sg=ast-grep."
fi

# Stack-conditional (only checked if the project is present)
[ -f pom.xml ]      && { echo "Java stack:"; for b in java mvn; do check "$b" --version; done; }
[ -f package.json ] && { echo "Node stack:"; check npx --version; }

echo "Gate utilities:"
check_soft ajv --version   # optional — the jq -e fallback covers the handoff gate

echo
[ "$miss" -eq 0 ] && echo "PREFLIGHT: ready." || echo "PREFLIGHT: missing core binaries."
exit "$miss"
