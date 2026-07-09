#!/usr/bin/env bash
# Prereq installer for the Capability-Scoped Agent Suite.
# Installs the CORE toolchain (search/structural + gate utilities) the agents shell
# out to, then runs the preflight doctor. Stack toolchains are opt-in: --java, --web.
# Windows: run this under WSL (comby is Linux-only anyway).
#
# Usage: install-prereqs.sh [--java] [--web] [--dry-run] [--yes]
set -uo pipefail

want_java=0 want_web=0 dry=0
for a in "$@"; do case "$a" in
  --java) want_java=1;; --web) want_web=1;;
  --dry-run) dry=1;;
  --yes|-y) ;;  # apt-get already hard-codes -y; brew does not prompt — flag is a no-op
  -h|--help) sed -n '2,9p' "$0"; exit 0;;
  *) echo "unknown flag: $a" >&2; exit 2;;
esac; done

run()  { echo "+ $*"; [ "$dry" -eq 1 ] || "$@"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- detect platform / package manager ----
os=$(uname -s); mgr=""
if [ "$os" = "Darwin" ]; then
  have brew || { echo "Homebrew required on macOS: https://brew.sh" >&2; exit 1; }
  mgr=brew
elif [ "$os" = "Linux" ]; then
  if   have apt-get; then mgr=apt
  elif have brew;    then mgr=brew
  else echo "No supported package manager (need apt or Homebrew)." >&2; exit 1; fi
else
  echo "Unsupported OS '$os'. On Windows, run this under WSL." >&2; exit 1
fi
echo "platform: $os · package manager: $mgr"

# ---- Node is a hard prerequisite (drives ast-grep, ajv, Tier-2 scripts) ----
if ! have node; then
  echo "Node.js not found. Install Active LTS (>=24) first, then re-run:" >&2
  echo "  nvm install --lts && nvm use --lts   (or winget install OpenJS.NodeJS.LTS)" >&2
  exit 1
fi
node_major=$(node -v | sed 's/^v\([0-9]*\).*/\1/')
[ "$node_major" -ge 24 ] || echo "WARN: Node $(node -v) < 24 (Active LTS). Works, but pin >=24 for parity."

# ---- CORE: search / structural + make ----
case "$mgr" in
  brew)
    run brew install ripgrep fd ast-grep jq tokei comby make
    ;;
  apt)
    run sudo apt-get update
    run sudo apt-get install -y ripgrep fd-find jq make build-essential
    have fd || echo "note: Debian/Ubuntu ships fd as 'fdfind' — add: alias fd=fdfind"
    run npm install -g @ast-grep/cli
    if   have cargo; then run cargo install tokei
    elif have snap;  then run sudo snap install tokei
    else echo "note: install tokei via cargo or snap (neither found)"; fi
    if ! have comby; then
      cv=1.8.1 ct="comby-${cv}-x86_64-linux.tar.gz"
      csum=ec0ca6477822154d71033e0b0a724c23a0608b99028ecab492bc9876ae8c458a
      echo "+ installing comby ${cv} (pinned, sha256-verified)"
      if [ "$dry" -ne 1 ]; then
        t=$(mktemp -d)
        if curl -fsSL -o "$t/$ct" "https://github.com/comby-tools/comby/releases/download/${cv}/${ct}" \
             && echo "$csum  $t/$ct" | sha256sum -c - \
             && tar -xzf "$t/$ct" -C "$t"; then
          sudo install -m 755 "$t/comby-${cv}-x86_64-linux" /usr/local/bin/comby
        else
          echo "note: comby install failed (download/checksum mismatch) — install manually from https://github.com/comby-tools/comby/releases"
        fi
        rm -rf "$t"
      fi
    fi
    ;;
esac

# ---- gate utilities ----
run npm install -g ajv-cli ajv-formats

# ---- sg collision guard ----
if have sg && ! sg --version 2>&1 | grep -qi 'ast-grep'; then
  echo "WARN: 'sg' resolves to util-linux set-group, not ast-grep."
  echo "      Use the 'ast-grep' binary in scripts, or add: alias sg=ast-grep"
fi

# ---- optional stack toolchains ----
if [ "$want_java" -eq 1 ]; then
  echo "== Java stack (Temurin/Corretto — NOT Oracle JDK) =="
  if   have sdk;          then run sdk install java 21.0.7-tem; run sdk install maven
  elif [ "$mgr" = brew ]; then run brew install --cask temurin@21; run brew install maven
  else echo "Install SDKMAN (sdkman.io), then: sdk install java 21.0.7-tem && sdk install maven"; fi
fi
if [ "$want_web" -eq 1 ]; then
  echo "== Angular / Ionic CLIs =="
  run npm install -g @angular/cli @ionic/cli
fi

# ---- preflight ----
here=$(cd "$(dirname "$0")" && pwd)
echo; echo "== running preflight doctor =="
if [ "$dry" -eq 1 ]; then echo "(dry-run: skipping preflight)"; else bash "$here/preflight.sh"; fi
