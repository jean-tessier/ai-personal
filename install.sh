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
#   --ref <ref>         tag, branch, or commit sha to fetch (default: main)
#   --dry-run           print planned copy operations; write nothing
#   --force             overwrite existing destination files/dirs (default: skip)
#   --yes-deps          auto-add dependencies (from dependencies.json) with no prompt
#   --no-deps           skip dependencies instead of adding/prompting
#   --uninstall         remove what the install record says was installed (no fetch)
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
Usage: install.sh --harness <name> --scope <scope> [--assets <cat1,cat2,...>] [--ref <ref>] [--dry-run] [--force] [--yes-deps|--no-deps]
       install.sh --uninstall --harness <name> --scope <scope> [--assets <cat1,cat2,...>] [--dry-run] [--force]

  --harness   harness key from scripts/harnesses.json (e.g. claude-code, copilot)
  --scope     scope key declared for that harness (e.g. project, user)
  --assets    comma-separated asset categories to install (default: all available;
              if omitted with a TTY attached, pick interactively via fzf/gum/prompt)
  --ref       tag, branch, or commit sha to fetch (default: main)
  --dry-run   print planned copy operations; write nothing
  --force     overwrite existing destination files/dirs (default: skip existing)
  --yes-deps  auto-add dependencies (from dependencies.json) with no prompt
  --no-deps   skip dependencies instead of adding/prompting
  --uninstall remove the files the install record lists, in the given categories (default: all);
              a modified asset is kept whole unless --force; --dry-run lists, deletes nothing
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
REF_SET=0
UNINSTALL=0
LOCAL_PATH=""   # test seam: skip network fetch, use a local checkout instead

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CATALOG_JSON="$WORK/catalog.json"
SELECTION_FILE="$WORK/selection.tsv"
SRC=""
SCOPE_ROOT=""   # set by validate_harness_and_scope()
HARNESSES_JSON=""
CATEGORIES=()

