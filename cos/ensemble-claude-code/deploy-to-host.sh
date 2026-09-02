#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - host deploy script for Linux / macOS.
# ASCII-ONLY FILE with LF line endings, deliberately: a CRLF-terminated bash
# script fails to execute on Linux (the shebang line carries a stray \r), and
# non-ASCII punctuation crossing a Windows-authored boundary can corrupt. Keep
# this file pure ASCII, LF-only.
#
# The Linux/macOS analog of deploy-to-host.ps1. Same behavior, same honesty:
# copies the staged set from this folder into an isolated Claude Code config
# home. The source ships CLEAN of factory provenance since 2026-09-02 (the line-1
# always-on comments and the agent cards' provenance: frontmatter field were
# relocated to the workbench's factory-side provenance ledger), so the strip
# helpers below run as structural GUARDS: on a clean source they find nothing and
# copy every file through unchanged, acting only if a provenance line ever creeps
# back into a body copy. It prunes a host skills/ folder only when
# skills-shipped.txt (the append-only manifest of every skill this COS has ever
# shipped) lists it AND the current source no longer carries it - a
# shipped-then-retired skill; a host-added skill this COS never shipped is left
# alone. It hash-verifies every file in the verified set (byte-identical against
# source, the agent cards against their guard-processed content; the six always-on
# copies excepted), prints the inventory, and refuses to clobber an existing home
# unless --update or --force.
#
# TARGET HOME - config-home semantics:
#   ${CLAUDE_ENSEMBLE_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ensemble-claude-code}
# The default follows the XDG Base Directory spec: per-user configuration lives
# under $XDG_CONFIG_HOME, which defaults to ~/.config. This is the Linux/macOS
# analog of the Windows script's %LOCALAPPDATA%\ensemble-claude-code (a per-user,
# non-roaming config location). Override the whole path with CLAUDE_ENSEMBLE_HOME,
# or relocate just the config root with XDG_CONFIG_HOME.
#
# DIVERGENCE FROM THE WINDOWS SCRIPT: only launch/*.sh is deployed here, never
# launch/*.ps1 - the PowerShell launcher and wiring script are useless on
# Linux/macOS. Everything else in the staged set is identical.
#
# Why user-executed: an agent session cannot draw a trustworthy footprint
# outside its shared workspace; the human runs the final hop and the script's
# own output is the deploy-time footprint. Same lesson as the PowerShell script.
#
# Run this in your own shell on the target host:
#   ./deploy-to-host.sh            # first deploy
#   ./deploy-to-host.sh --update   # refresh the staged files, keep login/session
#   ./deploy-to-host.sh --force    # replace the whole home (old one backed up)

set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${CLAUDE_ENSEMBLE_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ensemble-claude-code}"

update=0
force=0
for arg in "$@"; do
  case "$arg" in
    --update) update=1 ;;
    --force)  force=1 ;;
    *) echo "Unknown argument: $arg" >&2
       echo "Usage: ./deploy-to-host.sh [--update | --force]" >&2
       exit 2 ;;
  esac
done

echo "Source: $src"
echo "Target: $target"

# sha256 helper: sha256sum (Linux/coreutils) or shasum -a 256 (macOS ships no
# sha256sum by default). Portability guard so the same script hashes on both.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    echo "ERROR: neither sha256sum nor shasum found; cannot hash-verify." >&2
    exit 1
  fi
}

# Same helper reading stdin - used to hash derived (stripped) content without a
# temp file, mirroring sha256 above.
sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    echo "ERROR: neither sha256sum nor shasum found; cannot hash-verify." >&2
    exit 1
  fi
}

if [ -e "$target" ]; then
  if [ "$update" -eq 1 ]; then
    echo "Update mode: overwriting the staged files in place; session, trust, and login state stay untouched. (Git rolls back anything the source ever carried. A host skills folder this COS shipped in an earlier release but no longer carries is pruned - it came from the source, so git can restore it; a skills folder this COS never shipped is left alone as yours. --force is the other path: it moves the whole home to a timestamped backup - plugins, sessions, and login move with it and are re-established by hand.)"
  elif [ "$force" -eq 1 ]; then
    backup="${target}.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$target" "$backup"
    echo "Rollback baseline: existing target moved to $backup"
  else
    echo ""
    echo "Target already exists. Contents:"
    ls -1 "$target" || true
    echo ""
    echo "Re-run with --update to refresh the staged files in place (keeps login/session state; prunes only a skill this COS shipped and has since retired, and leaves any skill you added yourself alone),"
    echo "or with --force to replace the whole home (the existing directory is moved to a timestamped backup first; plugins, sessions, and login move with it and are re-established by hand)."
    exit 1
  fi
else
  echo "Rollback baseline: target absent before deploy ($(date +%Y-%m-%dT%H:%M:%S))"
