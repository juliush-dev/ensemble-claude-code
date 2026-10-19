#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - the Operator's here.now kit: sites and Drive.
# ASCII-only, LF line endings (the subtree's *.sh eol=lf attribute).
set +xv
#
# The one command the Operator's shell runs; hooks/guard-herenow.sh blocks
# everything else the Operator types. Reads pass the gate; a write asks unless
# the Operator marks it --ordered (the dispatch quotes the human's order) and
# its local source lies inside the session's root; a --public publish always
# asks. The kit finds the host's here-now skill and hands a publish to the
# skill's scripts/publish.sh and a Drive call to its scripts/drive.sh, each
# with a fixed argument set, after refusing what this COS never sends. Site
# access and site reads it calls here.now's API itself, through curl. It ships
# no here.now code: the skill, curl, file, jq and the account's API key are a
# declared host requirement, never shipped.
#
# Usage (the only forms the here.now gate accepts from the Operator):
#   herenow.sh check
#   herenow.sh manifest "<path>"
#   herenow.sh site-ls
#   herenow.sh site-files "<slug>"
#   herenow.sh site-cat "<slug>" "<path>"
#   herenow.sh drive-ls
#   herenow.sh drive-ls "<drive>" ["<prefix>"]
#   herenow.sh drive-cat "<drive>" "<path>"
#   herenow.sh publish "<path>" [--slug <slug>] [--title "<text>"] [--description "<text>"] [--ordered | --public]
#   herenow.sh drive-put "<drive>" "<path>" --from "<local-file>" [--ordered]
#
# CHECK is offline: it names the skill folder and its version, runs curl, file
# and jq for their versions, and says which key carrier is present, never the
# key, and whether HERENOW_DRIVE_TOKEN is set. The deploy scripts call it once
# per run for the inventory line. Lines:
#   SKILL: <dir> | SKILL: NOT FOUND (looked in ...)
#   VERSION: <x.y.z> | VERSION: unknown
#   BINARY: <name> <version> | MISSING: <name>      (curl, file, jq)
#   KEY: env | KEY: credentials-file | KEY: NONE
#   KEYFILE-MODE: <octal>                            (when the key file exists)
#   DRIVE-TOKEN: set | DRIVE-TOKEN: unset
#
# MANIFEST is local: it applies the refusals below and prints every file a
# publish of the path would upload (its path, byte size and content type, the
# type guessed the way the host script guesses it) and the count. The
# Operator's draft quotes this list. CHECK and MANIFEST never read the key and
# never call curl.
#
# The paths the kit prints (TARGET, FROM, SKILL, the looked-in list) are in the
# host's own spelling, through cygpath -w where it exists: on Windows under
# Git Bash that is the backslash form (C:\...), even for a path given with
# forward slashes. TARGET is also the resolved absolute path (pwd -P), so a
# check that compares it with the path as passed resolves and normalizes
# that path first.
#
# SITE READS (no upload, the API called directly):
#   site-ls     GET /api/v1/publishes (the personal account; no workspace),
#               then GET /api/v1/publish/<slug>/access for each, at most 100:
#               SITE: <slug> | <siteUrl> | access <owner-only | restricted
#               (n emails, n domains) | anyone_with_link | password> | updated
#               <updatedAt> | status <status>; then SITES: <n>, and ACCESS:
#               not read for <n> more past 100.
#   site-files  GET /api/v1/publish/<slug>/files: FILE: <path> (<size> bytes,
#               <contentType>), FILES: <n>, VERSION: <currentVersionId>. The
#               url field of each file is never used.
#   site-cat    the size from that listing, refused above 204,800 bytes before
#               any fetch; then GET /api/v1/publish/<slug>/files/<path> with
#               curl's --max-filesize 204800, and the bytes refused again when
#               the answer runs past the cap. A NUL byte prints BINARY: <n>
#               bytes, not shown.
# DRIVE READS (through the skill's drive.sh, working directory $HOME):
#   drive-ls    drive.sh ls [<drive> [<prefix>]]; the output cut at 204,800
#               bytes with a TRUNCATED line.
#   drive-cat   drive.sh cat <drive> <path> into head -c 204801; above
#               204,800 bytes refused with nothing printed; BINARY as site-cat.
#
# PUBLISH, owner-only by default. A new site without --public:
#   1. a one-line neutral placeholder (<!doctype html><title>.</title>) in a
#      temporary folder goes up through publish.sh with --client only (no
#      title, no description), working directory $HOME; the host script must
#      report publish_result.auth_mode=authenticated, else STOPPED, exit 7;
#   2. PATCH /api/v1/publish/<slug>/access to restricted with no allowed
#      emails or domains (here.now's owner-only, "Only you");
#   3. GET the access; anything but restricted with both lists empty is
#      STOPPED, exit 7: the placeholder stays live, nothing of the target
#      went up; on success ACCESS: owner-only, verified before content;
#   4. publish.sh "<target>" --slug <slug> [--title] [--description];
#   5. GET the access again: ACCESS: owner-only, verified after content; if it
#      is not, PATCH owner-only, GET again, EXPOSED and exit 8, or EXPOSED,
#      NOT RE-LOCKED and exit 9 when the re-lock does not verify (access
#      surviving a content update is undocumented);
#   6. WINDOW: how many seconds the placeholder was reachable by anyone with
#      its address (from step 1's end to step 3's verify);
#   7. the host script's output (the site URL on its own line, then the
#      publish_result lines), ACT: a new site, owner-only (placeholder first);
#      the placeholder folder removed.
# An update (--slug) without --public first GETs the access and refuses, exit
# 2 with nothing uploaded, unless the site is owner-only; then step 4 and step
# 5. The kit never PATCHes a site it did not find owner-only or create in this
# run (an access PATCH clears a site's password).
# --public: a new site goes up through publish.sh as the host script makes it
# (anyone with the link); an update keeps the site's current access, no PATCH;
# after either, ACCESS: <mode> (not owner-only) from a GET.
# --ordered changes nothing inside the kit but the line ORDERED: yes; the gate
# reads it. --ordered and --public together are refused, and each at most once.
#
# DRIVE-PUT: the local file is refused as a publish target is (below), and
# must be a regular file; the Drive path is refused on a control character, a
# .. segment, a leading slash or a backslash; --from exactly once. The kit
# runs drive.sh ls <drive> <path> first and prints ACT: new or ACT: replaces
# <bytes> bytes, etag <etag> (an overwrite is allowed when the Operator's
# draft named it from a prior drive-ls), then drive.sh put <drive> <path>
# --from <file>, relaying its answer.
#
# THE SKILL IS LOOKED FOR in this order, a symbolic link followed; a folder
# counts only when scripts/publish.sh in it is a readable file (the Drive
# commands also need scripts/drive.sh):
#   $CLAUDE_CONFIG_DIR/skills/here-now, $HOME/.claude/skills/here-now,
#   $HOME/.agents/skills/here-now.
# The version is the first "**Skill version: N**" line of its SKILL.md. The
# binaries are probed by running them (--version), never by name lookup alone;
# jq is the skill's own bin/jq when that is executable (the host script prefers
# it), else jq on PATH.
#
# THE KEY. check reports the carrier by existence only. The site reads and
# publish read the key themselves, inside this run only, as here.now's access
# and read calls require: HERENOW_API_KEY when non-empty, else
# ~/.herenow/credentials with whitespace stripped, into a shell variable that
# is never exported and is unset on the way out. A key that is empty or holds
# whitespace or a control character is refused (exit 5) before any call. The
# key goes to curl on its standard input only (printf, a shell builtin, piped
# into curl -H @-), never on a command line, in an environment or in a file;
# curl runs with -q (no .curlrc), --proto =https, --max-time 60, never -L or
# -v, its own messages discarded, HERENOW_API_KEY and HERENOW_DRIVE_TOKEN
# removed from its environment; every URL is built here from
# https://here.now/api/v1/, a slug matching [a-z0-9-]+ and a path encoded
# segment by segment, never taken from a response. An API error prints the
# HTTP status and the server's error text only. HERENOW_DRIVE_TOKEN is unset
# before any Drive call, so drive.sh uses the account key. The host scripts,
# publish.sh and drive.sh, find the key themselves and are handed nothing of
# it; they put it on curl's command line (publish.sh 1.29.0 line 330,
# drive.sh line 86), a residual of the skill, not of this kit.
#
# Exit codes: 0 done (check: ready); 2 refused (usage, a flag, a path or a
# value the kit does not accept, a size cap, an update of a site that is not
# owner-only); 3 the skill (or its drive.sh) not found; 4 found but incomplete
# (a binary or, for check, the key missing, named on stdout); 5 no usable key
# on this host; 6 a host script's upload ran and failed (its status printed);
# 7 STOPPED: the placeholder could not be made and verified owner-only, nothing
# of the target uploaded; 8 EXPOSED: the site was not owner-only after the
# content went up, re-locked and verified; 9 EXPOSED, NOT RE-LOCKED; 10 a read
# of here.now failed (an API error, or a host script's read).
#
# Refusals, each with the harm it prevents:
#   - no key found, or a key carrier yielding an empty key (publish, site
#     reads, Drive): an anonymous, world-readable 24-hour site whose claim token
#     the host script writes into local state, or a call that cannot be
#     authenticated; this COS publishes authenticated sites only;
#   - a target or local file that does not exist, is not a regular file or
#     folder (drive-put: not a regular file), or is itself a symbolic link: a
#     link under an innocent name uploading whatever it points to, while the
#     manifest shows the link's name;
#   - a target whose own path runs through a .git or .herenow folder, or a
#     folder holding, at any depth, an entry named .git, .herenow or .env*, a
#     file named credentials, .netrc or .pgpass, or a private key (*.pem,
#     *.p12, *.pfx, id_rsa*, id_dsa*, id_ecdsa*, id_ed25519*) (names compared
#     without regard to case): repository history, here.now state and keys,
#     environment secrets and private keys uploaded. The refusal names the
#     offending path and never trims it, since a trimmed publish is a silent
#     decision;
#   - a folder part of which could not be read, or a file name carrying a
#     control character: a manifest that cannot say truthfully what uploads;
#   - for publish, any option outside --slug, --title, --description,
#     --ordered and --public, each named in the refusal: --api-key and --token
#     (a key on a command line reaches transcripts and hook input), --base-url
#     and --allow-nonherenow-base-url (the key sent to another endpoint),
#     --claim-token (anonymous sites), --overwrite (replaces a live version
#     someone else changed; a later act class), --workspace (a team account; a
#     later act class), --ttl (an expiring site; a later act class),
#     --from-drive and --version (publishing from Drive, outside this kit),
#     --spa (routing the audited flow does not cover), --client (fixed here);
#     for drive-put, any option outside --from and --ordered, the same four
#     credential and base-url flags named; for the reads, any option at all;
#   - every drive.sh command but ls, cat and put: share mints bearer tokens
#     (write by default), import uploads a folder with no secret exclusions, rm
#     and delete destroy, export writes into a local tree, tokens and revoke
#     manage tokens, create and default reshape the account;
#   - a slug outside [a-z0-9-], a title or description that is empty or carries
#     a control character or a double quote, a site or Drive path that is
#     empty or carries a control character, a .. segment, a leading slash or a
#     backslash, a drive name that is empty, starts with - or carries a control
#     character: a value that changes meaning between the gate's reading and
#     the call.
# What the kit does not do: print, copy, store or pass a key; follow a
# redirect or a URL from a response; fetch here.now's docs; write anything in
# a project tree.
# Residual, not stopped here: a secret in a plainly named file is not
# recognized, and an ordered publish or upload no longer puts the file list in
# front of the human: the manifest in the Operator's draft stands before it,
# and the site is owner-only. The placeholder is reachable by anyone with its
# address for the WINDOW the kit prints. The gate judges whether a path lies
# inside the session's root by its text; the kit resolves it (TARGET and FROM
# print the resolved path), so a folder inside the root that is a link to
# elsewhere is caught only by that line. drive-put's new-or-replaces line reads
# one listing page; when the listing runs past it without the path, the line
# says so. site-ls reads the personal account only.