# ── JSON access (single dispatcher; python3 is the only non-stdlib dependency) ─
# ponytail: piped through `tr -d '\r'` — a native Windows python3 writes CRLF to
# stdout even when piped, which corrupts every `read -r`/`cp` consumer of this
# output ("cannot stat '...suite'$'\r'"). set -o pipefail (part of this script's
# top-level set -euo pipefail) keeps python's own exit code flowing through the
# pipe, since tr always exits 0.
_json() {
  { CATALOG_JSON="$CATALOG_JSON" HARNESSES_JSON="$HARNESSES_JSON" python3 -I - "$@" <<'PY'
import json, os, sys

def load(path):
    with open(path) as f:
        return json.load(f)

# The one install-record validator (ADR-0012), shared by install and uninstall.
def load_record(path, harness, scope):
    def bad(why):
        sys.exit(f"install record {path}: {why}")
    try:
        rec = load(path)
    except (ValueError, OSError) as e:
        bad(f"not valid JSON ({e})")
    if not isinstance(rec, dict) or rec.get("version") != 1:
        bad("not a version-1 install record")
    if not isinstance(rec.get("assets"), dict) or not all(
            isinstance(a, dict) and isinstance(a.get("files"), dict) for a in rec["assets"].values()):
        bad("malformed assets")
    if (rec.get("harness"), rec.get("scope")) != (harness, scope):
        sys.exit(f"install record {path} belongs to {rec.get('harness')}/{rec.get('scope')}, not {harness}/{scope}")
    return rec

# Safe record write: fresh temp file (a planted symlink is unlinked, never followed), then rename.
def save_record(path, rec):
    tmp = path + ".tmp"
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
    with open(tmp, "x") as f:
        json.dump(rec, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)

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

elif mode == "translate":
    harnesses = load(os.environ["HARNESSES_JSON"])
    tr = harnesses.get(args[0], {}).get("translate") or {}
    if isinstance(tr, dict) and args[1] not in tr:
        sys.exit(1)
    # a null or non-string value reaches plan_item's unknown-transform branch (fail closed)
    t = tr.get(args[1]) if isinstance(tr, dict) else None
    print(t if isinstance(t, str) else "(invalid)")

elif mode == "has_resource_kinds":
    harnesses = load(os.environ["HARNESSES_JSON"])
    sys.exit(0 if (harnesses.get(args[0], {}).get("resourceKinds") or {}).get(args[1]) else 1)

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

elif mode == "suite_plugin_shaped":
    catalog = load(os.environ["CATALOG_JSON"])
    it = find_item(catalog, "suites", args[0])
    sys.exit(0 if it and it.get("pluginShaped") else 1)

elif mode == "placements":
    # placements <suite> <harness> <scope> <src root>: expand the suite's manifest.json placements
    # (ADR-0008) into per-file rows. Exit 3: no manifest (any other non-zero exit is a crash). Else one stdout line kind per row:
    #   ERR<TAB>msg (refuse) | OMIT (harness not keyed) | NOTE<TAB>msg | ROW<TAB>src_rel<TAB>dest<TAB>mode
    suite, harness, scope, src_root = args
    it = find_item(load(os.environ["CATALOG_JSON"]), "suites", suite)
    man = it.get("manifest") if it else None
    if man is None:
        sys.exit(3)
    lines = []
    def err(msg):
        print("ERR\tsuite '%s' manifest: %s" % (suite, msg))
        sys.exit(0)
    if not isinstance(man, dict) or not isinstance(man.get(harness, []), list):
        err("must map each harness to a list of placements")
    if harness not in man:
        print("OMIT")
        sys.exit(0)
    hdef = load(os.environ["HARNESSES_JSON"]).get(harness, {})
    kinds = (hdef.get("resourceKinds") or {}).get(scope) or {}
    home_anchored = hdef.get("scopes", {}).get(scope, "").startswith("~")
    def ctl(t):
        return any(ord(c) < 32 or ord(c) == 127 for c in t)
    base = os.path.realpath(os.path.join(src_root, it["path"]))
    def tree(root):  # [(path relative to root or "", abs path)] of a file or directory tree
        if os.path.islink(root):
            err("symlink in placement: " + root)
        if os.path.isfile(root):
            return [("", root)]
        found = []
        for d, ds, fs in os.walk(root):
            for n in ds + fs:
                if os.path.islink(os.path.join(d, n)):
                    err("symlink in placement: " + os.path.join(d, n))
            found += [(os.path.relpath(os.path.join(d, n), root).replace(os.sep, "/"), os.path.join(d, n)) for n in sorted(fs)]
        return found
    for p in man[harness]:
        if not (isinstance(p, dict) and all(isinstance(p.get(k), str) for k in ("kind", "src", "mode"))):
            err("each placement needs string kind, src and mode")
        kind, src, pmode = p["kind"], p["src"], p["mode"]
        if kind not in ("agents", "skills", "instructions", "hooks", "config") or pmode not in ("copy", "merge"):
            err("bad kind or mode in placement '%s'" % src)
        if src.startswith("/") or "\\" in src or ctl(src) or any(s in ("", ".", "..") for s in src.split("/")):
            err("src must be relative with no empty, '.' or '..' segments or control characters: '%s'" % src)
        full = os.path.realpath(os.path.join(base, src))
        if not full.startswith(base + os.sep) or not os.path.exists(full):
            err("src '%s' is missing or outside the suite" % src)
        tmpl = kinds.get(kind)
        if tmpl is None:
            lines.append("NOTE\tkind '%s' has no destination for %s/%s — skipped" % (kind, harness, scope))
            continue
        tmpl = tmpl.replace("{suite}", suite)
        if kind == "instructions":
            if not os.path.isfile(full):
                err("kind 'instructions' needs a file src: '%s'" % src)
            roots = [(tmpl, full)]
        elif kind == "config":
            roots = [(tmpl.replace("{relpath}", os.path.basename(src)), full)]
        elif os.path.isdir(full):
            roots = [(tmpl.replace("{basename}", n), os.path.join(full, n)) for n in sorted(os.listdir(full))]
        else:
            err("kind '%s' needs a directory src: '%s'" % (kind, src))
        for droot, sroot in roots:
            for rel, a in tree(sroot):
                dest = droot + ("/" + rel if rel else "")
                srel = it["path"] + "/" + os.path.relpath(a, base).replace(os.sep, "/")
                # same text rule as ADR-0012's record consumer: root-anchored, ~/ only for a home-anchored scope
                segs = (dest[2:] if dest.startswith("~/") else dest).split("/")
                if (dest.startswith("/") or "\\" in dest or ctl(dest) or ctl(srel) or (not dest.startswith("~/") if home_anchored else dest.startswith("~"))
                        or any(g in ("", ".", "..") for g in segs)):
                    err("unsafe destination '%s'" % dest)
                lines.append("ROW\t%s\t%s\t%s" % (srel, dest, pmode))
    if not any(l.startswith("ROW\t") for l in lines):
        lines.append("OMIT")
    print("\n".join(lines))

elif mode == "record":
    import datetime, hashlib
    path, harness, scope, repo, ref, tsv, cwd, home = args
    rec = {"version": 1, "harness": harness, "scope": scope, "assets": {}}
    if os.path.exists(path):
        rec = load_record(path, harness, scope)
    with open(tsv) as f:
        rows = [line.rstrip("\n").split("\t") for line in f]
    if rows:
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        rec["source"] = {"repo": repo, "ref": ref or None}
        for asset, spec in rows:
            p = os.path.join(home, spec[2:]) if spec.startswith("~/") else os.path.join(cwd, spec)
            if not os.path.exists(p):
                sys.exit(f"install record: placed path missing: {p}")
            placed = [(spec, p)] if os.path.isfile(p) else [
                (spec + "/" + os.path.relpath(os.path.join(d, n), p).replace(os.sep, "/"), os.path.join(d, n))
                for d, _, names in os.walk(p) for n in names]
            entry = rec["assets"].setdefault(asset, {"files": {}})
            entry.update(installedAt=now, ref=ref or None)
            for k in [k for k in entry["files"] if k == spec or k.startswith(spec + "/")]:
                del entry["files"][k]
            for key, file in placed:
                with open(file, "rb") as fh:
                    entry["files"][key] = "sha256:" + hashlib.sha256(fh.read()).hexdigest()
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        save_record(path, rec)

elif mode == "uninstall":
    # The record is user-editable, so it is untrusted: every check runs before any delete.
    import hashlib, stat
    spec, harness, scope, cwd, home, dry, force, cats = args
    dry, force, cats, user = dry == "1", force == "1", cats.split(), spec.startswith("~/")
    base = home if user else cwd
    real = os.path.realpath
    bb = real(base)
    def entry(q):  # q's directory entry: real parent + own name (a final symlink is not followed)
        return os.path.join(real(os.path.dirname(q)), os.path.basename(q))
    # only <scope root>/.ai-personal-install.json, and only if it really sits inside the project root or $HOME
    path = entry(os.path.join(home, spec[2:]) if user else os.path.join(cwd, spec))
    if not path.startswith(bb + os.sep):
        sys.exit(f"install record {path} is outside {bb}; nothing was deleted")
    if not os.path.lexists(path):
        print(f"  note  no install record at {path}; nothing to uninstall")
        sys.exit(0)
    rec = load_record(path, harness, scope)  # guard 1: version, shape, harness/scope
    root = os.path.dirname(path)
    # guards 2 and 3: every recorded path, by text, then its real parent inside the project root or $HOME
    # Names are printed, so control characters (terminal escapes, NUL) refuse the whole record.
    # A .git segment is refused too: uninstall otherwise trusts the record you hold (run --dry-run first).
    ctrl = lambda s: any(ord(c) < 32 or 127 <= ord(c) < 160 for c in s)
    paths = {}
    for a, e in rec["assets"].items():
        if ctrl(a):
            sys.exit(f"install record {path}: unsafe asset name {a!r}; nothing was deleted")
        for k in e["files"]:
            t = k[2:] if user and k.startswith("~/") else None if user else k
            if (t is None or not t or ctrl(k) or "\\" in t or os.path.isabs(t) or t.startswith("~")
                    or any(s.lower() in ("", ".", "..", ".git") for s in t.split("/"))
                    or not entry(os.path.join(base, t)).startswith(bb + os.sep)):
                sys.exit(f"install record {path}: unsafe path {k!r} in {a}; nothing was deleted")
            paths[k] = os.path.join(base, t)
    sel = [a for a in rec["assets"] if not cats or a.split("/")[0] in cats]
    def ident(q):  # compare files, not spellings (case-insensitive file systems, links)
        try:
            st = os.stat(q)
            return (st.st_dev, st.st_ino)
        except OSError:
            return None
    own, stops = {ident(path), ident(root)}, {ident(root), ident(base), ident(cwd), ident(home)} - {None}
    def sha(p):  # never blocks on a FIFO, never follows a link, hashes only a regular file
        try:
            fd = os.open(p, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0))
            with os.fdopen(fd, "rb") as fh:
                if not stat.S_ISREG(os.fstat(fd).st_mode):
                    return None
                return "sha256:" + hashlib.sha256(fh.read()).hexdigest()
        except OSError:
            return None
    plan = {}
    for a in sel:
        dele, mod = [], []
        for k, h in rec["assets"][a]["files"].items():
            p = paths[k]
            try:
                st = os.lstat(p)  # guard 4: look before touching
            except (FileNotFoundError, NotADirectoryError):
                continue  # already gone: forgotten
            if ident(p) in own:
                print(f"  skip    {k} (the install record or the scope root)")
            elif not (stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode)):
                print(f"  skip    {k} (not a file)")
            else:
                if stat.S_ISLNK(st.st_mode) or sha(p) != h:  # guard 6; a link is never ours, never read
                    mod.append(k)
                dele.append((k, p))
        for k in mod:
            print(f"  {'force' if force else 'keep'}    {a}, modified: {k}" + ("" if force else " (use --force to delete it)"))
        if not mod or force:
            plan[a] = dele
    # guard 5: a path of any asset that stays (not selected, or kept as modified) is never deleted
    claimed = {ident(paths[k]) for a, e in rec["assets"].items() if a not in plan for k in e["files"]} - {None}
    failed = False
    for a, dele in plan.items():
        left = {}
        for k, p in dele:
            if ident(p) in claimed:
                print(f"  skip    {k} (also claimed by an asset that stays)")
                continue
            if dry:
                print(f"  [dry-run] would remove {k}")
                continue
            try:
                os.unlink(p)  # never follows a symlink
                print(f"  removed {k}")
            except FileNotFoundError:
                pass  # shared with an asset removed just before: forgotten
            except OSError as e:
                print(f"  FAIL    could not remove {k}: {e.strerror}", file=sys.stderr)
                left[k], failed = rec["assets"][a]["files"][k], True
        if dry:
            continue
        if left:
            rec["assets"][a]["files"] = left
        else:
            del rec["assets"][a]
        # guard 8: prune empty dirs bottom-up along the recorded path, stopping at a symlinked
        # dir, the scope root, the project root or $HOME
        for k, p in dele:
            d = os.path.dirname(p)
            while d.startswith(base + os.sep) and not os.path.islink(d) and ident(d) not in stops:
                try:
                    os.rmdir(d)  # only ever removes an empty directory
                except OSError:
                    break
                d = os.path.dirname(d)
    if not dry:  # guard 7: same safe write as install; an empty record is deleted
        save_record(path, rec) if rec["assets"] else os.unlink(path)
    if failed:
        sys.exit("uninstall: some files could not be removed; they stay in the install record")

