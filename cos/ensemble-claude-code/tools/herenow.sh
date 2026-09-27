#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - the Operator's here.now publishing kit.
# ASCII-only, LF line endings (the subtree's *.sh eol=lf attribute).
#
# The one command the Operator's shell runs; hooks/guard-herenow.sh blocks
# everything else the Operator types, and asks on every publish. The kit finds
# the host's here-now skill and hands a publish to that skill's own
# scripts/publish.sh with a fixed flag set, after refusing what this COS never
# publishes. It ships no here.now code of its own: the skill, curl, file, jq
# and the account's API key are a declared host requirement, never shipped.
#
# Usage (the only forms the here.now gate accepts from the Operator):
#   herenow.sh check
#   herenow.sh manifest "<path>"
#   herenow.sh publish "<path>" [--slug <slug>] [--title "<text>"] [--description "<text>"]
#
# CHECK is offline: it names the skill folder and its version, runs curl, file
# and jq for their versions, and says which key carrier is present, never the
# key. The deploy scripts call it once per run for the inventory line. Lines:
#   SKILL: <dir> | SKILL: NOT FOUND (looked in ...)
#   VERSION: <x.y.z> | VERSION: unknown
#   BINARY: <name> <version> | MISSING: <name>      (curl, file, jq)
#   KEY: env | KEY: credentials-file | KEY: NONE
#   KEYFILE-MODE: <octal>                            (when the key file exists)
#
# MANIFEST is local: it applies the refusals below and prints every file a
# publish of the path would upload (its path, byte size and content type, the
# type guessed the way the host script guesses it) and the count. The
# Operator's draft quotes this list.
#
# The paths the kit prints (TARGET, SKILL, the looked-in list) are in the
# host's own spelling, through cygpath -w where it exists: on Windows under
# Git Bash that is the backslash form (C:\...), even for a path given with
# forward slashes. TARGET is also the resolved absolute path (pwd -P), so a
# check that compares it with the path as passed resolves and normalizes
# that path first.
#
# PUBLISH applies the same refusals, checks the skill, the binaries and the
# key, then runs, with the working directory at $HOME:
#   bash <skill>/scripts/publish.sh "<absolute path>" --client claude-code/ensemble
#        [--slug <slug>] [--title <text>] [--description <text>]
# The host script normalizes the client string, so here.now receives
# "x-herenow-client: claude-code-ensemble/publish-sh", not the slash form.
# The host script finds the key itself (HERENOW_API_KEY, then
# ~/.herenow/credentials) and writes its state file, .herenow/state.json, in
# its working directory: $HOME here, so the state lands in the user's
# ~/.herenow/ and never in a project tree. Its output is relayed (the site URL
# on its own line, then the publish_result lines).
#
# THE SKILL IS LOOKED FOR in this order, a symbolic link followed; a folder
# counts only when scripts/publish.sh in it is a readable file:
#   $CLAUDE_CONFIG_DIR/skills/here-now, $HOME/.claude/skills/here-now,
#   $HOME/.agents/skills/here-now.
# The version is the first "**Skill version: N**" line of its SKILL.md. The
# binaries are probed by running them (--version), never by name lookup alone;
# jq is the skill's own bin/jq when that is executable (the host script prefers
# it), else jq on PATH.
#
# THE KEY IS TESTED BY EXISTENCE ONLY: the variable by whether it is set and
# non-empty, the file by whether it exists with a size above zero, and its mode.
# Nothing here reads, prints, copies, stores or passes a key.
#
# Exit codes: 0 done (check: ready); 2 refused (usage, a flag, a path the kit
# does not accept); 3 the skill not found; 4 found but incomplete (a binary or,
# for check, the key missing, named on stdout); 5 publish with no key on this
# host; 6 the host's publish script ran and failed (its status printed).
#
# Refusals, each with the harm it prevents:
#   - no key found (publish): an anonymous, world-readable 24-hour site, whose
#     claim token the host script writes into local state; this COS publishes
#     authenticated sites only, the key being a host requirement;
#   - a target that does not exist, is not a regular file or folder, or is
#     itself a symbolic link: a link under an innocent name publishing whatever
#     it points to, while the manifest shows the link's name;
#   - a target whose own path runs through a .git or .herenow folder, or a
#     folder holding, at any depth, an entry named .git, .herenow or .env*, a
#     file named credentials, *.pem or id_rsa* (names compared without regard
#     to case): repository history, here.now state and keys, environment
#     secrets and private keys published to a world-readable URL. The refusal
#     names the offending path and never trims it, since a trimmed publish is a
#     silent decision;
#   - a folder part of which could not be read, or a file name carrying a
#     control character: a manifest that cannot say truthfully what uploads;
#   - any option outside --slug, --title and --description, each named in the
#     refusal: --api-key (a key on a command line reaches transcripts and hook
#     input), --base-url and --allow-nonherenow-base-url (the key sent to
#     another endpoint), --claim-token (anonymous sites), --overwrite (replaces
#     a live version someone else changed; a later act class), --workspace (a
#     team account; a later act class), --ttl (an expiring site; a later act
#     class), --from-drive and --version (Drive publishing, outside this kit),
#     --spa (routing the audited flow does not cover), --client (fixed here);
#   - a slug outside [a-z0-9-], a title or description that is empty or carries
#     a control character or a double quote: a value that changes meaning
#     between the gate's reading and the host script's.
# What the kit does not do: read, print, copy or store a key; call any
# endpoint but through the skill's own script; fetch here.now's docs; write
# anything in a project tree.
# Residual, not stopped here: a credentials file holding only whitespace passes
# the size test while the host script reads no key from it and publishes
# anonymously; the kit then prints a warning after the fact. A secret in a
# plainly named file is not recognized: the manifest in the Operator's draft
# and the human's prompt are what stand between it and the URL.