set +a
set -u
# Functions imported from the environment could stand in for curl or printf.
for _fn in $(compgen -A function); do unset -f "$_fn"; done
unset _fn

CLIENT='claude-code/ensemble'
SKILL_VERSION_RE='^\*\*Skill version: ([0-9][0-9.]*)\*\*'
API_BASE='https://here.now/api/v1/'
CAP=204800
PLACEHOLDER='<!doctype html><title>.</title>'
OWNER_ONLY_BODY='{"mode":"restricted","allowedEmails":[],"allowedDomains":[]}'
BAD_NAMES='a .git, .herenow or .env* entry, a credentials, .netrc or .pgpass file, or a private key (*.pem, *.p12, *.pfx, id_rsa*, id_dsa*, id_ecdsa*, id_ed25519*)'

# The Drive token: reported by check, then unset for every call that follows.
drive_token_state=unset
[ -n "${HERENOW_DRIVE_TOKEN:-}" ] && drive_token_state=set
unset HERENOW_DRIVE_TOKEN

usage() {
  {
    echo "Usage: herenow.sh check"
    echo "       herenow.sh manifest \"<path>\""
    echo "       herenow.sh site-ls"
    echo "       herenow.sh site-files \"<slug>\""
    echo "       herenow.sh site-cat \"<slug>\" \"<path>\""
    echo "       herenow.sh drive-ls [\"<drive>\" [\"<prefix>\"]]"
    echo "       herenow.sh drive-cat \"<drive>\" \"<path>\""
    echo "       herenow.sh publish \"<path>\" [--slug <slug>] [--title \"<text>\"] [--description \"<text>\"] [--ordered | --public]"
    echo "       herenow.sh drive-put \"<drive>\" \"<path>\" --from \"<local-file>\" [--ordered]"
  } >&2
  exit 2
}