else:
    sys.exit(f"unknown mode: {mode}")
PY
  } | tr -d '\r'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    # a missing value must fail here: under set -u, bash 3.2 would exit with the EXIT trap's status (0)
    case "$1" in
      --assets|--harness|--scope|--ref|--local)
        if [[ $# -lt 2 || "$2" == -* ]]; then _fail "$1 needs a value"; usage; exit 1; fi ;;
    esac
    case "$1" in
      --assets)  ASSETS_RAW="$2"; shift 2 ;;
      --harness) HARNESS="$2"; shift 2 ;;
      --scope)   SCOPE="$2"; shift 2 ;;
      --ref)     REF="$2"; REF_SET=1; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --force)   FORCE=1; shift ;;
      --yes-deps) YES_DEPS=1; shift ;;
      --no-deps)  NO_DEPS=1; shift ;;
      --uninstall) UNINSTALL=1; shift ;;
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
  if [[ $UNINSTALL -eq 1 && ( $YES_DEPS -eq 1 || $NO_DEPS -eq 1 ) ]]; then
    _fail "--yes-deps and --no-deps cannot be combined with --uninstall"; usage; exit 1
  fi
  if [[ $YES_DEPS -eq 1 && $NO_DEPS -eq 1 ]]; then _fail "--yes-deps and --no-deps cannot be combined"; usage; exit 1; fi
  if [[ $REF_SET -eq 1 ]]; then
    if [[ -n "$LOCAL_PATH" ]]; then _fail "--ref cannot be combined with --local"; usage; exit 1; fi
    # the ref goes into a URL: allow only ref-ish characters, no path traversal
    if [[ ! "$REF" =~ ^[A-Za-z0-9._/-]+$ || "$REF" == *..* ]]; then _fail "invalid --ref '$REF' (allowed: letters, digits, . _ / -; no '..')"; usage; exit 1; fi
  fi
}