set -u

CLIENT='claude-code/ensemble'
SKILL_VERSION_RE='^\*\*Skill version: ([0-9][0-9.]*)\*\*'

usage() {
  {
    echo "Usage: herenow.sh check"
    echo "       herenow.sh manifest \"<path>\""
    echo "       herenow.sh publish \"<path>\" [--slug <slug>] [--title \"<text>\"] [--description \"<text>\"]"
  } >&2
  exit 2
}

refuse() {
  echo "REFUSED: $1" >&2
  exit 2
}

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# A Windows path (C:\x or C:/x) in the Unix form Git Bash's tools read.
to_unix() {
  case "$1" in
    [A-Za-z]:[\\/]*|[A-Za-z]:)
      if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1" | tr '\\' '/'; fi ;;
    *) printf '%s' "$1" ;;
  esac
}
# The host's own spelling of a path, for the lines a person reads.
to_native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; else printf '%s' "$1"; fi
}

# A newline is a line separator to grep, never a match, so it is tested apart.
has_cntrl() {
  case "$1" in *'
'*) return 0 ;; esac
  printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'
}

# --- the skill ------------------------------------------------------------------
skill_dir=""
looked_in=""
find_skill() {
  _cands=""
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && _cands="$(to_unix "$CLAUDE_CONFIG_DIR")/skills/here-now"
  [ -n "${HOME:-}" ] && _cands="$_cands
$HOME/.claude/skills/here-now
$HOME/.agents/skills/here-now"
  _oldifs="$IFS"; IFS='
'
  for _c in $_cands; do
    [ -n "$_c" ] || continue
    looked_in="${looked_in:+$looked_in, }$(to_native "$_c")"
    if [ -f "$_c/scripts/publish.sh" ] && [ -r "$_c/scripts/publish.sh" ]; then
      IFS="$_oldifs"; skill_dir="$_c"; return 0
    fi
  done
  IFS="$_oldifs"
  return 1
}

skill_version() {
  _v="$(LC_ALL=C sed -nE "s/$SKILL_VERSION_RE.*/\\1/p" "$skill_dir/SKILL.md" 2>/dev/null | head -n 1)"
  printf '%s' "${_v:-unknown}"
}

# --- the binaries ---------------------------------------------------------------
missing=""
# probe <name> <note> <command>: prints BINARY or MISSING; the version is the
# first token of the --version output's first line that starts with a digit,
# a "<name>-" prefix dropped (file-5.48, jq-1.8.2).
probe() {
  _name="$1"; _note="$2"; _bin="$3"
  _out="$("$_bin" --version 2>/dev/null | head -n 1)"
  if [ -z "$_out" ]; then
    echo "MISSING: $_name"
    missing="${missing:+$missing, }$_name"
    return 1
  fi
  _ver=""
  set -f
  for _t in $_out; do
    _t="${_t#"$_name"-}"
    case "$_t" in [0-9]*) _ver="$_t"; break ;; esac
  done
  set +f
  echo "BINARY: $_name ${_ver:-unknown}$_note"
  return 0
}
probe_binaries() {
  missing=""
  probe curl '' curl
  probe file '' file
  if [ -n "$skill_dir" ] && [ -x "$skill_dir/bin/jq" ]; then
    probe jq " (the skill's bin/jq)" "$skill_dir/bin/jq"
  else
    probe jq '' jq
  fi
  return 0
}

