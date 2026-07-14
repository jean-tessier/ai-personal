#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# install.sh — Vendor-agnostic installer: fetch this repo, resolve which
# assets go where for a chosen harness/scope, and copy them.
#
# Usage:  curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh \
#           | bash -s -- --harness claude-code --scope project --assets skills
#
# Flags:
#   --harness <key>     harness key from scripts/harnesses.json (required)
#   --scope <key>       scope key declared for that harness (required)
#   --assets <a,b,...>  comma-separated asset categories (default: all available;
#                       interactively pick per category if omitted and a TTY
#                       is attached — via fzf, gum, or a numbered prompt)
#   --dry-run           print planned copy operations; write nothing
#   --force             overwrite existing destination files/dirs (default: skip)
#   --no-deps           don't auto-include a selected suite's declared skill dependencies
#   -h, --help          show usage
#
# Exit:   0 success · 1 bad input or fetch/copy failure
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

OWNER="jean-tessier"
REPO_NAME="ai-personal"
REF="main"

ALL_CATEGORIES=(skills suites)

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLD='\033[1m'; NC='\033[0m'
_ok()   { printf "${GRN}    ok${NC}  %s\n" "$1"; }
_fail() { printf "${RED}  FAIL${NC}  %s\n" "$1" >&2; }
_warn() { printf "${YLW}  note${NC}  %s\n" "$1"; }
_head() { printf "\n${BLD}── %s ──${NC}\n" "$1"; }

# True for the one (harness, category) pair install.sh currently knows how to
# translate a plugin-shaped item for post-copy (see translate_to_copilot()).
# Centralized so select_assets()'s eligibility filter and apply_selection()'s
# dry-run note / real translate-call can't drift out of sync with each other.
is_copilot_suite_category() { [[ "$HARNESS" == "copilot" && "$1" == "suites" ]]; }

command -v python3 &>/dev/null || { _fail "python3 is required to parse catalog/harness JSON"; exit 1; }

usage() {
  cat <<'USAGE'
Usage: install.sh --harness <name> --scope <scope> [--assets <cat1,cat2,...>] [--dry-run] [--force] [--no-deps]

  --harness   harness key from scripts/harnesses.json (e.g. claude-code, copilot)
  --scope     scope key declared for that harness (e.g. project, user)
  --assets    comma-separated asset categories to install (default: all available;
              if omitted with a TTY attached, pick interactively via fzf/gum/prompt)
  --dry-run   print planned copy operations; write nothing
  --force     overwrite existing destination files/dirs (default: skip existing)
  --no-deps   don't auto-include a selected suite's declared skill dependencies
  -h, --help  show this help
USAGE
}

ASSETS_RAW=""
HARNESS=""
SCOPE=""
DRY_RUN=0
FORCE=0
NO_DEPS=0
LOCAL_PATH=""   # test seam: skip network fetch, use a local checkout instead

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CATALOG_JSON="$WORK/catalog.json"
SELECTION_FILE="$WORK/selection.tsv"
SRC=""
HARNESSES_JSON=""
CATEGORIES=()