# ── Fetch (no git — curl + tar only) ────────────────────────────────────────
fetch_source() {
  if [[ -n "$LOCAL_PATH" ]]; then
    SRC="$LOCAL_PATH"
    return
  fi
  local url="https://codeload.github.com/${OWNER}/${REPO_NAME}/tar.gz/${REF}"
  _head "fetching ${OWNER}/${REPO_NAME}@${REF}"
  if ! curl -fsSL "$url" -o "$WORK/src.tar.gz"; then _fail "fetch failed: $url"; exit 1; fi
  if ! tar -xzf "$WORK/src.tar.gz" -C "$WORK"; then _fail "extract failed: $WORK/src.tar.gz"; exit 1; fi
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
  SCOPE_ROOT="$(_json scope_root "$HARNESS" "$SCOPE")"
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

# ── Plan one item ───────────────────────────────────────────────────────────
# The single place that decides whether an asset can go to $HARNESS/$SCOPE and
# where: category mapping lookup, translate-transform eligibility, destination
# and post-copy transform. Both select_assets() (requested items) and
# resolve_dependencies() (dependencies) call it, so they can't drift apart.
#
# plan_item <asset> <label> <out_file>
#   asset     repo-relative path, e.g. skills/atomic-commits (the src_rel of a mapping row)
#   label     how to name the asset in a skip note, e.g. "dependency 'skills/x'"
#   out_file  gets one row appended:
#             asset<TAB>src_rel<TAB>dest<TAB>mode<TAB>transform
#             src_rel equals asset for a mapping row, and is one suite file for a
#             manifest row (one row per placed file). dest is root-anchored in
#             resolve_root()'s convention (relative = $PWD, "~/" = $HOME); mode is
#             "item" (whole-directory skip-or-replace) or "copy"|"merge" (per-file
#             manifest placement, never removes a directory); transform is the
#             post-copy rewrite, or "-" for none.
# Returns 1, after printing a note, if the asset can't be placed for this harness.
plan_item() {
  local asset="$1" label="$2" out="$3" category name template transform="-" placements
  case "$asset" in
    skills/*|suites/*) category="${asset%%/*}" ;;
    *) _warn "$label has an unrecognized category — skipped"; return 1 ;;
  esac
  name="${asset##*/}"
  # A suite manifest.json (ADR-0008) replaces mapping.suites and any translate: one
  # row per placed file, or a skip when the manifest omits this harness.
  # Exit 3 means "no manifest" (fall through to mapping); any other failure is a crash and
  # must not fall back to the wholesale copy, which would break the manifest's precedence.
  local prc=3
  if [[ "$category" == suites ]]; then
    prc=0; placements=$(_json placements "$name" "$HARNESS" "$SCOPE" "$SRC") || prc=$?
  fi
  if [[ $prc -ne 3 ]]; then
    if [[ $prc -ne 0 ]]; then _fail "$label: manifest placement failed"; exit 1; fi
    local kind rel dest pmode
    while IFS=$'\t' read -r kind rel dest pmode; do
      case "$kind" in
        ERR)  _fail "$rel"; exit 1 ;;
        OMIT) _warn "$label: manifest has no placements for harness '$HARNESS' — skipped"; return 1 ;;
        NOTE) _warn "$label: $rel" ;;
        ROW)  printf '%s\t%s\t%s\t%s\t-\n' "$asset" "$rel" "$dest" "$pmode" >> "$out" ;;
      esac
    done <<< "$placements"
    return 0
  fi
  if ! template=$(_json mapping "$HARNESS" "$category"); then
    _warn "$label has no mapping for harness '$HARNESS' — skipped"
    return 1
  fi
  # A harness may name a post-copy transform for a category (harnesses.json
  # "translate"). An item the transform can't handle has no form for this
  # harness and is skipped: e.g. Copilot only understands plugin-shaped suites
  # (see translate_to_copilot()), so a drop-in payload or a multi-harness suite
  # with its own hand-authored Copilot variant is not placed.
  if transform=$(_json translate "$HARNESS" "$category"); then
    local rc=0
    transform_eligible "$transform" "$name" || rc=$?
    case $rc in
      0) ;;
      1) _warn "$label is not plugin-shaped — no '$transform' translation available, skipped"; return 1 ;;
      *) _warn "$label: unknown translate transform '$transform' — skipped"; return 1 ;;
    esac
  else
    transform="-"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$asset" "$asset" "${SCOPE_ROOT:+$SCOPE_ROOT/}${template//"{name}"/$name}" item "$transform" >> "$out"
}