refuse() {
  echo "REFUSED: $1" >&2
  exit 2
}

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# --- temporary files, and the way out ------------------------------------------------
api_key=""
tmp_list=""
# new_tmp <variable> [dir]: a temporary file (or folder), removed on the way out.
new_tmp() {
  local _t
  if [ "${2:-}" = dir ]; then _t="$(mktemp -d 2>/dev/null)"; else _t="$(mktemp 2>/dev/null)"; fi
  [ -n "$_t" ] || refuse "no temporary file could be made"
  tmp_list="$tmp_list
$_t"
  printf -v "$1" '%s' "$_t"
}
cleanup() {
  api_key=""
  unset api_key
  local _t _oldifs="$IFS"
  IFS='
'
  set -f
  # Only what mktemp made in this run, and never a root, a relative path or a .. path.
  for _t in $tmp_list; do
    case "$_t" in
      *..*) ;;
      /?*/?*|[A-Za-z]:/?*/?*) rm -rf -- "$_t" ;;
    esac
  done
  set +f
  IFS="$_oldifs"
}
trap cleanup EXIT

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
# Server text for a line a person reads: control characters dropped.
clean() { LC_ALL=C tr -d '\000-\010\013-\037\177'; }

# --- values ---------------------------------------------------------------------------
check_slug() {
  printf '%s' "$1" | LC_ALL=C grep -Eq '^[a-z0-9-]+$' \
    || refuse "the slug '$(printf '%s' "$1" | clean)' carries a character outside a-z 0-9 - or is empty"
}
# check_rel_path <label> <value>: a site or Drive path, relative to its root.
check_rel_path() {
  [ -n "$2" ] || refuse "the $1 is empty"
  has_cntrl "$2" && refuse "the $1 carries a control character"
  case "$2" in /*) refuse "the $1 starts with a slash; give it relative to the root" ;; esac
  case "$2" in *\\*) refuse "the $1 carries a backslash" ;; esac
  case "/$2/" in */../*) refuse "the $1 carries a .. segment" ;; esac
  return 0
}
check_drive_name() {
  [ -n "$1" ] || refuse "the drive name is empty"
  has_cntrl "$1" && refuse "the drive name carries a control character"
  case "$1" in -*) refuse "the drive name starts with -" ;; esac
  return 0
}
# no_options <subcommand> <args...>: the reads take no option at all.
no_options() {
  local _sub="$1"; shift
  for _a in "$@"; do
    case "$_a" in
      --api-key*|--token*) refuse "$_a: a credential on a command line reaches transcripts and hook input; $_sub takes no option" ;;
      --base-url*|--allow-nonherenow-base-url) refuse "$_a: sends the key to an endpoint other than here.now; $_sub takes no option" ;;
      -*) refuse "$_a: $_sub takes no option" ;;
    esac
  done
}

# --- the skill ------------------------------------------------------------------------
skill_dir=""
looked_in=""
find_skill() {
  looked_in=""
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

# --- the binaries -----------------------------------------------------------------------
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
JQ=jq
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
pick_jq() {
  JQ=jq
  if [ -n "$skill_dir" ] && [ -x "$skill_dir/bin/jq" ]; then JQ="$skill_dir/bin/jq"; fi
}

# --- the key: existence for check, the value only for the kit's own calls ---------------
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
NO_KEY_TEXT="no API key on this host (neither HERENOW_API_KEY nor ~/.herenow/credentials); here.now's key is a host requirement, see the Prerequisites."
nothing_text="Nothing was sent."
# load_key: the key into the unexported shell variable api_key, or exit 5.
load_key() {
  api_key=""
  if [ -n "${HERENOW_API_KEY:-}" ]; then
    api_key="$HERENOW_API_KEY"
  elif [ -f "$keyfile" ] && [ -r "$keyfile" ]; then
    api_key="$(tr -d '[:space:]' < "$keyfile" 2>/dev/null)"
    if [ -z "$api_key" ]; then
      echo "NO KEY: the key file ~/.herenow/credentials holds no key (empty, or whitespace only). $nothing_text"
      exit 5
    fi
  fi
  if [ -z "$api_key" ]; then echo "NO KEY: $NO_KEY_TEXT $nothing_text"; exit 5; fi
  case "$api_key" in
    *[![:graph:]]*) api_key=""; echo "NO KEY: the key carrier's value holds whitespace or a control character inside the key, which would change the request. $nothing_text"; exit 5 ;;
  esac
  return 0
}

# --- the API ------------------------------------------------------------------------------
api_out=""
api_code=""
api_msg=""
# api <METHOD> <path below /api/v1/> [json body] [max bytes]: one call, the key
# on curl's standard input. Answers 0 on a 2xx, else sets api_msg; the body is
# in $api_out either way.
api() {
  local _args _rc _err
  [ -n "$api_out" ] || new_tmp api_out
  : > "$api_out"
  _args=(-q -sS --proto =https --max-time 60 -o "$api_out" -w '%{http_code}' -X "$1" -H @-)
  [ -n "${3:-}" ] && _args+=(-H 'content-type: application/json' --data-raw "$3")
  [ -n "${4:-}" ] && _args+=(--max-filesize "$4")
  api_code="$(printf 'authorization: Bearer %s\n' "$api_key" \
    | env -u HERENOW_API_KEY -u HERENOW_DRIVE_TOKEN curl "${_args[@]}" "$API_BASE$2" 2>/dev/null)"
  _rc=$?
  case "$api_code" in [0-9][0-9][0-9]) ;; *) api_code=000 ;; esac
  if [ "$_rc" -eq 0 ] && [ "$api_code" -ge 200 ] && [ "$api_code" -lt 300 ]; then
    api_msg=""; return 0
  fi
  if [ "$_rc" -eq 63 ]; then api_msg="the answer ran past the ${CAP}-byte cap"; return 63; fi
  if [ "$api_code" = 000 ]; then api_msg="no HTTP answer (curl exit $_rc)"; return 1; fi
  _err="$("$JQ" -r '.error // empty' "$api_out" 2>/dev/null | head -c 300 | clean)"
  api_msg="HTTP $api_code${_err:+: $_err}"
  return 1
}
read_fail() { echo "READ FAILED: $1: $api_msg"; exit 10; }

# The API reads need curl and jq, and the key.
api_ready() {
  find_skill >/dev/null 2>&1 || skill_dir=""
  pick_jq
  _bins="$(probe_binaries)"
  case "$_bins" in
    *'MISSING: curl'*|*'MISSING: jq'*)
      printf '%s\n' "$_bins" | grep '^MISSING: \(curl\|jq\)'
      echo "INCOMPLETE: the kit cannot call here.now without the binaries named MISSING above; the Operator reports the gap"
      exit 4 ;;
  esac
  load_key
}

# read_access <slug>: 0 when read; sets acc_label (owner-only | restricted (n
# emails, n domains) | the mode) and acc_owner (1 when owner-only).
acc_label=""
acc_owner=0
read_access() {
  acc_label=""; acc_owner=0
  api GET "publish/$1/access" || return 1
  if "$JQ" -e '.access.mode == "restricted" and .access.allowedEmails == [] and .access.allowedDomains == []' "$api_out" >/dev/null 2>&1; then
    acc_owner=1; acc_label="owner-only"; return 0
  fi
  acc_label="$("$JQ" -r '.access | if .mode == "restricted" then "restricted (\((.allowedEmails // []) | length) emails, \((.allowedDomains // []) | length) domains)" else (.mode | tostring) end' "$api_out" 2>/dev/null | head -n 1 | clean)"
  case "$acc_label" in
    'restricted ('*|anyone_with_link|password|account_members) ;;
    *) acc_label="unreadable" ;;
  esac
  return 0
}
lock_owner_only() { api PATCH "publish/$1/access" "$OWNER_ONLY_BODY"; }

# enc_path <relative path>: each segment through jq's @uri.
enc_path() {
  local _out="" _seg _oldifs="$IFS"
  IFS=/
  set -f
  for _seg in $1; do
    _out="${_out:+$_out/}$("$JQ" -nr --arg v "$_seg" '$v|@uri')"
  done
  set +f
  IFS="$_oldifs"
  printf '%s' "$_out"
}

# show_bytes <file>: the bytes, or the BINARY line when a NUL is among them.
show_bytes() {
  local _n _t
  _n="$(wc -c < "$1" | tr -d ' ')"
  _t="$(tr -d '\000' < "$1" | wc -c | tr -d ' ')"
  if [ "$_n" != "$_t" ]; then echo "BINARY: $_n bytes, not shown"; else cat -- "$1"; fi
}

# --- the target and its refusals --------------------------------------------------
target=""     # the resolved absolute path (Unix form)
is_dir=0
bad_name() {
  # bad_name <base name>: 0 when the name is one the kit refuses to upload.
  case "$(lc "$1")" in
    .git|.herenow|.env*|credentials|.netrc|.pgpass|*.pem|*.p12|*.pfx|id_rsa*|id_dsa*|id_ecdsa*|id_ed25519*) return 0 ;;
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
    bad_name "$_base" && refuse "the file's name ($_base) is one this kit never uploads ($BAD_NAMES): $_raw"
  else
    refuse "the path is neither a regular file nor a folder: $_raw"
  fi
  # Every component of the resolved path.
  _oldifs="$IFS"; IFS=/
  set -f
  for _seg in $target; do
    case "$(lc "$_seg")" in
      .git|.herenow) set +f; IFS="$_oldifs"; refuse "the path runs through a $_seg folder, whose content this kit never uploads: $_raw" ;;
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
    bad_name "$_base" && { rm -f "$_all"; refuse "the folder holds $_rel, an entry this kit never publishes ($BAD_NAMES); remove it or publish a folder without it, never a trimmed copy decided here"; }
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

# --- the host scripts -------------------------------------------------------------------
need_home() {
  [ -n "${HOME:-}" ] || refuse "HOME is not set, and the host scripts keep their state in the working directory"
  [ -d "$HOME" ] || refuse "cannot enter \$HOME, where the host scripts keep their state"
}
# Skill, binaries and key carrier for a publish or a Drive call; prints the lines.
host_ready() {
  if ! find_skill; then
    echo "SKILL: NOT FOUND (looked in $looked_in); the Operator reports the gap"
    exit 3
  fi
  pick_jq
  echo "SKILL: $(to_native "$skill_dir") ($(skill_version))"
  _bins="$(probe_binaries)"
  printf '%s\n' "$_bins"
  case "$_bins" in
    *MISSING:*) echo "INCOMPLETE: the host script cannot run without the binaries named MISSING above; the Operator reports the gap"; exit 4 ;;
  esac
  need_home
}
drive_ready() {
  if ! find_skill; then
    echo "SKILL: NOT FOUND (looked in $looked_in); the Operator reports the gap"
    exit 3
  fi
  if ! { [ -f "$skill_dir/scripts/drive.sh" ] && [ -r "$skill_dir/scripts/drive.sh" ]; }; then
    echo "SKILL: $(to_native "$skill_dir") has no readable scripts/drive.sh; the Operator reports the gap"
    exit 3
  fi
  pick_jq
  _bins="$(probe_binaries)"
  case "$_bins" in
    *MISSING:*) printf '%s\n' "$_bins" | grep '^MISSING:'; echo "INCOMPLETE: the host's drive script cannot run without the binaries named MISSING above; the Operator reports the gap"; exit 4 ;;
  esac
  find_key
  if [ "$key_carrier" = NONE ]; then echo "NO KEY: $NO_KEY_TEXT $nothing_text"; exit 5; fi
  need_home
}
# run_drive <drive.sh arguments...>: the host's drive script, at $HOME.
run_drive() {
  ( CDPATH='' cd -- "$HOME" 2>/dev/null || exit 97
    exec "${BASH:-bash}" "$skill_dir/scripts/drive.sh" "$@" )
}
# run_publish <publish.sh arguments...>: sets pub_out and pub_rc.
pub_out=""
pub_rc=0
run_publish() {
  pub_out="$( CDPATH='' cd -- "$HOME" 2>/dev/null || exit 97
    "${BASH:-bash}" "$skill_dir/scripts/publish.sh" "$@" 2>&1 )"
  pub_rc=$?
}
pub_slug() { printf '%s\n' "$pub_out" | sed -n 's/^publish_result\.slug=//p' | head -n 1 | tr -d '\r'; }
pub_authenticated() { printf '%s\n' "$pub_out" | grep -qx 'publish_result.auth_mode=authenticated'; }

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
    echo "DRIVE-TOKEN: $drive_token_state"
    if [ "$rc" -eq 0 ] && { [ -n "$missing" ] || [ "$key_carrier" = NONE ]; }; then rc=4; fi
    exit "$rc"
    ;;

  manifest)
    [ "$#" -eq 1 ] || usage
    resolve_target "$1"
    walk
    exit 0
    ;;

  site-ls)
    no_options site-ls "$@"
    [ "$#" -eq 0 ] || usage
    api_ready
    api GET publishes || read_fail "the site list"
    rows="$("$JQ" -r 'def c: tostring | gsub("[[:cntrl:]|]"; "?"); .publishes[]? | [(.slug // "" | c), (.siteUrl // "" | c), (.updatedAt // "" | c), (.status // "" | c)] | join("|")' "$api_out" 2>/dev/null)" \
      || { api_msg="the list could not be read as JSON"; read_fail "the site list"; }
    n=0; unread=0; failed=0
    while IFS='|' read -r s_slug s_url s_upd s_st; do
      [ -n "$s_slug$s_url" ] || continue
      n=$((n + 1))
      if [ "$n" -gt 100 ]; then unread=$((unread + 1)); continue; fi
      if ! printf '%s' "$s_slug" | LC_ALL=C grep -Eq '^[a-z0-9-]+$'; then
        acc="not read (the slug carries a character outside a-z 0-9 -)"
      elif read_access "$s_slug"; then
        acc="$acc_label"
      else
        acc="not read ($api_msg)"; failed=$((failed + 1))
      fi
      echo "SITE: $s_slug | $s_url | access $acc | updated $s_upd | status $s_st"
    done <<EOF
$rows
EOF
    echo "SITES: $n"
    [ "$unread" -gt 0 ] && echo "ACCESS: not read for $unread more"
    [ "$failed" -eq 0 ] || { echo "READ FAILED: the access of $failed site(s) could not be read"; exit 10; }
    exit 0
    ;;

  site-files)
    no_options site-files "$@"
    [ "$#" -eq 1 ] || usage
    check_slug "$1"
    api_ready
    api GET "publish/$1/files" || read_fail "the file list of $1"
    "$JQ" -r 'def c: tostring | gsub("[[:cntrl:]]"; "?"); (.files[]? | "FILE: \(.path | c) (\(.size | c) bytes, \(.contentType // "unknown" | c))"), "FILES: \(.files // [] | length)", "VERSION: \(.currentVersionId // "unknown" | c)"' "$api_out" 2>/dev/null \
      || { api_msg="the list could not be read as JSON"; read_fail "the file list of $1"; }
    exit 0
    ;;

  site-cat)
    no_options site-cat "$@"
    [ "$#" -eq 2 ] || usage
    check_slug "$1"
    check_rel_path "site path" "$2"
    api_ready
    api GET "publish/$1/files" || read_fail "the file list of $1"
    size="$("$JQ" -r --arg p "$2" '[.files[]? | select(.path == $p)] | if length == 0 then "none" else (.[0].size | tostring) end' "$api_out" 2>/dev/null)"
    case "$size" in
      none) echo "NOT FOUND: $2 is not in the live version of $1"; exit 10 ;;
      ''|*[!0-9]*) refuse "the file list gives no byte size for $2, so the ${CAP}-byte cap cannot be applied before the fetch" ;;
    esac
    [ "$size" -le "$CAP" ] || refuse "$2 is $size bytes, above the kit's ${CAP}-byte cap for site-cat; nothing was fetched"
    new_tmp body
    api GET "publish/$1/files/$(enc_path "$2")" "" "$CAP"
    arc=$?
    [ "$arc" -eq 63 ] && refuse "$2 ran past the kit's ${CAP}-byte cap while it was fetched; nothing shown"
    [ "$arc" -eq 0 ] || read_fail "$2 of $1"
    cp -- "$api_out" "$body"
    got="$(wc -c < "$body" | tr -d ' ')"
    [ "$got" -le "$CAP" ] || refuse "$2 came back as $got bytes, above the kit's ${CAP}-byte cap; nothing shown"
    show_bytes "$body"
    exit 0
    ;;

  drive-ls)
    no_options drive-ls "$@"
    [ "$#" -le 2 ] || usage
    [ "$#" -ge 1 ] && check_drive_name "$1"
    [ "$#" -eq 2 ] && check_rel_path "prefix" "$2"
    drive_ready
    new_tmp out; new_tmp err
    run_drive ls "$@" > "$out" 2> "$err"
    drc=$?
    if [ "$drc" -ne 0 ]; then
      head -c 2000 "$err" | clean
      echo "READ FAILED: the host's drive script exited $drc (its own message above)"
      exit 10
    fi
    got="$(wc -c < "$out" | tr -d ' ')"
    if [ "$got" -gt "$CAP" ]; then
      head -c "$CAP" "$out"
      echo ""
      echo "TRUNCATED: the listing ran to $got bytes; the first $CAP are shown. Name a drive and a narrower prefix."
    else
      cat -- "$out"
    fi
    exit 0
    ;;

  drive-cat)
    no_options drive-cat "$@"
    [ "$#" -eq 2 ] || usage
    check_drive_name "$1"
    check_rel_path "drive path" "$2"
    drive_ready
    new_tmp out; new_tmp err
    run_drive cat "$1" "$2" 2> "$err" | head -c "$((CAP + 1))" > "$out"
    drc="${PIPESTATUS[0]}"
    got="$(wc -c < "$out" | tr -d ' ')"
    [ "$got" -le "$CAP" ] || refuse "$2 runs past the kit's ${CAP}-byte cap for drive-cat; nothing shown"
    if [ "$drc" -ne 0 ]; then
      head -c 2000 "$err" | clean
      echo "READ FAILED: the host's drive script exited $drc (its own message above)"
      exit 10
    fi
    show_bytes "$out"
    exit 0
    ;;

  drive-put)
    [ "$#" -ge 2 ] || usage
    drive="$1"; dpath="$2"; shift 2
    from=""; have_from=0; ordered=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --from)
          [ "$have_from" -eq 0 ] || refuse "--from given twice"
          [ "$#" -ge 2 ] || refuse "--from needs a value"
          from="$2"; have_from=1; shift 2 ;;
        --ordered)
          [ "$ordered" -eq 0 ] || refuse "--ordered given twice"
          ordered=1; shift ;;
        --api-key|--api-key=*|--token|--token=*)
          refuse "${1%%=*}: a credential on a command line reaches transcripts and hook input; the host script finds the key itself" ;;
        --base-url|--base-url=*|--allow-nonherenow-base-url)
          refuse "${1%%=*}: sends the key to an endpoint other than here.now; not a form this kit takes" ;;
        -*)
          refuse "$1: an option drive-put does not take (only --from and --ordered)" ;;
        *)
          refuse "a stray word ('$1'); drive-put takes a drive, a path and --from" ;;
      esac
    done
    check_drive_name "$drive"
    check_rel_path "drive path" "$dpath"
    [ "$have_from" -eq 1 ] || refuse "--from \"<local-file>\" is missing; drive-put uploads one named local file"
    resolve_target "$from"
    [ "$is_dir" -eq 0 ] || refuse "the --from path is a folder; drive-put uploads one regular file (Drive import is outside this kit): $from"
    local_file="$target"
    fsz="$(wc -c < "$local_file" | tr -d ' ')"
    drive_ready
    echo "FROM: $(to_native "$local_file") ($fsz bytes, $(guess_type "$local_file"))"
    echo "TO: drive $drive, path $dpath"
    [ "$ordered" -eq 1 ] && echo "ORDERED: yes"
    new_tmp out; new_tmp err
    run_drive ls "$drive" "$dpath" > "$out" 2> "$err"
    drc=$?
    if [ "$drc" -ne 0 ]; then
      head -c 2000 "$err" | clean
      echo "READ FAILED: the listing before the upload failed (the host's drive script exited $drc); nothing was uploaded"
      exit 10
    fi
    seen="$("$JQ" -r --arg p "$dpath" 'def c: tostring | gsub("[[:cntrl:]]"; "?"); ([.files[]? | select(.path == $p)] | if length == 0 then "none" else "found \(.[0].size | c) bytes, etag \(.[0].etag | c)" end), (if .nextCursor then "more" else "last" end)' "$out" 2>/dev/null)" \
      || { echo "READ FAILED: the listing before the upload could not be read as JSON; nothing was uploaded"; exit 10; }
    case "$seen" in
      found*) echo "ACT: replaces ${seen#found }" | head -n 1 ;;
      'none'*more*) echo "ACT: new, or replaces a file the first listing page did not show (the listing runs past one page)" ;;
      *) echo "ACT: new" ;;
    esac
    echo ""
    put_out="$(run_drive put "$drive" "$dpath" --from "$local_file" 2>&1)"
    prc=$?
    printf '%s\n' "$put_out"
    if [ "$prc" -ne 0 ]; then
      echo "UPLOAD FAILED: the host's drive script exited $prc (its own message above)."
      exit 6
    fi
    exit 0
    ;;

  publish)
    [ "$#" -ge 1 ] || usage
    path_arg=""
    slug=""; title=""; description=""
    have_slug=0; have_title=0; have_desc=0; ordered=0; public=0
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
              check_slug "$_val"
              slug="$_val"; have_slug=1 ;;
            --title)
              [ "$have_title" -eq 0 ] || refuse "--title given twice"
              title="$_val"; have_title=1 ;;
            --description)
              [ "$have_desc" -eq 0 ] || refuse "--description given twice"
              description="$_val"; have_desc=1 ;;
          esac
          ;;
        --ordered)
          [ "$ordered" -eq 0 ] || refuse "--ordered given twice"
          ordered=1; shift ;;
        --public)
          [ "$public" -eq 0 ] || refuse "--public given twice"
          public=1; shift ;;
        --api-key|--api-key=*|--token|--token=*)
          refuse "${1%%=*}: the kit never passes a key on a command line, where transcripts and hook input would carry it; the host script finds the key itself" ;;
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
          refuse "$1: publishing from Drive, outside this kit" ;;
        --spa)
          refuse "--spa: SPA routing, outside the audited publish flow" ;;
        --client|--client=*)
          refuse "--client: the kit sets the client attribution itself ($CLIENT)" ;;
        -*)
          refuse "$1: an option the kit does not take (only --slug, --title, --description, --ordered and --public)" ;;
        *)
          [ -z "$path_arg" ] || refuse "a second path or a stray word ('$1'); one path per publish"
          path_arg="$1"; shift ;;
      esac
    done
    [ -n "$path_arg" ] || usage
    [ "$ordered" -eq 1 ] && [ "$public" -eq 1 ] \
      && refuse "--ordered with --public: an ordered publish is owner-only, and a public one always asks"
    resolve_target "$path_arg"
    walk
    echo ""
    host_ready
    nothing_text="Nothing was published."
    load_key
    if [ -n "${HERENOW_API_KEY:-}" ]; then echo "KEY: env"; else echo "KEY: credentials-file"; fi
    [ "$ordered" -eq 1 ] && echo "ORDERED: yes"
    echo ""
    set -- "$target" --client "$CLIENT"
    [ "$have_title" -eq 1 ] && set -- "$@" --title "$title"
    [ "$have_desc" -eq 1 ] && set -- "$@" --description "$description"

    # --- public: as the host script makes it, then the access read -------------------
    if [ "$public" -eq 1 ]; then
      [ "$have_slug" -eq 1 ] && set -- "$@" --slug "$slug"
      run_publish "$@"
      printf '%s\n' "$pub_out"
      case "$pub_out" in
        *'publish_result.auth_mode=anonymous'*)
          echo "WARNING: the host script published ANONYMOUSLY (it read no key, though the kit read one): a 24-hour site whose claim token sits in ~/.herenow/state.json. Report it; the human decides what follows." ;;
      esac
      if [ "$pub_rc" -ne 0 ]; then
        echo "PUBLISH FAILED: the host's publish script exited $pub_rc (its own message above)."
        exit 6
      fi
      s="$slug"; [ -n "$s" ] || s="$(pub_slug)"
      if ! printf '%s' "$s" | LC_ALL=C grep -Eq '^[a-z0-9-]+$'; then
        echo "ACCESS: not read (the host script named no slug the kit accepts)"; exit 10
      fi
      read_access "$s" || { echo "ACCESS: not read after the publish ($api_msg)"; exit 10; }
      if [ "$acc_owner" -eq 1 ]; then echo "ACCESS: owner-only"; else echo "ACCESS: $acc_label (not owner-only)"; fi
      if [ "$have_slug" -eq 1 ]; then echo "ACT: update of the site $slug, its access kept (--public)"
      else echo "ACT: a new site, PUBLIC (--public)"; fi
      exit 0
    fi

    # --- an update: only of a site found owner-only ------------------------------------
    if [ "$have_slug" -eq 1 ]; then
      read_access "$slug" || { echo "READ FAILED: the access of $slug ($api_msg); nothing was uploaded"; exit 10; }
      [ "$acc_owner" -eq 1 ] || refuse "an update without --public goes only to an owner-only site, and $slug is $acc_label; nothing was uploaded"
      echo "ACCESS: owner-only, verified before content"
      new_slug="$slug"
      window=""
    else
      # --- a new site: placeholder, lock, verify ----------------------------------------
      new_tmp ph dir
      printf '%s\n' "$PLACEHOLDER" > "$ph/index.html" || refuse "the placeholder could not be written"
      run_publish "$ph" --client "$CLIENT"
      t0="$(date +%s 2>/dev/null)"
      if [ "$pub_rc" -ne 0 ]; then
        printf '%s\n' "$pub_out"
        echo "PUBLISH FAILED: the host's publish script exited $pub_rc on the placeholder (its own message above); nothing of the target was uploaded."
        exit 6
      fi
      new_slug="$(pub_slug)"
      if ! pub_authenticated; then
        printf '%s\n' "$pub_out"
        echo "STOPPED: the placeholder went up without publish_result.auth_mode=authenticated, so it cannot be locked to the owner; nothing of the target was uploaded. Report it; the human decides what follows."
        exit 7
      fi
      if ! printf '%s' "$new_slug" | LC_ALL=C grep -Eq '^[a-z0-9-]+$'; then
        printf '%s\n' "$pub_out"
        echo "STOPPED: the host script named no slug the kit accepts for the placeholder; nothing of the target was uploaded."
        exit 7
      fi
      why=""
      if ! lock_owner_only "$new_slug"; then why="the owner-only lock failed ($api_msg)"
      elif ! read_access "$new_slug"; then why="the access could not be read back ($api_msg)"
      elif [ "$acc_owner" -ne 1 ]; then why="the access reads back as $acc_label"
      fi
      if [ -n "$why" ]; then
        echo "STOPPED: the placeholder site $new_slug is live and not verified owner-only ($why); nothing of the target was uploaded"
        exit 7
      fi
      t1="$(date +%s 2>/dev/null)"
      echo "ACCESS: owner-only, verified before content"
      window=""
      case "$t0$t1" in *[!0-9]*|'') ;; *) window="$((t1 - t0))" ;; esac
    fi

    # --- the content, then the access again -----------------------------------------------
    run_publish "$@" --slug "$new_slug"
    if [ "$pub_rc" -ne 0 ]; then
      printf '%s\n' "$pub_out"
      echo "PUBLISH FAILED: the host's publish script exited $pub_rc on the content (its own message above); the site $new_slug stays owner-only."
      exit 6
    fi
    erc=0
    if read_access "$new_slug" && [ "$acc_owner" -eq 1 ]; then
      echo "ACCESS: owner-only, verified after content"
    else
      was="${acc_label:-not readable ($api_msg)}"
      if lock_owner_only "$new_slug" && read_access "$new_slug" && [ "$acc_owner" -eq 1 ]; then
        echo "EXPOSED: the site was $was after the content update; re-locked and verified at $(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
        erc=8
      else
        echo "EXPOSED, NOT RE-LOCKED: the site was $was after the content update, and the re-lock did not verify${api_msg:+ ($api_msg)}. Tell the human now."
        erc=9
      fi
    fi
    [ -n "$window" ] && echo "WINDOW: the placeholder was reachable by anyone with its address for $window s"
    echo ""
    printf '%s\n' "$pub_out"
    if [ "$have_slug" -eq 1 ]; then echo "ACT: update of the site $slug, owner-only"
    else echo "ACT: a new site, owner-only (placeholder first)"; fi
    exit "$erc"
    ;;

  drive-*)
    refuse "$cmd: outside this kit. Of drive.sh only ls, cat and put are reachable: share mints bearer tokens (write by default), import uploads a folder with no secret exclusions, rm and delete destroy, export writes into a local tree, tokens and revoke manage tokens, create and default reshape the account" ;;
  site-*)
    refuse "$cmd: outside this kit; the site reads are site-ls, site-files and site-cat" ;;
  *)
    usage ;;
esac
