#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - Scout PreToolUse guard on Bash.
# ASCII-only, LF line endings (the subtree's *.sh eol=lf attribute).
#
# The Scout's shell runs one thing: the retrieval kit, tools/scout-fetch.sh,
# which lands a foreign source in the session scratchpad. This guard is an
# ALLOWLIST: one command shape passes, everything else is blocked (exit 2,
# never an ask - a background Scout cannot answer one). The block message
# prints the one accepted form. The Examiner's guard is the opposite form, a
# blocklist, because its shell is open by purpose (it runs whatever tests a
# check needs); a shell with one purpose takes an allowlist, where conforming
# to the printed form is the only move and nothing unmatched ever runs.
#
# The accepted form (single or repeated spaces between the words):
#   "$CLAUDE_CONFIG_DIR/tools/scout-fetch.sh" [--render|--check] "<https URL>" <PATH>
# where
#   - the kit is named as "$CLAUDE_CONFIG_DIR/tools/scout-fetch.sh", quoted or
#     not, with the variable name in exactly that case (a differently cased
#     name is another, unset variable, so bash would run /tools/scout-fetch.sh),
#     or by the config directory's own expanded path in any of the forms this
#     host spells it (quoted; unquoted only when it has no space; compared
#     case-insensitively on Windows, where the file system is);
#   - the URL is double-quoted, https, made only of the ASCII characters
#     A-Z a-z 0-9 . _ ~ % / ? = & + : # , ! * ' ( ) - (so no userinfo "@", no
#     "$", no backtick, no second quote, no bracketed IPv6 literal), and its
#     host passes url_problem below: no percent-encoding, a dotted name or a
#     public dotted-quad IPv4, never loopback, private, link-local, shared,
#     multicast, single-label, .localhost, .local, .internal, .localdomain,
#     .home.arpa or a bare or shorthand numeric form;
#   - PATH is under the calling session's own scratchpad, quoted or not:
#     the hook input's scratchpad_dir (a documented common input field,
#     Claude Code 2.1.257 and later) when the harness sends it, and always
#     inside the scratchpad root set as well; when the input carries no
#     scratchpad_dir, the root set alone. Below the root every segment
#     matches [A-Za-z0-9_-][A-Za-z0-9._-]* (no "..", no dotfiles, no empty
#     segments); an unquoted PATH carries no backslash.
# Nothing else may appear: no shell metacharacter (; | & < > backtick $ ( ) { })
# or newline outside the two quoted arguments, no second URL or path, no second
# flag, no environment assignment in front (so the Scout never chooses the
# browser binary). The URL and PATH checks are re-run inside the kit.
#
# The scratchpad root set is the one hooks/guard-archivist-paths.sh builds for
# its scratchpad exemption (LOCALAPPDATA/Temp/claude, TEMP/claude, TMP/claude
# in long and 8.3 short form via cygpath; on POSIX, only when none of those is
# set, ${TMPDIR:-/tmp}/claude and ${TMPDIR:-/tmp}/claude-<digits>), extended by
# the forms a Git Bash command naturally uses: the drive form /c/... and the
# mount form (Git Bash mounts the user's Temp at /tmp, so /tmp/claude there is
# the same folder). The URL check (url_problem, byte-identical) and the root
# set here are kept identical to tools/scout-fetch.sh's; change both
# together. The session anchor is the guard's alone: the kit sees no hook
# input, and relies on refusing any name that already exists instead.
#
# Still string-matching, like every house guard: the Bash tool hands this
# guard the command text and bash parses it after. The shape is kept narrow
# enough that the two readings cannot differ: every word is quoted or free of
# anything bash expands.

set -u

ACCEPTED='"$CLAUDE_CONFIG_DIR/tools/scout-fetch.sh" [--render|--check] "<https URL>" <path under the session scratchpad>'

block() {
  {
    echo "Scout guard: blocked ($1)."
    echo "Your shell runs one command, the retrieval kit, in this form:"
    echo "  $ACCEPTED"
    echo "Conform to that form or stop and report, never reshape around it."
  } >&2
  exit 2
}