# ── Selection step ──────────────────────────────────────────────────────────
# Flag-driven: every item in each requested category, planned by plan_item()
# and written to $SELECTION_FILE as
# "asset<TAB>src_rel<TAB>dest<TAB>mode<TAB>transform". When no --assets was passed
# AND stdin is a real TTY, the full per-category item list is routed through
# pick_items() first so the user chooses a subset — otherwise (explicit
# --assets, or no TTY) every item is taken, same as before Task 4.
#
# ponytail: undocumented test seam — INSTALL_FORCE_INTERACTIVE=1 bypasses the
# `[[ -t 0 ]]` check (mirrors --local's role for fetch_source), so the picker
# path can be exercised from a script with no real TTY attached.
select_assets() {
  : > "$SELECTION_FILE"
  local category found name src_rel items_file
  local interactive=0
  if [[ -z "$ASSETS_RAW" ]]; then
    if [[ -t 0 ]] || [[ -n "${INSTALL_FORCE_INTERACTIVE:-}" ]]; then
      interactive=1
    fi
  fi

  for category in "${CATEGORIES[@]}"; do
    # Early, whole-category check (before the picker would ask about items that
    # could never be placed); plan_item() makes the authoritative per-item call.
    # (a suite may be placed from its manifest by a harness that only has resourceKinds)
    if ! _json mapping "$HARNESS" "$category" >/dev/null && ! { [[ "$category" == suites ]] && _json has_resource_kinds "$HARNESS" "$SCOPE"; }; then
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
      plan_item "$src_rel" "${category%s} '$name'" "$SELECTION_FILE" || true
    done < "$items_file"

    if [[ $found -eq 0 ]]; then
      _warn "category '$category' has no assets in the catalog — nothing to select"
    fi
  done
}

