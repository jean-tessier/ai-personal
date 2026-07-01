#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test-install-docker.sh — Run test-install.sh inside a disposable container.
#
# Full isolation from the host: no network (install.sh's tests use the
# --local seam, not the real fetch), and no host disk writes survive — --rm
# discards the container's writable layer (where test-install.sh's mktemp
# sandboxes live) the moment the run ends. Useful when the host's own shell
# environment (version managers, dotfiles, an existing $HOME/.claude) makes
# local sandboxing awkward to trust.
#
# Requires a running Docker daemon.
# Usage:  bash scripts/test-install-docker.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker run --rm --network none \
  -v "$REPO":/repo:ro \
  -w /repo \
  python:3-slim \
  bash scripts/test-install.sh