input="$(cat 2>/dev/null || true)"
# Key-scoped, non-greedy capture of the command value (the Examiner guard's
# extraction): stop at the value's own closing quote, a backslash-escaped quote
# counting as interior text, so no other field bleeds into the string.
raw="$(printf '%s' "$input" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1)"
[ -n "$raw" ] || block "no command could be read from the tool input"

printf '%s' "$raw" | LC_ALL=C grep -q '[[:cntrl:]]' && block "a control character in the command"
# JSON escapes: only \" and \\ belong to the accepted form. \n, \t, \r, \u...
# would decode to a newline, a tab or an arbitrary character.
_rest_esc="${raw//\\\\/}"
case "$_rest_esc" in
  *\\[!\"]*|*\\) block "a newline, tab or other escaped character in the command" ;;
esac
cmd="${raw//\\\\/$'\001'}"
cmd="${cmd//\\\"/\"}"
cmd="${cmd//$'\001'/\\}"

# Trim the ends.
cmd="${cmd#"${cmd%%[! ]*}"}"
cmd="${cmd%"${cmd##*[! ]}"}"

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
norm_root() { printf '%s' "$1" | tr '\\' '/' | sed 's:/*$::'; }
# The drive form of a mixed Windows path (C:/x -> /c/x), built from cygpath's
# own drive prefix: "cygpath -u" alone renders a mounted folder by its mount
# (Git Bash mounts the user's Temp at /tmp), never as /c/...
drive_unix() {
  case "$1" in
    [A-Za-z]:/*)
      _dp="$(cygpath -u "${1%%/*}/" 2>/dev/null)"
      [ -n "$_dp" ] && printf '%s' "${_dp%/}/${1#*:/}" ;;
  esac
}

win_host=0
{ [ -n "${LOCALAPPDATA:-}" ] || [ -n "${TEMP:-}" ] || [ -n "${TMP:-}" ]; } && win_host=1

# --- the kit word ---------------------------------------------------------------
# The two variable forms match case-sensitively everywhere; the expanded path
# forms case-insensitively on Windows.
literal_words='"$CLAUDE_CONFIG_DIR/tools/scout-fetch.sh"
$CLAUDE_CONFIG_DIR/tools/scout-fetch.sh'
kit_words=""
add_dir_forms() {
  _d="$1"
  [ -n "$_d" ] || return 0
  _forms="$_d
$(norm_root "$_d")"
  if command -v cygpath >/dev/null 2>&1; then
    _ml="$(cygpath -m -l "$_d" 2>/dev/null)"
    _ms="$(cygpath -m -s "$_d" 2>/dev/null)"
    _forms="$_forms
$_ml
$_ms
$(cygpath -u "$_d" 2>/dev/null)
$(drive_unix "$(norm_root "$_d")")
$(drive_unix "$_ml")
$(drive_unix "$_ms")"
  fi
  _oldifs="$IFS"; IFS='
'
  for _f in $_forms; do
    [ -n "$_f" ] || continue
    _f="${_f%/}"; _f="${_f%\\}"
    case "$_f" in
      *\\*) _sep='\' ;;
      *)    _sep='/' ;;
    esac
    _k="$_f${_sep}tools${_sep}scout-fetch.sh"
    kit_words="$kit_words
\"$_k\""
    case "$_k" in
      *' '*|*\\*) ;;
      *) kit_words="$kit_words
$_k" ;;
    esac
  done
  IFS="$_oldifs"
}
add_dir_forms "${CLAUDE_CONFIG_DIR:-}"
_self_home="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
add_dir_forms "$_self_home"

rest=""
_oldifs="$IFS"; IFS='
'
for _w in $literal_words; do
  case "$cmd" in
    "$_w "*) rest="${cmd:${#_w}}"; break ;;
  esac
done
if [ -z "$rest" ]; then
  _cmd_cmp="$cmd"
  [ "$win_host" -eq 1 ] && _cmd_cmp="$(lc "$cmd")"
  for _w in $kit_words; do
    [ -n "$_w" ] || continue
    case "$_w" in *'$'*) continue ;; esac   # an expanded path never holds a variable
    _wc="$_w"
    [ "$win_host" -eq 1 ] && _wc="$(lc "$_w")"
    case "$_cmd_cmp" in
      "$_wc "*) rest="${cmd:${#_w}}"; break ;;
    esac
  done
fi
IFS="$_oldifs"
[ -n "$rest" ] || block "the command is not the retrieval kit"

# --- flag -----------------------------------------------------------------------
rest="${rest#"${rest%%[! ]*}"}"
case "$rest" in
  "--render "*) rest="${rest#--render}" ;;
  "--check "*)  rest="${rest#--check}" ;;
  -*)           block "an option the kit does not take" ;;
esac
rest="${rest#"${rest%%[! ]*}"}"
case "$rest" in
  -*) block "a second flag" ;;
esac

# --- URL ------------------------------------------------------------------------
case "$rest" in
  \"*) ;;
  \'*) block "a single-quoted URL; double quotes only" ;;
  *)   block "an unquoted URL; double quotes only" ;;
esac
rest="${rest#\"}"
case "$rest" in
  *\"*) ;;
  *) block "an unterminated quote" ;;
esac
url="${rest%%\"*}"
rest="${rest#*\"}"
case "$rest" in
  " "*) ;;
  "")   block "no path after the URL" ;;
  *)    block "text glued to the URL's closing quote" ;;
esac
rest="${rest#"${rest%%[! ]*}"}"

# url_problem is kept byte-identical to tools/scout-fetch.sh's; change both
# together (the kit's comment above its copy says what it checks).
url_problem() {
  _u="$1"
  url_reason=""
  case "$_u" in
    'https://['*) url_reason="the host is a bracketed IPv6 literal; the kit takes named hosts and public IPv4 only"; return 1 ;;
  esac
  printf '%s' "$_u" | LC_ALL=C grep -Eq "^https://[A-Za-z0-9._~%/?=&+:#,!*'()-]+\$" \
    || { url_reason="the URL is not https or carries a character outside A-Z a-z 0-9 . _ ~ % / ? = & + : # , ! * ' ( ) -"; return 1; }
  _r="${_u#https://}"
  _hostport="${_r%%[/?#]*}"
  _host="${_hostport%%:*}"
  case "$_hostport" in
    *:*) _port="${_hostport#*:}"
         case "$_port" in ''|*[!0-9]*) url_reason="the URL's port is not a number"; return 1 ;; esac ;;
  esac
  case "$_host" in
    *%*) url_reason="the host carries a percent-encoding ($_host), which curl and browsers decode"; return 1 ;;
  esac
  _host="$(printf '%s' "$_host" | tr '[:upper:]' '[:lower:]')"
  _host="${_host%"${_host##*[!.]}"}"
  [ -n "$_host" ] || { url_reason="the URL has no host"; return 1; }
  case "$_host" in
    .*|*..*) url_reason="the host has an empty label ($_host)"; return 1 ;;
    localhost|*.localhost|*.local|*.internal|*.localdomain|home.arpa|*.home.arpa)
      url_reason="the host is local ($_host)"; return 1 ;;
    *.*) ;;
    *) url_reason="the host is a single label ($_host), which resolves through local name services"; return 1 ;;
  esac
  case "$_host" in
    0x*|*.0x*) url_reason="the host is a numeric form ($_host)"; return 1 ;;
    *[!0-9.]*) return 0 ;;   # a name, not a numeric address
  esac
  # All digits and dots: only a plain public dotted quad passes.
  _oldifs="$IFS"; IFS=.
  # shellcheck disable=SC2086
  set -- $_host
  IFS="$_oldifs"
  [ "$#" -eq 4 ] || { url_reason="the host is a shorthand numeric form ($_host)"; return 1; }
  for _o in "$@"; do
    case "$_o" in ''|0?*) url_reason="the host has an empty or zero-padded octet ($_host)"; return 1 ;; esac
    [ "$_o" -le 255 ] || { url_reason="the host is not an address ($_host)"; return 1; }
  done
  case "$1" in 0|10|127) url_reason="the host is a local or private address ($_host)"; return 1 ;; esac
  [ "$1" -ge 224 ] && { url_reason="the host is a multicast or reserved address ($_host)"; return 1; }
  [ "$1" = 169 ] && [ "$2" = 254 ] && { url_reason="the host is a link-local address ($_host)"; return 1; }
  [ "$1" = 192 ] && [ "$2" = 168 ] && { url_reason="the host is a private address ($_host)"; return 1; }
  [ "$1" = 172 ] && [ "$2" -ge 16 ] && [ "$2" -le 31 ] && { url_reason="the host is a private address ($_host)"; return 1; }
  [ "$1" = 100 ] && [ "$2" -ge 64 ] && [ "$2" -le 127 ] && { url_reason="the host is a shared (carrier) address ($_host)"; return 1; }
  return 0
}

check_url() {
  url_problem "$1" || block "$url_reason"
}
check_url "$url"

# --- PATH -----------------------------------------------------------------------
has_meta() {
  case "$1" in
    *[\;\|\&\<\>\`\$\(\)\{\}]*) return 0 ;;
  esac
  return 1
}
case "$rest" in
  \"*)
    _p="${rest#\"}"
    case "$_p" in *\"*) ;; *) block "an unterminated quote" ;; esac
    path="${_p%%\"*}"
    after="${_p#*\"}"
    has_meta "$after" && block "a shell metacharacter outside the quoted arguments"
    after="${after#"${after%%[! ]*}"}"
    [ -z "$after" ] || block "more than one URL or path, or words after the path"
    ;;
  "")
    block "no path after the URL" ;;
  *)
    has_meta "$rest" && block "a shell metacharacter outside the quoted arguments"
    case "$rest" in
      *\"*|*\'*) block "a quote inside an unquoted path" ;;
      *' '*)     block "more than one URL or path, or words after the path" ;;
      *\\*)      block "a backslash in an unquoted path (bash would eat it); quote the path or use forward slashes" ;;
    esac
    path="$rest"
    ;;
esac
has_meta "$path" && block "a shell metacharacter in the path"

path="$(printf '%s' "$path" | tr '\\' '/')"

scratch_roots=""
add_root() {
  [ -n "$1" ] && scratch_roots="$scratch_roots
$1"
}
add_win_root() {
  _r="$1"
  add_root "$_r"
  if command -v cygpath >/dev/null 2>&1; then
    _parent="${_r%/claude}"
    _l="$(cygpath -m -l "$_parent" 2>/dev/null)"
    _s="$(cygpath -m -s "$_parent" 2>/dev/null)"
    [ -n "$_l" ] && add_root "${_l%/}/claude"
    [ -n "$_s" ] && add_root "${_s%/}/claude"
    for _f in "$_parent" "$_l" "$_s"; do
      [ -n "$_f" ] || continue
      _u="$(cygpath -u "$_f" 2>/dev/null)"
      [ -n "$_u" ] && add_root "${_u%/}/claude"
      _u="$(drive_unix "$_f")"
      [ -n "$_u" ] && add_root "${_u%/}/claude"
    done
  fi
}
[ -n "${LOCALAPPDATA:-}" ] && add_win_root "$(norm_root "$LOCALAPPDATA")/Temp/claude"
[ -n "${TEMP:-}" ] && add_win_root "$(norm_root "$TEMP")/claude"
[ -n "${TMP:-}" ] && add_win_root "$(norm_root "$TMP")/claude"
posix_tmp=""
if [ "$win_host" -eq 0 ]; then
  posix_tmp="$(norm_root "${TMPDIR:-/tmp}")"
  add_root "$posix_tmp/claude"
fi

# root_rel <path>: sets rr_found (1 when the path is under a root), rr_rel
# (the part below the root) and rr_key (rr_rel, prefixed on POSIX by the
# claude-<digits> segment, so two uid roots never share a key). The key names
# one folder whichever form (short, long, drive, mount) spelled the root.
root_rel() {
  _p="$1"; rr_found=0; rr_rel=""; rr_key=""
  _pc="$_p"
  [ "$win_host" -eq 1 ] && _pc="$(lc "$_p")"
  _oldifs="$IFS"; IFS='
'
  for _root in $scratch_roots; do
    [ -n "$_root" ] || continue
    _rc="$_root"
    [ "$win_host" -eq 1 ] && _rc="$(lc "$_root")"
    case "$_pc" in
      "$_rc"/*) rr_rel="${_p:${#_root}+1}"; rr_key="$rr_rel"; rr_found=1; break ;;
    esac
  done
  IFS="$_oldifs"
  if [ "$rr_found" -eq 0 ] && [ -n "$posix_tmp" ]; then
    case "$_p" in
      "$posix_tmp"/claude-*/*)
        _after="${_p#"$posix_tmp"/claude-}"
        _seg="${_after%%/*}"
        case "$_seg" in
          ''|*[!0-9]*) ;;
          *) rr_rel="${_after#*/}"; rr_key="claude-$_seg/$rr_rel"; rr_found=1 ;;
        esac ;;
    esac
  fi
}
root_rel "$path"
found="$rr_found"; rel="$rr_rel"; path_key="$rr_key"
[ "$found" -eq 1 ] || block "the path is not under the session scratchpad"
[ -n "$rel" ] || block "the path names the scratchpad root, not a file under it"
case "$rel" in */) block "the path ends in a slash" ;; esac
_oldifs="$IFS"; IFS=/
set -f
for _seg in $rel; do
  printf '%s' "$_seg" | LC_ALL=C grep -Eq '^[A-Za-z0-9_-][A-Za-z0-9._-]*$' \
    || { set +f; IFS="$_oldifs"; block "a path segment that is empty, '..', a dotfile, or carries a character outside A-Z a-z 0-9 . _ -"; }