# ── Transform registry ──────────────────────────────────────────────────────
# Keyed by transform name (harnesses.json "translate"), never by harness name.
# A new harness that reuses a transform is a JSON edit; a new kind of transform
# needs a case here and in validate.sh's known-transform list (ADR-0011).
# transform_eligible <transform> <name>: 0 eligible, 1 not eligible, 2 unknown transform.
transform_eligible() {
  case "$1" in
    copilot-plugin) _json suite_plugin_shaped "$2" ;;
    *) return 2 ;;
  esac
}
# transform_apply <transform> <dest>: rewrite the freshly-copied item at <dest>.
transform_apply() {
  case "$1" in
    copilot-plugin) translate_to_copilot "$2" ;;
  esac
}

# ── Copilot translation ──────────────────────────────────────────────────────
# Mutates a freshly-copied, plugin-shaped suite directory in place so it matches
# GitHub Copilot/VS Code's native agent-plugin layout instead of Claude Code's:
#   - .claude-plugin/plugin.json -> plugin.json at the plugin root (per GitHub's
#     own docs; the field names themselves — name/description/version/
#     dependencies/skills — are unchanged, since both ecosystems share them).
#   - agents/*.md -> agents/*.agent.md (Copilot's own filename convention,
#     already used by this repo's hand-authored Copilot payloads).
# plan_item() only ever routes pluginShaped suites here (via transform_apply)
# for a harness whose `translate` names copilot-plugin, whether requested or
# pulled in as a dependency — drop-in Copilot
# payloads (tiered-escalation-suite, tier-layered-teams/copilot) never reach this
# function: they have no plugin form, so plan_item() skips them with a note.
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

