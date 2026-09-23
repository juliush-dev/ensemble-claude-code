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
# alone.
#
# settings.json is not copied but MERGED, by merge-settings.py, the one merge
# implementation both deploy scripts call: the paths source and the host
# companion settings.local.json declare are replaced, the paths
# settings-shipped.txt lists and source no longer declares are pruned, and every
# other key the host carries is left exactly as it stands. A host's own settings
# survive an update.
#
# PYTHON 3 IS A PREREQUISITE. Without it this script does not update
# settings.json at all: an existing host file is left exactly as it stands and
# the script says so, loudly, on every run until Python 3 is installed. Only a
# first deploy, where there is no host file to protect, writes source wholesale
# instead (a home with no settings file is useless).
#
# A CHROMIUM-FAMILY BROWSER IS A DECLARED HOST REQUIREMENT, NOT AN ENFORCED ONE.
# The Scout's retrieval kit (tools/scout-fetch.sh) renders script-filled pages
# in a headless Chrome, Edge or Chromium the host already carries (Brave is
# left out of the search until its headless behavior is settled; a Brave path
# still works when named through env.ENSEMBLE_BROWSER); this COS ships no
# browser. Once per run, after everything has landed, the script
# runs the deployed kit's own probe (tools/scout-fetch.sh --check) and prints
# the result as an inventory line: the browser's path and version, or
# 'browser (NOT FOUND - the Scout's rendered reads report the gap)'. Never
# fatal: without a browser everything else lands and the run ends with exit
# code 0, and the Scout says so when a page needs rendering instead of
# guessing. A browser off the standard install paths is named in the host
# companion as env.ENSEMBLE_BROWSER (settings.local.example.md).
#
# It hash-verifies every file in the verified set (byte-identical against
# source, the agent cards against their guard-processed content; the six always-on
# copies excepted), asserts the deployed settings.json path by path against what
# the factory declares, prints the inventory, and refuses to clobber an existing
# home unless --update or --force.
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
# SECOND DOCUMENTED DIVERGENCE: WHERE the no-Python warning is printed. The two
# scripts word that block identically, line for line. The stream differs. This
# script writes every line of it to stderr; the PowerShell script prints its
# copy with Write-Host, which goes to the console through the host/information
# stream and never to stderr. Measured by running the block on each side and
# capturing both streams: on each side everything lands on one stream and
# nothing at all on the other. What follows from it, on each side:
# './deploy-to-host.sh --update 2>/dev/null' silences the whole warning here,
# and a stdout-only log misses it, while on the PowerShell side neither of
# those two redirections reaches the other copy: Write-Host writes the
# information stream, so '> log.txt' captures none of the block and no stderr
# redirection silences it. The information stream itself does reach it, with
# '6>$null' to silence or '6>&1' to capture. Deliberate, not an oversight.
# PowerShell 5.1 has no coloured write to stderr, and its Write-Error under a
# stop-on-error preference would throw and abort the deploy partway through,
# which is worse than a warning the ordinary redirections miss. Both scripts
# keep the loudest block their shell affords; forcing one to match the other's
# stream would buy symmetry with a quieter or a more fragile deploy.
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
for d in rules agents skills hooks tools launch; do
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