done
set +f
IFS="$_oldifs"

# --- the session anchor -----------------------------------------------------------
# The root set holds every project's and every session's scratch. When the
# hook input names the session's own scratchpad (scratchpad_dir, a common
# input field since Claude Code 2.1.257; a dispatched Scout shares its
# dispatching session's scratchpad), PATH must also lie under it, so a Scout
# cannot land a file in another session's scratchpad or beside its own, in
# the session's tasks/ folder. The value is read with the same key-scoped
# extraction as the command: inside a JSON string every quote is escaped, so
# no string value can forge the key. Only the \\ and \/ escapes are read;
# any other escape in the value blocks rather than guesses.
sp_raw="$(printf '%s' "$input" | sed -nE 's/.*"scratchpad_dir"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1)"
if [ -n "$sp_raw" ]; then
  _sp_chk="${sp_raw//\\\\/}"
  _sp_chk="${_sp_chk//\\\//}"
  case "$_sp_chk" in
    *\\*) block "the session's scratchpad_dir carries an escape this guard does not read" ;;
  esac
  sp="$(printf '%s' "$sp_raw" | sed -e 's:\\\\:/:g' -e 's:\\/:/:g')"
  sp="$(norm_root "$sp")"
  # Compared below the root, where both sides are plain long names (a "~"
  # short segment fails the segment rule above), so the root's own spelling
  # (short, long, drive or mount form) cannot make one folder look like two.
  root_rel "$sp"
  [ "$rr_found" -eq 1 ] && [ -n "$rr_key" ] \
    || block "the session's scratchpad_dir is not under the scratchpad root set ($sp)"
  sp_key="$rr_key"
  _pk="$path_key"; _sk="$sp_key"
  [ "$win_host" -eq 1 ] && { _pk="$(lc "$_pk")"; _sk="$(lc "$_sk")"; }
  case "$_pk" in
    "$_sk"/?*) ;;
    *) block "the path is not under this session's own scratchpad ($sp)" ;;
  esac
fi

exit 0