# ── Dependency resolution ────────────────────────────────────────────────────
# Runs after select_assets(), before apply_selection(). Each selected item may
# declare deps via dependencies.json (surfaced by catalog.sh as
# "dependencies":[...] and read here via `_json deps <path>`). Walk to a fixed
# point: any pass that finds not-yet-selected deps decides once (via
# --yes-deps/--no-deps/prompt/fail) whether to add them, then re-scans
# (including newly-added rows) so transitive deps are picked up too, until a
# pass finds nothing new.
resolve_dependencies() {
  local changed=1 asset src_rel dest mode transform dep reply decision
  local candidates_file="$WORK/dep_candidates.txt"
  local resolvable_file="$WORK/dep_resolvable.tsv"
  local skipped_file="$WORK/dep_skipped.txt"   # deps plan_item() rejected: noted once, never re-planned
  : > "$skipped_file"

  while [[ $changed -eq 1 ]]; do
    changed=0

    # Pass 1: every dep of every currently-selected row, minus ones already
    # selected (matched on the asset column), minus ones plan_item() already
    # rejected in an earlier round, and minus dupes within this pass.
    : > "$candidates_file"
    while IFS= read -r asset; do
      while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        grep -qxF -- "$dep" <(cut -f1 "$SELECTION_FILE") && continue
        grep -qxF "$dep" "$skipped_file" && continue
        grep -qxF "$dep" "$candidates_file" && continue
        printf '%s\n' "$dep" >> "$candidates_file"
      done < <(_json deps "$asset")
    done < <(cut -f1 "$SELECTION_FILE" | uniq)
    [[ -s "$candidates_file" ]] || break

    # Pass 2: plan each candidate with plan_item(), the same decision
    # select_assets() makes for a requested item. One it can't place (no
    # mapping, unrecognized category, not plugin-shaped) is warn-and-skip —
    # never a hard failure by itself — and remembered so later rounds don't
    # print the same note again.
    : > "$resolvable_file"
    while IFS= read -r dep; do
      if ! plan_item "$dep" "dependency '$dep'" "$resolvable_file"; then
        printf '%s\n' "$dep" >> "$skipped_file"
      fi
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
      cut -f1 "$resolvable_file" | uniq | sed 's/^/    /'
      printf 'Add them? [Y/n] '
      read -r reply
      case "$reply" in
        ""|[Yy]*) decision=add ;;
        *)        decision=skip ;;
      esac
    else
      _fail "missing dependencies (pass --yes-deps to add or --no-deps to skip): $(cut -f1 "$resolvable_file" | uniq | tr '\n' ' ')"
      exit 1
    fi

    if [[ "$decision" == skip ]]; then
      _warn "skipping dependencies (--no-deps): $(cut -f1 "$resolvable_file" | uniq | tr '\n' ' ')"
      break
    fi

    cat "$resolvable_file" >> "$SELECTION_FILE"
    changed=1
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

# ── Install record (ADR-0012) ───────────────────────────────────────────────
# Every write path calls record_write, which logs the placed asset and merges it
# into <scope root>/.ai-personal-install.json at once, so every completed placement
# is recorded even if a later one fails (a failed cp/transform leaves that asset's
# partial copy unrecorded, the safe direction). Dry runs never call record_write.
RECORD_TSV="$WORK/record.tsv"

# record_flush: validate the record and merge the rows in $RECORD_TSV (none: validate only).
record_flush() {
  local ref=""
  [[ -n "$LOCAL_PATH" ]] || ref="$REF"
  _json record "$(resolve_root "${SCOPE_ROOT:+$SCOPE_ROOT/}.ai-personal-install.json")" \
    "$HARNESS" "$SCOPE" "$OWNER/$REPO_NAME" "$ref" "$RECORD_TSV" "$PWD" "$HOME"
}

# record_write <asset> <dest_spec>: log one placed file or directory, then flush.
record_write() {
  printf '%s\t%s\n' "$1" "$2" > "$RECORD_TSV"
  record_flush
}