# --- the key: existence only ------------------------------------------------------
key_carrier="NONE"
keyfile="${HOME:-/nonexistent}/.herenow/credentials"
find_key() {
  if [ -n "${HERENOW_API_KEY:+x}" ]; then key_carrier="env"
  elif [ -s "$keyfile" ]; then key_carrier="credentials-file"
  else key_carrier="NONE"
  fi
}
keyfile_mode() {
  [ -e "$keyfile" ] || return 1
  _m="$(stat -c '%a' "$keyfile" 2>/dev/null || stat -f '%Lp' "$keyfile" 2>/dev/null)"
  [ -n "$_m" ] && printf '%s' "$_m"
}

# --- the target and its refusals --------------------------------------------------
target=""     # the resolved absolute path (Unix form)
is_dir=0
bad_name() {
  # bad_name <base name>: 0 when the name is one the kit refuses to publish.
  case "$(lc "$1")" in
    .git|.herenow|.env*|credentials|*.pem|id_rsa*) return 0 ;;
  esac
  return 1
}
resolve_target() {
  _raw="$1"
  [ -n "$_raw" ] || refuse "no path given"
  has_cntrl "$_raw" && refuse "the path carries a control character"
  _p="$(to_unix "$_raw")"
  [ -e "$_p" ] || [ -L "$_p" ] || refuse "the path does not exist: $_raw"
  [ -L "$_p" ] && refuse "the path is a symbolic link; name the real file or folder, so the manifest shows what uploads: $_raw"
  if [ -d "$_p" ]; then
    target="$(CDPATH='' cd -- "$_p" 2>/dev/null && pwd -P)" || refuse "the folder cannot be entered: $_raw"
    is_dir=1
  elif [ -f "$_p" ]; then
    _dir="$(dirname -- "$_p")"; _base="$(basename -- "$_p")"
    _dir="$(CDPATH='' cd -- "$_dir" 2>/dev/null && pwd -P)" || refuse "the file's folder cannot be entered: $_raw"
    target="${_dir%/}/$_base"
    is_dir=0
    bad_name "$_base" && refuse "the file's name ($_base) is one this kit never publishes (a .git, .herenow or .env* entry, a credentials file, a *.pem or id_rsa* key): $_raw"
  else
    refuse "the path is neither a regular file nor a folder: $_raw"
  fi
  # Every component of the resolved path.
  _oldifs="$IFS"; IFS=/
  set -f
  for _seg in $target; do
    case "$(lc "$_seg")" in
      .git|.herenow) set +f; IFS="$_oldifs"; refuse "the path runs through a $_seg folder, whose content this kit never publishes: $_raw" ;;
    esac
  done
  set +f
  IFS="$_oldifs"
}

# guess_type <file>: the content type, guessed as the host script guesses it
# (its guess_content_type, publish.sh 1.29.0): by extension, else file(1).
guess_type() {
  case "${1##*.}" in
    html|htm) echo "text/html; charset=utf-8" ;;
    css)      echo "text/css; charset=utf-8" ;;
    js|mjs)   echo "text/javascript; charset=utf-8" ;;
    json)     echo "application/json; charset=utf-8" ;;
    md|txt)   echo "text/plain; charset=utf-8" ;;
    svg)      echo "image/svg+xml" ;;
    png)      echo "image/png" ;;
    jpg|jpeg) echo "image/jpeg" ;;
    gif)      echo "image/gif" ;;
    webp)     echo "image/webp" ;;
    pdf)      echo "application/pdf" ;;
    mp4)      echo "video/mp4" ;;
    mov)      echo "video/quicktime" ;;
    mp3)      echo "audio/mpeg" ;;
    wav)      echo "audio/wav" ;;
    xml)      echo "application/xml" ;;
    woff2)    echo "font/woff2" ;;
    woff)     echo "font/woff" ;;
    ttf)      echo "font/ttf" ;;
    ico)      echo "image/x-icon" ;;
    *)        file --brief --mime-type "$1" 2>/dev/null || echo "application/octet-stream" ;;
  esac
}

