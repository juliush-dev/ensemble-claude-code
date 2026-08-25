#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - host deploy script for Linux / macOS.
# ASCII-ONLY FILE with LF line endings, deliberately: a CRLF-terminated bash
# script fails to execute on Linux (the shebang line carries a stray \r), and
# non-ASCII punctuation crossing a Windows-authored boundary can corrupt. Keep
# this file pure ASCII, LF-only.
#
# The Linux/macOS analog of deploy-to-host.ps1. Same behavior, same honesty:
# copies the staged set from this folder into an isolated Claude Code config
# home, strips the provenance comment line from the deployed always-on copies
# (the source keeps them), hash-verifies every byte-identical file, prints the
# inventory, and refuses to clobber an existing home unless --update or --force.
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

if [ -e "$target" ]; then
  if [ "$update" -eq 1 ]; then
    echo "Update mode: overwriting the staged files in place; session, trust, and login state stay untouched. (Git holds the source history for rollback.)"
  elif [ "$force" -eq 1 ]; then
    backup="${target}.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$target" "$backup"
    echo "Rollback baseline: existing target moved to $backup"
  else
    echo ""
    echo "Target already exists. Contents:"
    ls -1 "$target" || true
    echo ""
    echo "Re-run with --update to refresh the staged files in place (keeps login/session state),"
    echo "or with --force to replace the whole home (the existing directory is moved to a timestamped backup first)."
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

copy_verified() {
  # copy_verified <src-rel> <dst-rel>
  local rel="$1" dstrel="$2"
  mkdir -p "$target/$(dirname "$dstrel")"
  cp "$src/$rel" "$target/$dstrel"
  verify_list+=("$rel|$dstrel")
}

copy_stripped() {
  # copy_stripped <src-rel> <dst-rel>
  # Strip the provenance comment line (first line only) if present; copy the
  # rest byte-for-byte. tail -n +2 preserves everything after line 1 exactly,
  # matching the PS regex ^<!-- provenance:[^\r\n]*\r?\n (first line only).
  local rel="$1" dstrel="$2"
  mkdir -p "$target/$(dirname "$dstrel")"
  if head -n 1 "$src/$rel" | grep -q '^<!-- provenance:'; then
    tail -n +2 "$src/$rel" > "$target/$dstrel"
  else
    cp "$src/$rel" "$target/$dstrel"
  fi
}

# --- always-on: provenance line stripped from the deployed copies (6 files).
copy_stripped 'always-on/CLAUDE.md' 'CLAUDE.md'
for f in "$src"/always-on/rules/*.md; do
  copy_stripped "always-on/rules/$(basename "$f")" "rules/$(basename "$f")"
done

# --- everything else: copied byte-identical, hash-verified below.
for f in "$src"/agents/*.md; do
  copy_verified "agents/$(basename "$f")" "agents/$(basename "$f")"
done

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
# provenance: pursuit framework-dna, route dna-into-the-cos, the user's word 2026-08-25.
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
with open(sys.argv[2], encoding='utf-8') as f: over = json.load(f)
with open(sys.argv[3], 'w', encoding='utf-8') as f:
    json.dump(merge(base, over), f, indent=2, ensure_ascii=False); f.write('\n')
PY
  echo "settings.json: deployed as source merged with the host companion settings.local.json."
else
  copy_verified 'settings.json' 'settings.json'
fi

# Integrity: every file deployed byte-identical hash-compares against source.
# (chmod above changes mode, not content, so it does not affect these hashes.)
echo ""
echo "Verifying byte-identical files against source (sha256)..."
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
if [ "${#failed[@]}" -gt 0 ]; then
  echo "HASH MISMATCH on:" >&2
  for p in "${failed[@]}"; do echo "  $p" >&2; done
  exit 1
fi
echo ""
echo "All ${#verify_list[@]} byte-identical files hash-verified; 6 always-on files deployed with the provenance line stripped."

echo ""
echo "Deployed inventory (the staged set only):"
{
  echo "CLAUDE.md"
  [ -f "$companion" ] && echo "settings.json (merged with the host companion)"
  for f in "$src"/always-on/rules/*.md; do echo "rules/$(basename "$f")"; done
  for pair in "${verify_list[@]}"; do echo "${pair##*|}"; done
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