# ── Copy (or report, in --dry-run) ──────────────────────────────────────────
MERGE_KEPT=""   # existing files a merge placement left alone (listed once at the end)
apply_selection() {
  if [[ ! -s "$SELECTION_FILE" ]]; then
    _warn "nothing selected — no files copied"
    return
  fi

  _head "$([[ $DRY_RUN -eq 1 ]] && echo "dry run" || echo "installing")"
  local asset src_rel dest_spec mode transform category src dest
  # a bad existing record must stop the install before any file is copied
  : > "$RECORD_TSV"; record_flush
  while IFS=$'\t' read -r asset src_rel dest_spec mode transform; do
    category="${asset%%/*}"
    src="$SRC/$src_rel"
    dest="$(resolve_root "$dest_spec")"
    # fail closed: an unknown mode must never fall into the whole-directory (rm -rf) branch
    case "$mode" in item|copy|merge) ;; *) _fail "malformed selection row for $asset"; exit 1 ;; esac

    if [[ $DRY_RUN -eq 1 ]]; then
      local note=""
      [[ "$transform" != "-" ]] && note="  (translated: $transform)"
      if [[ "$mode" != item && ( -d "$dest" || -L "$dest" ) ]]; then
        printf '  [dry-run] %-9s %s -> %s  (not a regular file, would skip)\n' "$category" "$src_rel" "$dest"
      elif [[ -e "$dest" && $FORCE -eq 1 ]]; then
        printf '  [dry-run] %-9s %s -> %s  (exists, would overwrite)%s\n' "$category" "$src_rel" "$dest" "$note"
      elif [[ -e "$dest" && "$mode" == merge ]]; then
        printf '  [dry-run] %-9s %s -> %s  (exists, merge would leave it untouched)\n' "$category" "$src_rel" "$dest"
      elif [[ -e "$dest" ]]; then
        printf '  [dry-run] %-9s %s -> %s  (exists, would skip; use --force to overwrite)\n' "$category" "$src_rel" "$dest"
      else
        printf '  [dry-run] %-9s %s -> %s%s\n' "$category" "$src_rel" "$dest" "$note"
      fi
      continue
    fi

    # Manifest placements (ADR-0008) work per file and never remove a directory:
    # the destination may be the user's own tree (e.g. ./scripts), not ours alone.
    # merge is copy that never touches an existing file without --force (ADR-0013);
    # its skips are reported once at the end, not per file.
    if [[ "$mode" == copy || "$mode" == merge ]]; then
      if [[ -d "$dest" || -L "$dest" ]]; then
        _warn "skip (not a regular file): $dest"
      elif [[ -e "$dest" && $FORCE -ne 1 ]]; then
        if [[ "$mode" == merge ]]; then
          MERGE_KEPT="$MERGE_KEPT"$'\n'"        $dest_spec"
        else
          _warn "skip (exists): $dest — use --force to overwrite"
        fi
      else
        # skip only when something that is not a directory is in the way; any other
        # mkdir failure (permissions, read-only, full disk) must fail the install
        local up; up="$(dirname "$dest")"
        while [[ ! -e "$up" && ! -L "$up" ]]; do up="$(dirname "$up")"; done
        if [[ ! -d "$up" ]]; then
          _warn "skip (parent is not a directory): $dest"
          continue
        fi
        mkdir -p "$(dirname "$dest")"
        [[ -e "$dest" ]] && rm -f "$dest"   # --force: cp keeps an old file's mode, so replace it
        cp "$src" "$dest"
        record_write "$asset" "$dest_spec"
        _ok "${dest_spec#"$SCOPE_ROOT"/}"
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
    if [[ "$transform" != "-" ]]; then
      transform_apply "$transform" "$dest"
    fi
    record_write "$asset" "$dest_spec"
    _ok "${dest_spec#"$SCOPE_ROOT"/}"
  done < "$SELECTION_FILE"
  [[ -z "$MERGE_KEPT" ]] || _warn "merge: left existing file(s) untouched (use --force to overwrite):$MERGE_KEPT"
}

# ── Uninstall (ADR-0012 "Consumers MUST") ───────────────────────────────────
# Removes what <scope root>/.ai-personal-install.json says this tool placed, after
# the record and every path in it pass the checks in `_json uninstall`.
uninstall() {
  local cats=""
  if [[ -n "$ASSETS_RAW" ]]; then resolve_categories; cats="${CATEGORIES[*]}"; fi
  _head "$([[ $DRY_RUN -eq 1 ]] && echo "dry run (uninstall)" || echo "uninstalling")"
  _json uninstall "${SCOPE_ROOT:+$SCOPE_ROOT/}.ai-personal-install.json" "$HARNESS" "$SCOPE" \
    "$PWD" "$HOME" "$DRY_RUN" "$FORCE" "$cats"
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
  if [[ $UNINSTALL -eq 1 ]]; then uninstall; return; fi
  resolve_categories
  select_assets
  resolve_dependencies
  apply_selection
}

main "$@"