# Walks the target: refuses on any entry the kit never publishes, then prints
# the files the host script would upload (it walks with find -type f and
# skips .DS_Store; symbolic links are not regular files and do not upload).
manifest_lines=""
file_count=0
total_bytes=0
walk() {
  echo "TARGET: $(to_native "$target")"
  if [ "$is_dir" -eq 0 ]; then
    _sz="$(wc -c < "$target" | tr -d ' ')"
    echo "FILE: $(basename -- "$target") ($_sz bytes, $(guess_type "$target"))"
    file_count=1; total_bytes="$_sz"
    echo "FILES: 1 ($total_bytes bytes)"
    return 0
  fi
  _err="$(mktemp 2>/dev/null)" || refuse "no temporary file for the folder walk"
  _all="$(mktemp 2>/dev/null)" || { rm -f "$_err"; refuse "no temporary file for the folder walk"; }
  find "$target" -mindepth 1 -print0 > "$_all" 2> "$_err"
  _frc=$?
  if [ "$_frc" -ne 0 ] || [ -s "$_err" ]; then
    rm -f "$_err" "$_all"
    refuse "part of the folder could not be read, so the kit cannot say what a publish would upload: $(to_native "$target")"
  fi
  rm -f "$_err"
  _links=0
  _ds=0
  _files=""
  while IFS= read -r -d '' _f; do
    _rel="${_f#"$target"/}"
    has_cntrl "$_rel" && { rm -f "$_all"; refuse "a file name carries a control character, which the manifest cannot show truthfully (in $(to_native "$target"))"; }
    _base="${_rel##*/}"
    bad_name "$_base" && { rm -f "$_all"; refuse "the folder holds $_rel, an entry this kit never publishes (a .git, .herenow or .env* entry, a credentials file, a *.pem or id_rsa* key); remove it or publish a folder without it, never a trimmed copy decided here"; }
    if [ -L "$_f" ]; then _links=$((_links + 1)); continue; fi
    [ -f "$_f" ] || continue
    [ "$_base" = ".DS_Store" ] && { _ds=$((_ds + 1)); continue; }
    _files="$_files$_rel
"
  done < "$_all"
  rm -f "$_all"
  _oldifs="$IFS"; IFS='
'
  set -f
  for _rel in $(printf '%s' "$_files" | LC_ALL=C sort); do
    _sz="$(wc -c < "$target/$_rel" | tr -d ' ')"
    echo "FILE: $_rel ($_sz bytes, $(guess_type "$target/$_rel"))"
    file_count=$((file_count + 1))
    total_bytes=$((total_bytes + _sz))
  done
  set +f
  IFS="$_oldifs"
  echo "FILES: $file_count ($total_bytes bytes)"
  [ "$_links" -gt 0 ] && echo "SKIPPED: $_links symbolic link(s); the host script uploads regular files only"
  [ "$_ds" -gt 0 ] && echo "SKIPPED: $_ds .DS_Store file(s), as the host script skips them"
  [ "$file_count" -gt 0 ] || refuse "the folder holds no file a publish would upload: $(to_native "$target")"
  return 0
}

# --- subcommands --------------------------------------------------------------------
cmd="${1:-}"
[ "$#" -ge 1 ] && shift