fi

mkdir -p "$target"
for d in rules agents skills hooks launch; do
  mkdir -p "$target/$d"
done

# Files copied byte-identical are collected here for hash verification.
verify_list=()
# Agent cards deployed through the provenance-frontmatter guard are collected
# here separately - hash-verified against their guard-processed content (identical
# to source while the source ships clean, as it now does), not a raw path.
verify_stripped_list=()
fm_stripped_count=0
always_on_stripped_count=0

copy_verified() {
  # copy_verified <src-rel> <dst-rel>
  local rel="$1" dstrel="$2"
  mkdir -p "$target/$(dirname "$dstrel")"
  cp "$src/$rel" "$target/$dstrel"
  verify_list+=("$rel|$dstrel")
}

copy_stripped() {
  # copy_stripped <src-rel> <dst-rel>
  # Guard: strip a line-1 provenance comment if present; copy the rest
  # byte-for-byte. The source ships clean since 2026-09-02, so this normally
  # finds nothing and copies the file whole; it acts only if a comment ever
  # creeps back. tail -n +2 preserves everything after line 1 exactly, matching
  # the PS regex ^<!-- provenance:[^\r\n]*\r?\n (first line only).
  local rel="$1" dstrel="$2"
  mkdir -p "$target/$(dirname "$dstrel")"
  if head -n 1 "$src/$rel" | grep -q '^<!-- provenance:'; then
    tail -n +2 "$src/$rel" > "$target/$dstrel"
    always_on_stripped_count=$((always_on_stripped_count + 1))
  else
    cp "$src/$rel" "$target/$dstrel"
  fi
}

strip_provenance_frontmatter() {
  # strip_provenance_frontmatter <file>  ->  stdout
  # Guard: emit the file with any provenance frontmatter field removed - the
  # leading YAML block between the --- fences only, so a body mention of
  # provenance is untouched. The source ships clean since 2026-09-02, so every
  # card now has no such key and passes through unchanged; the guard acts only if
  # a key ever creeps back. Were a value present, it would be a single-line
  # scalar today; a future multi-line value (block scalar, an
  # unclosed single quote, or an indented continuation) is refused with exit 3
  # rather than half-stripping the card. Line endings mostly survive - awk keeps
  # the record's trailing CR when the source is CRLF - but not always: awk
  # appends a trailing newline when the final line lacks one, and some awk builds
  # (Git-Bash gawk) emit CR-free output regardless. Both are platform-dependent
  # and inert here (the cards are LF-pinned and end in a newline, and verify
  # re-runs this same awk so the hashes stay self-consistent). \047 is a
  # single quote, spelled octal to keep this awk program single-quotable.
  awk '
    NR==1 && $0 ~ /^---[\r]?$/ { infm=1; print; next }
    {
      if (pend==1) {
        if ($0 ~ /^[ \t]/) { print "ERROR: provenance value continues onto the next line" > "/dev/stderr"; exit 3 }
        pend=0
      }
      if (infm==1 && $0 ~ /^---[\r]?$/) { infm=0; print; next }
      if (infm==1 && $0 ~ /^provenance:/) {
        val=$0; sub(/^provenance:[ \t]*/,"",val); sub(/[\r]?$/,"",val)
        if (val ~ /^[|>]/) { print "ERROR: provenance uses a multi-line block scalar" > "/dev/stderr"; exit 3 }
        if (val ~ /^\047/ && val !~ /\047[ \t]*$/) { print "ERROR: provenance single-quoted value is not closed on one line" > "/dev/stderr"; exit 3 }
        pend=1
        next
      }
      print
    }
  ' "$1"
}

copy_stripped_frontmatter() {
  # copy_stripped_frontmatter <src-rel> <dst-rel>
  # Write through a temp file beside the target and move it into place only on
  # awk success. The > redirect truncates its file before awk runs, so writing
  # straight to the target would leave a truncated card behind on the fail-loud
  # path (exit 3). On failure the temp is removed and the error propagated, so a
  # refused strip leaves the deployed target untouched (matching the .ps1, which
  # throws before writing).
  local rel="$1" dstrel="$2"
  mkdir -p "$target/$(dirname "$dstrel")"
  local tmp="$target/$dstrel.tmp.$$"
  if ! strip_provenance_frontmatter "$src/$rel" > "$tmp"; then
    rm -f "$tmp"
    echo "ERROR: refusing to deploy $rel with a half-stripped frontmatter; target left untouched." >&2
    exit 3
  fi
  mv "$tmp" "$target/$dstrel"
  if ! cmp -s "$src/$rel" "$target/$dstrel"; then
    fm_stripped_count=$((fm_stripped_count + 1))
  fi
  verify_stripped_list+=("$rel|$dstrel")
}