# ── JSON access (single dispatcher; python3 is the only non-stdlib dependency) ─
# ponytail: piped through `tr -d '\r'` — a native Windows python3 writes CRLF to
# stdout even when piped, which corrupts every `read -r`/`cp` consumer of this
# output ("cannot stat '...suite'$'\r'"). set -o pipefail (part of this script's
# top-level set -euo pipefail) keeps python's own exit code flowing through the
# pipe, since tr always exits 0.
_json() {
  { CATALOG_JSON="$CATALOG_JSON" HARNESSES_JSON="$HARNESSES_JSON" python3 - "$@" <<'PY'
import json, os, sys

def load(path):
    with open(path) as f:
        return json.load(f)

def find_item(catalog, category, name):
    for it in catalog.get("assets", {}).get(category, []):
        if it["name"] == name:
            return it
    return None

mode = sys.argv[1]
args = sys.argv[2:]

if mode == "harness_exists":
    harnesses = load(os.environ["HARNESSES_JSON"])
    sys.exit(0 if args[0] in harnesses else 1)

elif mode == "harness_keys":
    harnesses = load(os.environ["HARNESSES_JSON"])
    print(" ".join(sorted(harnesses)))

elif mode == "scope_root":
    harnesses = load(os.environ["HARNESSES_JSON"])
    root = harnesses.get(args[0], {}).get("scopes", {}).get(args[1])
    if root is None:
        sys.exit(1)
    print(root)

elif mode == "scope_keys":
    harnesses = load(os.environ["HARNESSES_JSON"])
    print(" ".join(sorted(harnesses.get(args[0], {}).get("scopes", {}))))

elif mode == "mapping":
    harnesses = load(os.environ["HARNESSES_JSON"])
    tmpl = harnesses.get(args[0], {}).get("mapping", {}).get(args[1])
    if tmpl is None:
        sys.exit(1)
    print(tmpl)

elif mode == "categories":
    catalog = load(os.environ["CATALOG_JSON"])
    assets = catalog.get("assets", {})
    cats = [c for c in ("skills", "suites") if assets.get(c)]
    print(" ".join(cats))

elif mode == "items":
    catalog = load(os.environ["CATALOG_JSON"])
    assets = catalog.get("assets", {})
    category = args[0]
    items = []
    for it in assets.get(category, []):
        items.append((it["name"], it["path"]))
    for name, path in items:
        print(f"{name}\t{path}")

elif mode == "item_path":
    catalog = load(os.environ["CATALOG_JSON"])
    it = find_item(catalog, args[0], args[1])
    if it is None:
        sys.exit(1)
    print(it["path"])

elif mode == "suite_deps":
    catalog = load(os.environ["CATALOG_JSON"])
    it = find_item(catalog, "suites", args[0])
    print(" ".join(it.get("dependencies", [])) if it else "")

elif mode == "suite_plugin_shaped":
    catalog = load(os.environ["CATALOG_JSON"])
    it = find_item(catalog, "suites", args[0])
    sys.exit(0 if it and it.get("pluginShaped") else 1)

else:
    sys.exit(f"unknown mode: {mode}")
PY
  } | tr -d '\r'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --assets)  ASSETS_RAW="$2"; shift 2 ;;
      --harness) HARNESS="$2"; shift 2 ;;
      --scope)   SCOPE="$2"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --force)   FORCE=1; shift ;;
      --no-deps) NO_DEPS=1; shift ;;
      --local)   LOCAL_PATH="$2"; shift 2 ;;  # undocumented test seam
      -h|--help) usage; exit 0 ;;
      *) _fail "unknown flag: $1"; usage; exit 1 ;;
    esac
  done

  # ponytail: explicit if/fi, not `cond && { ...; exit 1; }` — the latter's
  # false-branch exit status becomes parse_args's own return status under
  # `set -e` when it's the function's last statement, which then aborts the
  # (unguarded) caller even though nothing actually went wrong.
  if [[ -z "$HARNESS" ]]; then _fail "--harness is required"; usage; exit 1; fi
  if [[ -z "$SCOPE"   ]]; then _fail "--scope is required"; usage; exit 1; fi
}

# ── Fetch (no git — curl + tar only) ────────────────────────────────────────
fetch_source() {
  if [[ -n "$LOCAL_PATH" ]]; then
    SRC="$LOCAL_PATH"
    return
  fi
  local url="https://codeload.github.com/${OWNER}/${REPO_NAME}/tar.gz/${REF}"
  _head "fetching ${OWNER}/${REPO_NAME}@${REF}"
  curl -fsSL "$url" -o "$WORK/src.tar.gz"
  tar -xzf "$WORK/src.tar.gz" -C "$WORK"
  SRC="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d | head -1)"
}

build_catalog() {
  bash "$SRC/scripts/catalog.sh" > "$CATALOG_JSON"
  HARNESSES_JSON="$SRC/scripts/harnesses.json"
}