for f in "$src"/tools/*.sh; do
  copy_verified "tools/$(basename "$f")" "tools/$(basename "$f")"
  chmod +x "$target/tools/$(basename "$f")"   # the Scout's retrieval kit must be executable
done

for f in "$src"/launch/*.sh; do
  copy_verified "launch/$(basename "$f")" "launch/$(basename "$f")"
  chmod +x "$target/launch/$(basename "$f")"   # the launcher scripts must be executable
done

copy_verified '.mcp.json' '.mcp.json'

# --- settings.json: the preserving merge ------------------------------------
# Host companion: settings.local.json beside this script (gitignored, never
# tracked - publishable-clean) carries host-specific settings such as
# permissions.additionalDirectories. The tracked settings.json stays clean, and
# the launcher's --setting-sources user means only the deployed settings.json
# governs a session, so the companion is the one door for host values. Tracked
# example: settings.local.example.json, with settings.local.example.md beside it
# carrying the guidance (JSON has no comments, and a _provenance key holding it
# would itself be a companion-declared path landing on the host).
#
# merge-settings.py is the single merge implementation both deploy scripts call
# (see its header for the model). It replaces the paths source-plus-companion
# declares, prunes the paths settings-shipped.txt lists and source no longer
# declares, and LEAVES EVERY OTHER HOST KEY ALONE - a plugin toggle, a
# notification preference, a model entry the harness wrote survives an update
# instead of being flattened. It names every host entry it is about to drop
# before it writes. One implementation, so the two scripts cannot disagree about
# a security-relevant file. The deployed file is not in the byte-identical list
# (it is derived, and it legitimately carries host keys); the assertion below
# verifies it instead.
#
# This block sits LAST, after every copy and after .mcp.json, so a failure here
# cannot leave a half-deployed home with everything else stale. The .ps1 now
# orders it the same way.
#
# PYTHON 3 IS PROBED BY RUNNING IT, never by asking whether the command
# resolves. command -v / Get-Command answers yes for the Windows Store alias at
# WindowsApps\python3.exe, which exists on machines with no Python at all and
# opens the Store instead of running anything. The probe here is identical to
# the .ps1's for that reason, and because python on some hosts is still
# Python 2 - the version string is what decides.
#
# NO PYTHON 3. Python 3 is a stated prerequisite of this deploy, and the
# mechanism does not engineer around its absence with a second merge
# implementation. One merge in one language is what keeps parity risk out of a
# security-relevant path. Two branches, both scripts alike:
#
#   * A host settings.json EXISTS. It is not written. Not merged, not copied,
#     not touched. The script prints an unmissable block saying settings were
#     not updated and Python 3 must be installed, and prints it again at the end
#     of the run. It re-fires on every deploy while the condition holds, so the
#     condition is raised by the machine rather than left to anyone's memory.
#     Nothing is ever lost this way; the home simply keeps the settings it had.
#   * NO host settings.json (a first deploy). Source is written wholesale and
#     the script says plainly that the companion was not merged and Python 3 is
#     needed. There is nothing to protect, and a home with no settings file is
#     useless. That copy is hash-verified against source like any other copied
#     file.
#
# (This also replaces the old exit 1, which under the preserving merge would
# have aborted every update on a python3-less host rather than only the
# companion case.)
find_python3() {
  local exe out
  for exe in python3 python; do
    out="$("$exe" --version 2>&1)" || continue
    case "$out" in
      "Python 3"*) echo "$exe"; return 0 ;;
    esac
  done
  return 1
}
companion="$src/settings.local.json"
merge_script="$src/merge-settings.py"
settings_manifest="$src/settings-shipped.txt"
python_exe="$(find_python3)" || python_exe=""
settings_merged=0
settings_copied=0
settings_skipped=0
merge_args=(--source "$src/settings.json" --target "$target/settings.json" --manifest "$settings_manifest")
[ -f "$companion" ] && merge_args+=(--companion "$companion")

# The block the no-Python branches print. One function, called at the moment it
# happens and again at the end of the run, so both printings are the same text.
no_python_block() {
  echo "" >&2
  echo "***************************************************************" >&2
  if [ "$1" = "skipped" ]; then
    echo "SETTINGS NOT UPDATED - PYTHON 3 IS MISSING" >&2
    echo "" >&2
    echo "No working Python 3 was found (tried running 'python3 --version' and" >&2
    echo "'python --version'). Python 3 is a prerequisite of this deploy." >&2
    echo "" >&2
    echo "settings.json was LEFT EXACTLY AS IT WAS:" >&2
    echo "  $target/settings.json" >&2
    echo "Nothing of yours was lost - and nothing new landed there either. This home" >&2
    echo "keeps running the settings it already had, including any older factory" >&2
    echo "rules, until Python 3 is installed." >&2
    echo "" >&2
    echo "Install Python 3, then run this script again." >&2
  else
    echo "PYTHON 3 IS MISSING - settings.json written WITHOUT the companion merge" >&2
    echo "" >&2
    echo "No working Python 3 was found (tried running 'python3 --version' and" >&2
    echo "'python --version'). Python 3 is a prerequisite of this deploy." >&2
    echo "" >&2
    echo "This is a first deploy: there was no settings.json in the target home, so" >&2
    echo "there was nothing to protect and source was copied there wholesale. The" >&2
    echo "host companion settings.local.json was NOT merged in, so" >&2
    echo "permissions.additionalDirectories and anything else in it is missing from" >&2
    echo "the deployed file." >&2
    echo "" >&2
    echo "Install Python 3, then run this script again to get the companion merged." >&2
  fi
  echo "***************************************************************" >&2
  echo "" >&2
}

if [ -z "$python_exe" ]; then
  if [ -f "$target/settings.json" ]; then
    settings_skipped=1
    no_python_block skipped
  else
    cp "$src/settings.json" "$target/settings.json"
    settings_copied=1
    no_python_block first-deploy
  fi
else
  merge_rc=0
  "$python_exe" "$merge_script" merge "${merge_args[@]}" || merge_rc=$?
  if [ "$merge_rc" -eq 3 ]; then
    echo "settings.json WRITTEN BUT NOT VERIFIED (merge-settings.py exited 3, a verification failure). The file was written and then failed its own path-by-path check; it is not trustworthy. See the lines above for which paths." >&2
    exit 1
  elif [ "$merge_rc" -ne 0 ]; then
    echo "settings.json MERGE FAILED (merge-settings.py exited $merge_rc). The deployed settings.json is not trustworthy; everything else in this deploy landed." >&2
    exit 1
  fi
  settings_merged=1
fi

# Integrity: every deployed file hash-compares against source - byte-identical,
# except the agent cards (compared against their guard-processed content, which
# equals source byte-for-byte while the source ships clean, as it now does).
# (chmod above changes mode, not content, so it does not affect these hashes.)
# settings.json is NOT in this set and cannot be: the deployed file legitimately
# carries host keys the factory never declared, so no hash of source says
# anything true about it. It gets the post-write assertion below instead, which
# also closes an old asymmetry - when a companion was present this script used
# to drop settings.json from verification entirely, while the .ps1 verified it.
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

# settings.json's own verification: re-read the deployed file from disk, parse
# it, and assert that every declared path equals source-plus-companion's value
# and every retired path is gone. This is what the hash check used to be for,
# done in the only way that still means something.
if [ "$settings_merged" -eq 1 ]; then
  if ! "$python_exe" "$merge_script" verify "${merge_args[@]}"; then
    echo "SETTINGS VERIFICATION FAILED - the deployed settings.json does not carry what the factory declares (see the lines above)." >&2
    exit 1
  fi
elif [ "$settings_copied" -eq 1 ]; then
  # The first-deploy no-Python branch is a plain byte copy, so a hash is the
  # right instrument for it - the one the merged file can no longer take. It was
  # outside every check until now: out of the byte-identical list because the
  # merged file cannot be hash-compared, and skipped by the assertion because no
  # merge ran.
  if [ "$(sha256 "$src/settings.json")" != "$(sha256 "$target/settings.json")" ]; then
    echo "HASH MISMATCH on: settings.json (wholesale copy of source)" >&2
    exit 1
  fi
  echo "settings.json: wholesale copy of source, hash-verified byte-identical against it (no merge ran, so the path-by-path assertion does not apply)."
else
  echo "settings.json: NOT WRITTEN this run - the existing host file was left untouched because Python 3 is missing. Nothing to verify; see the block above."
fi

echo ""
echo "All $(( ${#verify_list[@]} + ${#verify_stripped_list[@]} )) files hash-verified (the agent cards against their guard-processed content; settings.json is verified separately, by the assertion above). Provenance guards ran clean: $always_on_stripped_count always-on comment line(s) and $fm_stripped_count agent card field(s) stripped - the source ships clean of factory provenance, so the guards act only if it ever creeps back."

# --- The browser probe: a declared host requirement, reported, never fatal ----
# Runs the DEPLOYED kit's own --check once and reads its exit code (0 found,
# 3 no browser, 4 found but the headless render failed) and its BROWSER and
# VERSION lines. Any failure here only changes the inventory line; set -e is
# held off by the if-test.
if probe_out="$("$target/tools/scout-fetch.sh" --check 2>/dev/null)"; then
  probe_rc=0
else
  probe_rc=$?
fi
probe_path="$(printf '%s\n' "$probe_out" | sed -n 's/^BROWSER: //p' | head -n 1)"
probe_ver="$(printf '%s\n' "$probe_out" | sed -n 's/^VERSION: //p' | head -n 1)"
case "$probe_rc" in
  0) browser_line="browser ($probe_path, $probe_ver)" ;;
  3) browser_line="browser (NOT FOUND - the Scout's rendered reads report the gap)" ;;
  4) browser_line="browser (FOUND at $probe_path, $probe_ver, but its headless render returned nothing - the Scout's rendered reads report the gap)" ;;
  *) browser_line="browser (NOT CHECKED - the probe exited $probe_rc)" ;;
esac

echo ""
echo "Deployed inventory (the staged set only):"
{
  echo "CLAUDE.md"
  echo "$browser_line"
  if [ "$settings_skipped" -eq 1 ]; then
    echo "settings.json (NOT WRITTEN - no Python 3; the host file is untouched and unchanged)"
  elif [ "$settings_copied" -eq 1 ]; then
    echo "settings.json (WHOLESALE COPY of source - no Python 3, first deploy, companion not merged)"
  elif [ -f "$companion" ]; then
    echo "settings.json (source merged with the host companion, over the host's own keys)"
  else
    echo "settings.json (source merged over the host's own keys)"
  fi
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

# The no-Python block again, last, so the run cannot end without it having been
# the final thing on screen. It re-fires on every deploy while Python 3 is
# missing; the condition is raised by the script, never left to memory.
[ "$settings_skipped" -eq 1 ] && no_python_block skipped
[ "$settings_copied" -eq 1 ] && no_python_block first-deploy
exit 0