# --- always-on: provenance-line guard over the deployed copies (6 files); the
# clean source leaves them byte-identical.
copy_stripped 'always-on/CLAUDE.md' 'CLAUDE.md'
for f in "$src"/always-on/rules/*.md; do
  copy_stripped "always-on/rules/$(basename "$f")" "rules/$(basename "$f")"
done

# --- agent cards: provenance-frontmatter guard, verified against the
# guard-processed content below (every card now has no such key and deploys
# unchanged; the guard would act only if one crept back).
for f in "$src"/agents/*.md; do
  copy_stripped_frontmatter "agents/$(basename "$f")" "agents/$(basename "$f")"
done

# --- everything else: copied byte-identical, hash-verified below.

for d in "$src"/skills/*/; do
  [ -d "$d" ] || continue
  sk="$(basename "$d")"
  mkdir -p "$target/skills/$sk"
  copy_verified "skills/$sk/SKILL.md" "skills/$sk/SKILL.md"
  # Carry a skill's references/ folder if it has one (the curated skills ship
  # references; the native runbooks do not).
  if [ -d "$src/skills/$sk/references" ]; then
    mkdir -p "$target/skills/$sk/references"
    for rf in "$src/skills/$sk"/references/*; do
      [ -e "$rf" ] || continue
      copy_verified "skills/$sk/references/$(basename "$rf")" "skills/$sk/references/$(basename "$rf")"
    done
  fi
done

# Prune retired factory skills, gated by skills-shipped.txt (the append-only
# manifest of every skill folder this COS has ever shipped). A host skills/ folder
# is removed ONLY when it is BOTH listed in the manifest (an earlier release
# shipped it) AND absent from the current source (this release retired it) - e.g.
# skills/unslop, shipped then renamed to writing-and-talking-style, would
# otherwise linger beside its replacement on an --update. A folder NOT in the
# manifest is one this COS never shipped (a host-added skill) and is kept. Scoped
# strictly to skills/ subdirectories; nothing else is ever removed. The manifest
# is pre-filtered ONCE here - comment lines and blanks dropped, surrounding
# whitespace trimmed - mirroring the .ps1's Get-Content filter, so a host folder
# named exactly like a comment line can never match (a raw grep -qxF against the
# file would prune such a folder under sh yet keep it under ps1). A missing
# manifest is guarded like the .ps1's Test-Path: one loud warning, prune disabled,
# no error cascade. Matching is grep -qxF (whole-line exact) against the filtered
# list via a here-string, so a non-match (exit 1) sits inside an if-test where
# set -e does not trip and no pipe/SIGPIPE race can flip the result.
manifest="$src/skills-shipped.txt"
if [ -f "$manifest" ]; then
  # Per line: trim leading then trailing whitespace, drop comment lines (leading
  # # after the trim) and blank lines. Matches the .ps1's -notmatch '^\s*#' plus
  # .Trim() plus drop-empties. sed exits 0 even when every line is filtered out.
  shipped="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "$manifest")"
  manifest_ok=1
else
  shipped=""
  manifest_ok=0
  echo "WARNING: skills-shipped.txt not found at $manifest - prune disabled; no host skill folder is removed this run (a shipped-then-retired skill would linger, but nothing host-added is at risk)." >&2
fi
# Self-policing: every skill this release ships must be listed in the manifest, or
# a future retirement of it could never be pruned (the gate would read it as
# host-added). Warn loudly per missing name; the deploy still proceeds. Skipped
# when the manifest is absent - the one warning above already stands, and this
# loop would otherwise flag every skill (an error cascade).
if [ "$manifest_ok" -eq 1 ]; then
  for d in "$src"/skills/*/; do
    [ -d "$d" ] || continue
    sk="$(basename "$d")"
    if ! grep -qxF "$sk" <<< "$shipped"; then
      echo "WARNING: skills-shipped.txt does not list '$sk' - add it, or a future retirement cannot be pruned." >&2
    fi
  done
