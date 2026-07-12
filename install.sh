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
#   --yes-deps          auto-add dependencies (from dependencies.json) with no prompt
#   --no-deps           skip dependencies instead of adding/prompting
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

command -v python3 &>/dev/null || { _fail "python3 is required to parse catalog/harness JSON"; exit 1; }

usage() {
  cat <<'USAGE'
Usage: install.sh --harness <name> --scope <scope> [--assets <cat1,cat2,...>] [--dry-run] [--force] [--yes-deps|--no-deps]

  --harness   harness key from scripts/harnesses.json (e.g. claude-code, copilot)
  --scope     scope key declared for that harness (e.g. project, user)
  --assets    comma-separated asset categories to install (default: all available;
              if omitted with a TTY attached, pick interactively via fzf/gum/prompt)
  --dry-run   print planned copy operations; write nothing
  --force     overwrite existing destination files/dirs (default: skip existing)
  --yes-deps  auto-add dependencies (from dependencies.json) with no prompt
  --no-deps   skip dependencies instead of adding/prompting
  -h, --help  show this help
USAGE
}

ASSETS_RAW=""
HARNESS=""
SCOPE=""
DRY_RUN=0
FORCE=0
YES_DEPS=0
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
_json() {
  CATALOG_JSON="$CATALOG_JSON" HARNESSES_JSON="$HARNESSES_JSON" python3 - "$@" <<'PY'
import json, os, sys

def load(path):
    with open(path) as f:
        return json.load(f)

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

elif mode == "deps":
    catalog = load(os.environ["CATALOG_JSON"])
    assets = catalog.get("assets", {})
    target_path = args[0]
    for cat in ("skills", "suites"):
        for it in assets.get(cat, []):
            if it["path"] == target_path:
                for dep in it.get("dependencies", []):
                    print(dep)
                break

else:
    sys.exit(f"unknown mode: {mode}")
PY
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --assets)  ASSETS_RAW="$2"; shift 2 ;;
      --harness) HARNESS="$2"; shift 2 ;;
      --scope)   SCOPE="$2"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --force)   FORCE=1; shift ;;
      --yes-deps) YES_DEPS=1; shift ;;
      --no-deps)  NO_DEPS=1; shift ;;
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
      dest_rel="${template//"{name}"/$name}"
      printf '%s\t%s\t%s\t%s\n' "$category" "$name" "$src_rel" "$dest_rel" >> "$SELECTION_FILE"
    done < "$items_file"

    if [[ $found -eq 0 ]]; then
      _warn "category '$category' has no assets in the catalog — nothing to select"
    fi
  done
}

# ── Dependency resolution ────────────────────────────────────────────────────
# Runs after select_assets(), before apply_selection(). Each selected item may
# declare deps via dependencies.json (surfaced by catalog.sh as
# "dependencies":[...] and read here via `_json deps <path>`). Walk to a fixed
# point: any pass that finds not-yet-selected deps decides once (via
# --yes-deps/--no-deps/prompt/fail) whether to add them, then re-scans
# (including newly-added rows) so transitive deps are picked up too, until a
# pass finds nothing new.
resolve_dependencies() {
  local changed=1 category name src_rel dest_rel dep dep_category dep_name template reply decision
  local candidates_file="$WORK/dep_candidates.txt"
  local resolvable_file="$WORK/dep_resolvable.tsv"

  while [[ $changed -eq 1 ]]; do
    changed=0

    # Pass 1: every dep of every currently-selected row, minus ones already
    # selected (matched on the src_rel/path column) and minus dupes within
    # this pass.
    : > "$candidates_file"
    while IFS=$'\t' read -r category name src_rel dest_rel; do
      while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        grep -qF $'\t'"$dep"$'\t' "$SELECTION_FILE" && continue
        grep -qxF "$dep" "$candidates_file" && continue
        printf '%s\n' "$dep" >> "$candidates_file"
      done < <(_json deps "$src_rel")
    done < "$SELECTION_FILE"
    [[ -s "$candidates_file" ]] || break

    # Pass 2: resolve each candidate's category + harness mapping. A category
    # with no mapping for this harness is warn-and-skip, same as
    # select_assets() does for a whole requested category — never a hard
    # failure by itself.
    : > "$resolvable_file"
    while IFS= read -r dep; do
      case "$dep" in
        skills/*) dep_category=skills ;;
        suites/*) dep_category=suites ;;
        *) _warn "dependency '$dep' has an unrecognized category — skipped"; continue ;;
      esac
      if ! template=$(_json mapping "$HARNESS" "$dep_category"); then
        _warn "dependency '$dep' has no mapping for harness '$HARNESS' — skipped"
        continue
      fi
      dep_name="${dep##*/}"
      dest_rel="${template//"{name}"/$dep_name}"
      printf '%s\t%s\t%s\t%s\n' "$dep_category" "$dep_name" "$dep" "$dest_rel" >> "$resolvable_file"
    done < "$candidates_file"
    [[ -s "$resolvable_file" ]] || break

    # Decide once per pass for the whole batch of resolvable candidates.
    if [[ $NO_DEPS -eq 1 ]]; then
      decision=skip
    elif [[ $YES_DEPS -eq 1 ]]; then
      decision=add
    elif [[ -t 0 ]] || [[ -n "${INSTALL_FORCE_INTERACTIVE:-}" ]]; then
      _head "dependencies"
      printf '  not yet selected:\n'
      cut -f3 "$resolvable_file" | sed 's/^/    /'
      printf 'Add them? [Y/n] '
      read -r reply
      case "$reply" in
        ""|[Yy]*) decision=add ;;
        *)        decision=skip ;;
      esac
    else
      _fail "missing dependencies (pass --yes-deps to add or --no-deps to skip): $(cut -f3 "$resolvable_file" | tr '\n' ' ')"
      exit 1
    fi

    if [[ "$decision" == skip ]]; then
      _warn "skipping dependencies (--no-deps): $(cut -f3 "$resolvable_file" | tr '\n' ' ')"
      break
    fi

    while IFS=$'\t' read -r category name dep dest_rel; do
      printf '%s\t%s\t%s\t%s\n' "$category" "$name" "$dep" "$dest_rel" >> "$SELECTION_FILE"
      changed=1
    done < "$resolvable_file"
  done
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
      if [[ -e "$dest" ]]; then
        printf '  [dry-run] %-9s %s -> %s  (exists, would skip; use --force to overwrite)\n' "$category" "$src_rel" "$dest"
      else
        printf '  [dry-run] %-9s %s -> %s\n' "$category" "$src_rel" "$dest"
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
  resolve_dependencies
  apply_selection
}

main "$@"