case "$cmd" in
  check)
    [ "$#" -eq 0 ] || usage
    rc=0
    if find_skill; then
      echo "SKILL: $(to_native "$skill_dir")"
      echo "VERSION: $(skill_version)"
    else
      echo "SKILL: NOT FOUND (looked in $looked_in)"
      rc=3
    fi
    probe_binaries
    find_key
    echo "KEY: $key_carrier"
    _m="$(keyfile_mode)" && echo "KEYFILE-MODE: $_m"
    if [ "$rc" -eq 0 ] && { [ -n "$missing" ] || [ "$key_carrier" = NONE ]; }; then rc=4; fi
    exit "$rc"
    ;;

  manifest)
    [ "$#" -eq 1 ] || usage
    resolve_target "$1"
    walk
    exit 0
    ;;

  publish)
    [ "$#" -ge 1 ] || usage
    path_arg=""
    slug=""; title=""; description=""
    have_slug=0; have_title=0; have_desc=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --slug|--title|--description)
          _opt="$1"
          [ "$#" -ge 2 ] || refuse "$_opt needs a value"
          _val="$2"; shift 2
          has_cntrl "$_val" && refuse "the value of $_opt carries a control character"
          case "$_val" in *'"'*) refuse "the value of $_opt carries a double quote" ;; esac
          [ -n "$_val" ] || refuse "the value of $_opt is empty"
          case "$_opt" in
            --slug)
              [ "$have_slug" -eq 0 ] || refuse "--slug given twice"
              printf '%s' "$_val" | LC_ALL=C grep -Eq '^[a-z0-9-]+$' \
                || refuse "the slug '$_val' carries a character outside a-z 0-9 -"
              slug="$_val"; have_slug=1 ;;
            --title)
              [ "$have_title" -eq 0 ] || refuse "--title given twice"
              title="$_val"; have_title=1 ;;
            --description)
              [ "$have_desc" -eq 0 ] || refuse "--description given twice"
              description="$_val"; have_desc=1 ;;
          esac
          ;;
        --api-key|--api-key=*)
          refuse "--api-key: the kit never passes a key on a command line, where transcripts and hook input would carry it; the host script finds the key itself" ;;
        --base-url|--base-url=*|--allow-nonherenow-base-url)
          refuse "$1: sends the key to an endpoint other than here.now; not a form this kit takes" ;;
        --claim-token|--claim-token=*)
          refuse "--claim-token: anonymous-site claim tokens; this COS publishes authenticated sites only" ;;
        --overwrite)
          refuse "--overwrite: skips the stale-base check and replaces a live version someone else changed; a later act class, not built" ;;
        --workspace|--workspace=*)
          refuse "--workspace: publishes into a team account; a later act class, not built" ;;
        --ttl|--ttl=*)
          refuse "--ttl: an expiring site; a later act class, not built" ;;
        --from-drive|--from-drive=*|--version|--version=*)
          refuse "$1: Drive publishing, outside this kit" ;;
        --spa)
          refuse "--spa: SPA routing, outside the audited publish flow" ;;
        --client|--client=*)
          refuse "--client: the kit sets the client attribution itself ($CLIENT)" ;;
        -*)
          refuse "$1: an option the kit does not take (only --slug, --title and --description)" ;;
        *)
          [ -z "$path_arg" ] || refuse "a second path or a stray word ('$1'); one path per publish"
          path_arg="$1"; shift ;;
      esac
    done
    [ -n "$path_arg" ] || usage
    resolve_target "$path_arg"
    walk
    echo ""
    if ! find_skill; then
      echo "SKILL: NOT FOUND (looked in $looked_in); the Operator reports the gap"
      exit 3
    fi
    echo "SKILL: $(to_native "$skill_dir") ($(skill_version))"
    _bins="$(probe_binaries)"
    printf '%s\n' "$_bins"
    case "$_bins" in
      *MISSING:*) echo "INCOMPLETE: the host script cannot run without the binaries named MISSING above; the Operator reports the gap"; exit 4 ;;
    esac
    find_key
    if [ "$key_carrier" = NONE ]; then
      echo "NO KEY: no API key on this host (neither HERENOW_API_KEY nor ~/.herenow/credentials); here.now's key is a host requirement, see the Prerequisites. Nothing was published."
      exit 5
    fi
    echo "KEY: $key_carrier"
    set -- "$target" --client "$CLIENT"
    [ "$have_slug" -eq 1 ] && set -- "$@" --slug "$slug"
    [ "$have_title" -eq 1 ] && set -- "$@" --title "$title"
    [ "$have_desc" -eq 1 ] && set -- "$@" --description "$description"
    if [ "$have_slug" -eq 1 ]; then echo "ACT: update of the site $slug"; else echo "ACT: a new site"; fi
    echo ""
    [ -n "${HOME:-}" ] || refuse "HOME is not set, and the host script keeps its state in the working directory"
    CDPATH='' cd -- "$HOME" 2>/dev/null || refuse "cannot enter \$HOME, where the host script keeps its state"
    out="$("${BASH:-bash}" "$skill_dir/scripts/publish.sh" "$@" 2>&1)"
    prc=$?
    printf '%s\n' "$out"
    case "$out" in
      *'publish_result.auth_mode=anonymous'*)
        echo "WARNING: the host script published ANONYMOUSLY (it read no key, though a key carrier was present): a 24-hour site whose claim token sits in ~/.herenow/state.json. Report it; the human decides what follows." ;;
    esac
    if [ "$prc" -ne 0 ]; then
      echo "PUBLISH FAILED: the host's publish script exited $prc (its own message above)."
      exit 6
    fi
    exit 0
    ;;

  *)
    usage ;;
esac