fi
if [ -d "$target/skills" ]; then
  for d in "$target"/skills/*/; do
    [ -d "$d" ] || continue
    sk="$(basename "$d")"
    [ -d "$src/skills/$sk" ] && continue   # still in source: keep
    if grep -qxF "$sk" <<< "$shipped"; then
      rm -rf "$d"
      echo "Pruned retired factory skill: skills/$sk (an earlier release shipped it; this one does not)"
    else
      echo "Kept host-added skill: skills/$sk (this COS never shipped it, so the deploy does not manage it)"
    fi
  done
fi

for f in "$src"/hooks/*.sh; do
  copy_verified "hooks/$(basename "$f")" "hooks/$(basename "$f")"
  chmod +x "$target/hooks/$(basename "$f")"   # the guard hooks must be executable
done

for f in "$src"/launch/*.sh; do
  copy_verified "launch/$(basename "$f")" "launch/$(basename "$f")"
  chmod +x "$target/launch/$(basename "$f")"   # the launcher scripts must be executable
done

copy_verified '.mcp.json' '.mcp.json'

# Host companion: settings.local.json beside this script (gitignored, never
# tracked - publishable-clean) carries host-specific settings such as
# permissions.additionalDirectories. When present it is deep-merged into the
# deployed settings.json (objects merge key by key, arrays concatenate without
# duplicates, companion scalars win); the tracked settings.json stays clean.
# The launcher's --setting-sources user means only the deployed settings.json
# governs a session, so this merge is the one door for host values. Tracked
# example: settings.local.example.json. Mirrors deploy-to-host.ps1; needs
# python3 only when a companion is present. The merged file is not in the
# byte-identical list (it is derived, not copied).
companion="$src/settings.local.json"
if [ -f "$companion" ]; then
  command -v python3 >/dev/null 2>&1 || { echo "ERROR: settings.local.json is present but python3 was not found; the merge needs it." >&2; exit 1; }
  python3 - "$src/settings.json" "$companion" "$target/settings.json" <<'PY'
import json, sys
def merge(b, o):
    for k, v in o.items():
        if k in b and isinstance(b[k], dict) and isinstance(v, dict):
            merge(b[k], v)
        elif k in b and isinstance(b[k], list) and isinstance(v, list):
            b[k] = b[k] + [x for x in v if x not in b[k]]
        else:
            b[k] = v
    return b
with open(sys.argv[1], encoding='utf-8') as f: base = json.load(f)
# utf-8-sig: the host companion may be saved with a UTF-8 BOM (some Windows
# editors add one); utf-8-sig strips a leading BOM if present and reads plain
# UTF-8 otherwise, so a BOM'd settings.local.json does not crash the merge.
with open(sys.argv[2], encoding='utf-8-sig') as f: over = json.load(f)
with open(sys.argv[3], 'w', encoding='utf-8') as f:
    json.dump(merge(base, over), f, indent=2, ensure_ascii=False); f.write('\n')
PY
  echo "settings.json: deployed as source merged with the host companion settings.local.json."
else
  copy_verified 'settings.json' 'settings.json'
fi

# Integrity: every deployed file hash-compares against source - byte-identical,
# except the agent cards (compared against their guard-processed content, which
# equals source byte-for-byte while the source ships clean, as it now does).
# (chmod above changes mode, not content, so it does not affect these hashes.)
echo ""
echo "Verifying deployed files against source (sha256)..."
failed=()
for pair in "${verify_list[@]}"; do
  rel="${pair%%|*}"
  dstrel="${pair##*|}"
  a="$(sha256 "$src/$rel")"
  b="$(sha256 "$target/$dstrel")"
  if [ "$a" != "$b" ]; then
    failed+=("$dstrel")
  fi
done
for pair in "${verify_stripped_list[@]}"; do
  rel="${pair%%|*}"
  dstrel="${pair##*|}"
  a="$(strip_provenance_frontmatter "$src/$rel" | sha256_stdin)"
  b="$(sha256 "$target/$dstrel")"
  if [ "$a" != "$b" ]; then
    failed+=("$dstrel")
  fi
done
if [ "${#failed[@]}" -gt 0 ]; then
  echo "HASH MISMATCH on:" >&2
  for p in "${failed[@]}"; do echo "  $p" >&2; done
  exit 1
fi
echo ""
echo "All $(( ${#verify_list[@]} + ${#verify_stripped_list[@]} )) files hash-verified (the agent cards against their guard-processed content). Provenance guards ran clean: $always_on_stripped_count always-on comment line(s) and $fm_stripped_count agent card field(s) stripped - the source ships clean of factory provenance, so the guards act only if it ever creeps back."

echo ""
echo "Deployed inventory (the staged set only):"
{
  echo "CLAUDE.md"
  [ -f "$companion" ] && echo "settings.json (merged with the host companion)"
  for f in "$src"/always-on/rules/*.md; do echo "rules/$(basename "$f")"; done
  for pair in "${verify_list[@]}"; do echo "${pair##*|}"; done
  for pair in "${verify_stripped_list[@]}"; do echo "${pair##*|}"; done
} | LC_ALL=C sort | sed 's/^/  /'

echo ""
echo "Anything else inside the target (credentials, sessions, caches, file history, the plugin-marketplace catalog the harness fetches on its own) is the harness's runtime state; this script never touches it."

echo ""
echo "Start sessions from any directory with:"
echo "  \"$target/launch/start-ensemble.sh\""
echo "(or add the one-word alias named in that script's header)."
echo ""
echo "Next step (one-time): launch it and run /login once."
echo ""
echo "IMPORTANT: restart any Ensemble session that is already open - config (settings, permission rules, MCP wiring) is read at session start, so a running session keeps its old instructions until you relaunch it."