validate_harness_and_scope() {
  if ! _json harness_exists "$HARNESS"; then
    _fail "unknown harness '$HARNESS' (available: $(_json harness_keys))"
    exit 1
  fi
  if ! _json scope_root "$HARNESS" "$SCOPE" >/dev/null; then
    _fail "harness '$HARNESS' has no scope '$SCOPE' (available: $(_json scope_keys "$HARNESS"))"
    exit 1
  fi
}

resolve_categories() {
  if [[ -z "$ASSETS_RAW" ]]; then
    read -r -a CATEGORIES <<< "$(_json categories)"
    return
  fi
  IFS=',' read -r -a CATEGORIES <<< "$ASSETS_RAW"
  local c
  for c in "${CATEGORIES[@]}"; do
    if [[ ! " ${ALL_CATEGORIES[*]} " == *" $c "* ]]; then
      _fail "unknown asset category '$c' (known: ${ALL_CATEGORIES[*]})"
      exit 1
    fi
  done
}

# ── Interactive picker (Task 4) ──────────────────────────────────────────────
# Renders a subset-choice UI over an items_file (name<TAB>src_rel per line)
# and prints the chosen lines in the same 2-column format to stdout. Tries
# fzf, then gum, then a numbered read-loop — whichever renders, select_assets
# only ever sees the resulting subset of (name, src_rel) pairs.
pick_items() {
  local category="$1" items_file="$2" chosen_names

  if command -v fzf &>/dev/null; then
    chosen_names="$(cut -f1 "$items_file" | fzf -m --prompt="${category}> " --header="tab: toggle · enter: confirm")"
  elif command -v gum &>/dev/null; then
    chosen_names="$(cut -f1 "$items_file" | gum choose --no-limit --header "select ${category} (space: toggle, enter: confirm)")"
  else
    _read_loop_pick "$category" "$items_file"
    return
  fi

  if [[ -z "$chosen_names" ]]; then
    return
  fi

  # ponytail: pass chosen_names via ENVIRON, not -v — macOS's /usr/bin/awk
  # (One True Awk) chokes on a literal newline inside a -v assignment.
  CHOSEN_NAMES="$chosen_names" awk -F'\t' '
    BEGIN { n = split(ENVIRON["CHOSEN_NAMES"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1 }
    want[$1]
  ' "$items_file"
}

# Fallback when neither fzf nor gum is on PATH: list items 1..N to stderr,
# read a comma/space-separated list of numbers (or a/all) from stdin.
_read_loop_pick() {
  local category="$1" items_file="$2"
  local i=0 idx=0 name src_rel reply low n

  _head "select ${category}" >&2
  while IFS=$'\t' read -r name src_rel; do
    i=$((i + 1))
    printf '  %d) %s\n' "$i" "$name" >&2
  done < "$items_file"
  printf 'Enter numbers (comma/space-separated), or "a" for all: ' >&2
  read -r reply

  low="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
  if [[ "$low" == "a" || "$low" == "all" ]]; then
    cat "$items_file"
    return
  fi

  while IFS=$'\t' read -r name src_rel; do
    idx=$((idx + 1))
    for n in ${reply//,/ }; do
      if [[ "$n" == "$idx" ]]; then
        printf '%s\t%s\n' "$name" "$src_rel"
      fi
    done
  done < "$items_file"
}

# ── Selection step ──────────────────────────────────────────────────────────
# Flag-driven: every item in each requested category, resolved to a concrete
# destination path, written to $SELECTION_FILE as
# "category<TAB>name<TAB>src_rel<TAB>dest_rel". When no --assets was passed
# AND stdin is a real TTY, the full per-category item list is routed through
# pick_items() first so the user chooses a subset — otherwise (explicit
# --assets, or no TTY) every item is taken, same as before Task 4.
#
# ponytail: undocumented test seam — INSTALL_FORCE_INTERACTIVE=1 bypasses the
# `[[ -t 0 ]]` check (mirrors --local's role for fetch_source), so the picker
# path can be exercised from a script with no real TTY attached.
select_assets() {
  : > "$SELECTION_FILE"
  local category template found name src_rel dest_rel items_file
  local interactive=0
  if [[ -z "$ASSETS_RAW" ]]; then
    if [[ -t 0 ]] || [[ -n "${INSTALL_FORCE_INTERACTIVE:-}" ]]; then
      interactive=1
    fi
  fi

  for category in "${CATEGORIES[@]}"; do
    if ! template=$(_json mapping "$HARNESS" "$category"); then
      _warn "category '$category' has no mapping for harness '$HARNESS' — skipped"
      continue
    fi

    items_file="$WORK/items.tsv"
    _json items "$category" > "$items_file"

    found=0
    if [[ -s "$items_file" ]]; then found=1; fi

    # SELECTION STEP (Task 4 plug-in point)
    if [[ $found -eq 1 && $interactive -eq 1 ]]; then
      pick_items "$category" "$items_file" > "$WORK/picked.tsv"
      items_file="$WORK/picked.tsv"
      if [[ ! -s "$items_file" ]]; then
        _warn "category '$category': nothing selected — skipping"
      fi
    fi

    while IFS=$'\t' read -r name src_rel; do
      [[ -z "$name" ]] && continue
      # Copilot only understands the plugin-shaped suites install.sh knows how to
      # translate (see translate_to_copilot()) — a suite without a
      # .claude-plugin/plugin.json at its root (a drop-in Copilot payload, or a
      # multi-harness suite that ships its own hand-authored Copilot variant
      # already) has no Copilot form for install.sh to place here.
      if is_copilot_suite_category "$category"; then
        if ! _json suite_plugin_shaped "$name"; then
          _warn "suite '$name' is not plugin-shaped — no Copilot translation available, skipped"
          continue
        fi
      fi
      dest_rel="${template//"{name}"/$name}"
      printf '%s\t%s\t%s\t%s\n' "$category" "$name" "$src_rel" "$dest_rel" >> "$SELECTION_FILE"
    done < "$items_file"

    if [[ $found -eq 0 ]]; then
      _warn "category '$category' has no assets in the catalog — nothing to select"
    fi
  done

  resolve_dependencies
}

# ── Dependency resolution ────────────────────────────────────────────────────
# For every suite in $SELECTION_FILE, auto-include its declared skill
# dependencies (suites/{name}/.claude-plugin/plugin.json's "dependencies" array,
# surfaced by catalog.sh as pluginShaped/dependencies) — mirrors how Claude
# Code's own plugin installer auto-resolves a plugin's `dependencies`. On by
# default; --no-deps opts out globally rather than per-dependency (per-dep
# opt-in/opt-out flags are the thing Homebrew tried and removed in 2.0 for being
# combinatorially untestable — see docs/adrs/ADR-0007).
resolve_dependencies() {
  [[ $NO_DEPS -eq 1 ]] && return
  [[ ! -s "$SELECTION_FILE" ]] && return
  # ponytail: `return 0` explicitly — a bare `return` after `||` inherits
  # grep's own *failing* exit status (no match = no suites selected, a normal
  # outcome here, not an error), which would make this function itself return
  # nonzero and abort the whole script under set -e with no error message.
  grep -q $'^suites\t' "$SELECTION_FILE" || return 0

  local suite_name deps dep skills_tmpl src_rel dest_rel already

  # Resolved once, not per-dependency — this template is invariant across every
  # suite/dependency in a single run, so one failed/missing lookup means no
  # dependency can ever be auto-included for this harness; say so once instead
  # of repeating the same warning per dependency.
  if ! skills_tmpl=$(_json mapping "$HARNESS" "skills"); then
    _warn "harness '$HARNESS' has no 'skills' mapping — suite dependencies can't be auto-included"
    return
  fi

  while IFS= read -r suite_name; do
    [[ -z "$suite_name" ]] && continue
    deps="$(_json suite_deps "$suite_name")"
    [[ -z "$deps" ]] && continue

    for dep in $deps; do
      already="$(awk -F'\t' -v n="$dep" '$1=="skills" && $2==n{print; exit}' "$SELECTION_FILE")"
      [[ -n "$already" ]] && continue

      if ! src_rel=$(_json item_path "skills" "$dep"); then
        _warn "suite '$suite_name' depends on unknown skill '$dep' — skipped"
        continue
      fi

      dest_rel="${skills_tmpl//"{name}"/$dep}"
      printf 'skills\t%s\t%s\t%s\n' "$dep" "$src_rel" "$dest_rel" >> "$SELECTION_FILE"
      _warn "including dependency skill '$dep' for suite '$suite_name'"
    done
  done < <(awk -F'\t' '$1=="suites"{print $2}' "$SELECTION_FILE")
}

# ── Copilot translation ──────────────────────────────────────────────────────
# Mutates a freshly-copied, plugin-shaped suite directory in place so it matches
# GitHub Copilot/VS Code's native agent-plugin layout instead of Claude Code's:
#   - .claude-plugin/plugin.json -> plugin.json at the plugin root (per GitHub's
#     own docs; the field names themselves — name/description/version/
#     dependencies/skills — are unchanged, since both ecosystems share them).
#   - agents/*.md -> agents/*.agent.md (Copilot's own filename convention,
#     already used by this repo's hand-authored Copilot payloads).
# select_assets() only ever routes pluginShaped suites here for the copilot
# harness (see its per-item guard above) — drop-in Copilot payloads
# (tiered-escalation-suite, tier-layered-teams/copilot) never reach this
# function and are copied wholesale, unchanged, same as before this existed.
translate_to_copilot() {
  local dest="$1" manifest="$dest/.claude-plugin/plugin.json" f base

  if [[ -f "$manifest" ]]; then
    mv "$manifest" "$dest/plugin.json"
  fi
  rm -rf "$dest/.claude-plugin"

  if [[ -d "$dest/agents" ]]; then
    while IFS= read -r -d '' f; do
      [[ "$f" == *.agent.md ]] && continue
      base="${f%.md}"
      mv "$f" "${base}.agent.md"
    done < <(find "$dest/agents" -maxdepth 1 -name "*.md" -print0)
  fi
}

resolve_root() {
  local root="$1"
  case "$root" in
    "~"|"~/"*) printf '%s' "${HOME}${root#\~}" ;;
    /*)        printf '%s' "$root" ;;
    *)         printf '%s' "$PWD/$root" ;;
  esac
}

# ── Copy (or report, in --dry-run) ──────────────────────────────────────────
apply_selection() {
  if [[ ! -s "$SELECTION_FILE" ]]; then
    _warn "nothing selected — no files copied"
    return
  fi

  local dest_root
  dest_root="$(resolve_root "$(_json scope_root "$HARNESS" "$SCOPE")")"

  _head "$([[ $DRY_RUN -eq 1 ]] && echo "dry run" || echo "installing")"
  local category name src_rel dest_rel src dest
  while IFS=$'\t' read -r category name src_rel dest_rel; do
    src="$SRC/$src_rel"
    dest="$dest_root/$dest_rel"

    if [[ $DRY_RUN -eq 1 ]]; then
      local note=""
      is_copilot_suite_category "$category" && note="  (copilot-translated)"
      if [[ -e "$dest" ]]; then
        printf '  [dry-run] %-9s %s -> %s  (exists, would skip; use --force to overwrite)\n' "$category" "$src_rel" "$dest"
      else
        printf '  [dry-run] %-9s %s -> %s%s\n' "$category" "$src_rel" "$dest" "$note"
      fi
      continue
    fi

    # ponytail: default is skip-existing, not merge/overwrite — safest default
    # with no TTY to ask; --force opts into clobbering.
    if [[ -e "$dest" && $FORCE -ne 1 ]]; then
      _warn "skip (exists): $dest — use --force to overwrite"
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest"
    cp -R "$src" "$dest"
    if is_copilot_suite_category "$category"; then
      translate_to_copilot "$dest"
    fi
    _ok "$dest_rel"
  done < "$SELECTION_FILE"
}

main() {
  parse_args "$@"
  fetch_source
  build_catalog
  if [[ ! -f "$SRC/scripts/harnesses.json" ]]; then
    _fail "fetched tree is missing scripts/harnesses.json — nothing to install"
    exit 1
  fi
  validate_harness_and_scope
  resolve_categories
  select_assets
  apply_selection
}

main "$@"
