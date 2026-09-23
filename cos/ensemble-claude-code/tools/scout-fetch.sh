#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - the Scout's retrieval kit.
# ASCII-only, LF line endings (the subtree's *.sh eol=lf attribute).
#
# The one command the Scout's shell runs; hooks/guard-scout-bash.sh blocks
# everything else. It lands a foreign source in the session scratchpad, where
# Read and Grep enumerate it, and says which state of the source it captured.
#
# Usage (the only forms the Scout's guard accepts):
#   scout-fetch.sh "<https URL>" <PATH>             raw download
#   scout-fetch.sh --render "<https URL>" <PATH>    raw download, then a render
#   scout-fetch.sh --check "<https URL>" <PATH>     is a browser here? (no fetch)
# and, for the deploy scripts only:
#   scout-fetch.sh --check                          is a browser here?
#
# RAW MODE downloads the URL's bytes to PATH with curl (-q ignores a host
# .curlrc; https only; 60 s and a 20 MB cap per request) and prints the
# sha256, byte and line counts. curl follows no redirect by itself: the kit
# reads each redirect's target, runs the URL check below on it, and only then
# requests it (at most 5 hops), so every host the download reaches has passed
# the check before its request. For HTML it adds a prose measure: the
# characters of text outside tags, comments, script, style and noscript
# (whitespace runs counted once), plus the bytes held inside script elements.
# The measure reads three ways:
#   prose >= 1500 characters                  fetched: the text is in the file
#   prose < 1500 and file >= 20000 bytes      shell: run again with --render
#                                             onto a new PATH
#   otherwise                                 terse: a small page, little text
#
# RENDER MODE first does the raw download (a render never lands without the
# raw file beside it), then runs a Chromium-family browser headless with a
# fresh profile at <PATH>.profile and dumps the settled DOM of the URL the
# download ended at to <PATH>.rendered.html. It writes <PATH>.provenance.txt
# (the URL asked for and the one the download ended at, UTC time, browser
# path and version, the flag line, sha256/bytes/prose of both files, and the
# line "rendered with headless Chromium, not fetched"), then removes the
# profile directory. A render is one settled state of the page, not a
# superset of the raw file: text held as script data is complete in the raw
# file and partial in the render. The render is judged by the output file's
# size, never by the browser's console text (Chrome on Windows prints
# "Opening in existing browser session." on a fresh headless profile while a
# headed Chrome runs, and still renders headless without the user's cookies).
#
# --check renders an offline data: page (no network) that writes the
# browser's user agent, and reports the browser path and version, or NO
# BROWSER. The deploy scripts call it once per run.
#
# THE BROWSER IS A DECLARED HOST REQUIREMENT, NEVER SHIPPED. Looked for in
# this order: $ENSEMBLE_BROWSER when set and non-empty (then only it); chrome,
# msedge, chromium, chromium-browser at their standard install paths (Windows
# paths through Git Bash, then macOS and Linux paths); then the same names on
# PATH. No browser is assumed to be present, Edge included. Brave is left out
# of the search until its headless behaviour is settled: on the Windows host
# where the kit was built, a headless Brave returned no DOM while a Brave
# window was open, and whether it handed the URL to that window's signed-in
# session was not observed. ENSEMBLE_BROWSER still accepts a Brave path.
#
# Exit codes: 0 done; 2 refused (usage, a URL, redirect target or PATH the
# kit does not accept, or a PATH or sibling name that already exists); 3 NO
# BROWSER; 4 the browser ran and returned no DOM; 5 the raw download failed.
#
# Containment, each with the harm it prevents:
#   - a fresh profile per render, removed after: page script reading the
#     user's signed-in sessions and cookies;
#   - https only, no userinfo, and a host that is a dotted public name or a
#     public dotted-quad IPv4 address: no loopback, private, link-local,
#     shared or multicast address, no bare or shorthand numeric form, no
#     single-label name (it resolves through local name services), no
#     .localhost, .local, .internal, .localdomain or .home.arpa name, no
#     bracketed IPv6 literal (refused whole, not parsed), no percent-encoding
#     and nothing outside ASCII in the host (curl decodes %6c%6fcalhost to
#     localhost and maps a full-width name to its ASCII form): a render or
#     download reaching local services as the user. The same check runs on
#     every redirect target before the kit requests it;
#   - nothing overwritten, nothing removed that this run did not create: the
#     kit refuses when PATH or a sibling it would create (PATH.rendered.html,
#     PATH.provenance.txt, PATH.profile, PATH.check-profile) already exists,
#     creates each file exclusively, and removes on failure only what it
#     created: a download or render replacing or deleting another member's
#     or another session's file under the scratchpad root;
#   - output only under the scratchpad root set (re-checked here after the
#     guard; the guard narrows it further to the calling session's own
#     scratchpad when the harness reports it): a landed file anywhere in a
#     project or the home;
#   - timeout 120 plus the virtual-time budget, and never --no-sandbox: a
#     hung render pinning the Scout; the renderer sandbox lost.
# Residuals, not stopped here (closing them needs a proxy or resolver rules):
# a public name that resolves to a private address (DNS rebinding included);
# a private DNS suffix such as .corp or .lan; and, in a render, whatever the
# browser reaches on its own - a redirect or script navigation (plain http
# included) to a local service, whose DOM --dump-dom then returns, and the
# page's sub-resource requests.

set -u

PROSE_FETCHED_MIN=1500
SHELL_MIN_BYTES=20000
RENDER_TIMEOUT=120
CHECK_TIMEOUT=60
PROVENANCE_LINE='rendered with headless Chromium, not fetched'
# An offline page that writes the user agent: proves the headless render works
# and names the engine version without touching the network.
CHECK_URL='data:text/html,%3Cbody%3E%3Cscript%3Edocument.write(navigator.userAgent)%3C/script%3E%3C/body%3E'
LOOKED_FOR='ENSEMBLE_BROWSER, then chrome, msedge, chromium and chromium-browser at their standard install paths and on PATH; Brave only through ENSEMBLE_BROWSER'
MAX_REDIRECTS=5

usage() {
  echo "Usage: scout-fetch.sh [--render|--check] \"<https URL>\" <PATH under the session scratchpad>" >&2
  echo "       scout-fetch.sh --check" >&2
  exit 2
}

refuse() {
  echo "REFUSED: $1" >&2
  exit 2
}

# --- arguments ----------------------------------------------------------------
mode=raw
case "${1:-}" in
  --render) mode=render; shift ;;
  --check)  mode=check;  shift ;;
  -*)       usage ;;
esac
url="${1:-}"
path="${2:-}"
[ "$#" -le 2 ] || usage
if [ "$mode" = check ] && [ -z "$url" ] && [ -z "$path" ]; then
  : # bare --check (the deploy's probe)
else
  [ -n "$url" ] && [ -n "$path" ] || usage
fi

# --- URL check ------------------------------------------------------------------
# url_problem is kept byte-identical to hooks/guard-scout-bash.sh's; change
# both together. It returns 0 for an accepted URL, else sets url_reason and
# returns 1. https only; the same character set the guard accepts, matched
# byte-wise (LC_ALL=C, so nothing outside ASCII passes); no userinfo; no
# bracketed IPv6 literal; no percent-encoding in the host; the host, trailing
# dots dropped, has no empty label, has at least one dot, is not a local name,
# and is not a bare or shorthand numeric form (2130706433, 127.1, 0x7f.1 and
# octal octets all reach addresses a dotted-quad test would miss); a dotted
# quad passes only when it is public.
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
  url_problem "$1" || refuse "$url_reason; the kit reaches public sources only: $1"
}

# --- PATH check: the scratchpad root set ------------------------------------------
# The root set is the one hooks/guard-archivist-paths.sh builds for its
# scratchpad exemption, extended by the forms a Git Bash command naturally
# uses: the drive form /c/... and the mount form (Git Bash mounts the user's
# Temp at /tmp, so /tmp/claude there is the same folder). Kept identical to
# hooks/guard-scout-bash.sh's; change both together. Windows:
# $LOCALAPPDATA/Temp/claude, $TEMP/claude and $TMP/claude, each also in its
# long and 8.3 short form where cygpath resolves them, because one path may
# arrive in either form (a "~1" short segment or the long user name) and a
# single form would miss the other. POSIX, only when none of the three
# Windows variables is set: ${TMPDIR:-/tmp}/claude and
# ${TMPDIR:-/tmp}/claude-<digits>. Below the root every segment must match
# [A-Za-z0-9_-][A-Za-z0-9._-]*: no "..", no ".", no dotfiles, no empty
# segments. The kit sees no hook input, so it cannot narrow this set to the
# calling session's own scratchpad; the guard does, when the harness reports
# it, and the no-overwrite rule below holds either way.
norm_root() {
  printf '%s' "$1" | tr '\\' '/' | sed 's:/*$::'
}
lc() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}
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
scratch_roots=""
win_root=0
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
[ -n "${LOCALAPPDATA:-}" ] && { add_win_root "$(norm_root "$LOCALAPPDATA")/Temp/claude"; win_root=1; }
[ -n "${TEMP:-}" ] && { add_win_root "$(norm_root "$TEMP")/claude"; win_root=1; }
[ -n "${TMP:-}" ] && { add_win_root "$(norm_root "$TMP")/claude"; win_root=1; }
posix_tmp=""
if [ "$win_root" -eq 0 ]; then
  posix_tmp="$(norm_root "${TMPDIR:-/tmp}")"
  add_root "$posix_tmp/claude"
fi

# Prints the part of $1 below its scratchpad root; fails when $1 is under none.
below_scratch() {
  _t="$1"
  _tc="$_t"
  [ "$win_root" -eq 1 ] && _tc="$(lc "$_t")"
  _oldifs="$IFS"
  IFS='
'
  for _root in $scratch_roots; do
    [ -n "$_root" ] || continue
    _rc="$_root"
    [ "$win_root" -eq 1 ] && _rc="$(lc "$_root")"
    case "$_tc" in
      "$_rc"/*) IFS="$_oldifs"; printf '%s' "${_t:${#_root}+1}"; return 0 ;;
    esac
  done
  IFS="$_oldifs"
  if [ -n "$posix_tmp" ]; then
    case "$_t" in
      "$posix_tmp"/claude-*/*)
        _after="${_t#"$posix_tmp"/claude-}"
        _seg="${_after%%/*}"
        case "$_seg" in
          ''|*[!0-9]*) ;;
          *) printf '%s' "${_after#*/}"; return 0 ;;
        esac ;;
    esac
  fi
  return 1
}

check_path() {
  _p="$(printf '%s' "$1" | tr '\\' '/')"
  _rel="$(below_scratch "$_p")" \
    || refuse "the path is not under the session scratchpad: $1"
  [ -n "$_rel" ] || refuse "the path names the scratchpad root itself, not a file under it: $1"
  _oldifs="$IFS"; IFS=/
  set -f
  for _seg in $_rel; do
    printf '%s' "$_seg" | LC_ALL=C grep -Eq '^[A-Za-z0-9_-][A-Za-z0-9._-]*$' \
      || { set +f; IFS="$_oldifs"; refuse "the path has a segment the kit does not accept ('$_seg': empty, '..', a dotfile, or a character outside A-Z a-z 0-9 . _ -): $1"; }
  done
  set +f
  IFS="$_oldifs"
  case "$_p" in */) refuse "the path ends in a slash; name a file: $1" ;; esac
  path="$_p"
}

# --- no overwrite, no foreign delete ------------------------------------------------
# Every file or folder the kit writes is new: it refuses when one of the names
# a run would create already exists (a dangling link counts), creates each
# file exclusively (noclobber opens it O_EXCL), and removes on failure only
# what this run created.
exists() { [ -e "$1" ] || [ -L "$1" ]; }
refuse_existing() {
  for _n in "$@"; do
    exists "$_n" && refuse "$_n already exists; the kit never overwrites or removes a file it did not create in this run. Name a new PATH"
  done
  return 0
}
create_new() {
  ( set -C; : > "$1" ) 2>/dev/null || refuse "cannot create $1 as a new file (it appeared meanwhile, or the folder is not writable)"
}
make_new_dir() {
  mkdir "$1" 2>/dev/null || refuse "cannot create the folder $1 as a new folder"
}

# --- measures -------------------------------------------------------------------
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    echo "unavailable (no sha256sum or shasum)"
  fi
}
bytes_of() { wc -c < "$1" | tr -d ' '; }
lines_of() { wc -l < "$1" | tr -d ' '; }

is_html() {
  head -c 4096 "$1" | tr '[:upper:]' '[:lower:]' | grep -Eq '<!doctype html|<html|<head|<body'
}

# Prints "<prose characters> <script bytes>". Prose: the characters of the
# text outside tags, comments, script, style and noscript (a noscript notice is
# the shell speaking, not the page), each whitespace run counted as one space
# and the ends trimmed. Characters are UTF-8 code points, counted under
# LC_ALL=C by skipping continuation bytes, so the count does not depend on the
# locale. Portable awk: RS is one character.
prose_measure() {
  LC_ALL=C awk '
    function cnt(s,   n) {
      gsub(/[ \t\r\n\f\v]+/, " ", s)
      if (lastsp && substr(s, 1, 1) == " ") s = substr(s, 2)
      if (s == "") return 0
      lastsp = (substr(s, length(s), 1) == " ")
      gsub(/[\200-\277]/, "", s)
      return length(s)
    }
    BEGIN { RS = "<"; skip = ""; incom = 0; prose = 0; sbytes = 0; lastsp = 1 }
    NR == 1 { prose += cnt($0); next }
    {
      rec = $0
      if (incom) {
        i = index(rec, "-->")
        if (i == 0) next
        incom = 0
        prose += cnt(substr(rec, i + 3))
        next
      }
      if (skip != "") {
        head = tolower(substr(rec, 1, length(skip) + 2))
        if (head ~ ("^/" skip "([ \t\r\n>]|$)")) {
          skip = ""
          gt = index(rec, ">")
          if (gt) prose += cnt(substr(rec, gt + 1))
          next
        }
        if (skip == "script") sbytes += length(rec) + 1
        next
      }
      if (substr(rec, 1, 3) == "!--") {
        i = index(substr(rec, 4), "-->")
        if (i == 0) { incom = 1; next }
        prose += cnt(substr(rec, 4 + i + 2))
        next
      }
      gt = index(rec, ">")
      tag = (gt ? substr(rec, 1, gt - 1) : rec)
      txt = (gt ? substr(rec, gt + 1) : "")
      lt = tolower(tag)
      if (lt ~ /^(script|style|noscript)([ \t\r\n\/]|$)/ && lt !~ /\/$/) {
        match(lt, /^[a-z]+/)
        skip = substr(lt, 1, RLENGTH)
        if (skip == "script") sbytes += length(txt)
        next
      }
      prose += cnt(txt)
    }
    END { if (lastsp && prose > 0) prose--; print prose, sbytes }' "$1"
}

# Prints the report lines for one landed file; sets m_sha m_bytes m_lines
# m_prose m_script m_reading for the sidecar.
measure() {
  _f="$1"
  m_sha="$(sha256_of "$_f")"
  m_bytes="$(bytes_of "$_f")"
  m_lines="$(lines_of "$_f")"
  echo "SHA256: $m_sha"
  echo "BYTES: $m_bytes"
  echo "LINES: $m_lines"
  if is_html "$_f"; then
    set -- $(prose_measure "$_f")
    m_prose="$1"
    m_script="$2"
    echo "PROSE: $m_prose characters outside tags, comments, script, style and noscript"
    echo "SCRIPT BYTES: $m_script (text held inside script elements)"
    if [ "$m_prose" -ge "$PROSE_FETCHED_MIN" ]; then
      m_reading="fetched - the page's text is in this file"
    elif [ "$m_bytes" -ge "$SHELL_MIN_BYTES" ]; then
      m_reading="shell - a large file with almost no text outside script and style; run again with --render onto a new PATH, and keep this raw file (text held as script data is complete here, partial in a render)"
    else
      m_reading="terse - a small page with little text; what is here may be all there is"
    fi
  else
    m_prose="n/a (not HTML)"
    m_script="n/a (not HTML)"
    m_reading="raw file, not HTML - enumerate it directly"
    echo "PROSE: n/a (not HTML)"
  fi
}

# --- browser discovery ------------------------------------------------------------
winpath_to_unix() {
  case "$1" in
    [A-Za-z]:[\\/]*|[A-Za-z]:)
      if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1" | tr '\\' '/'; fi ;;
    *) printf '%s' "$1" ;;
  esac
}
env_dir() {
  _v="$(printenv "$1" 2>/dev/null || true)"
  [ -n "$_v" ] && winpath_to_unix "$_v"
}

browser=""
browser_version=""
browser_is_winexe=0
no_browser_reason=""

usable() { [ -n "$1" ] && [ -f "$1" ] && [ -x "$1" ]; }

find_browser() {
  if [ -n "${ENSEMBLE_BROWSER:-}" ]; then
    _c="$(winpath_to_unix "$ENSEMBLE_BROWSER")"
    if usable "$_c"; then browser="$_c"; return 0; fi
    no_browser_reason="ENSEMBLE_BROWSER is set to '$ENSEMBLE_BROWSER', which is not an executable file"
    return 1
  fi
  _pf="$(env_dir PROGRAMFILES)"
  _pf86="$(env_dir 'ProgramFiles(x86)')"
  _lad="$(env_dir LOCALAPPDATA)"
  _cands=""
  for _b in "$_pf" "$_pf86" "$_lad"; do
    [ -n "$_b" ] && _cands="$_cands
$_b/Google/Chrome/Application/chrome.exe"
  done
  for _b in "$_pf86" "$_pf" "$_lad"; do
    [ -n "$_b" ] && _cands="$_cands
$_b/Microsoft/Edge/Application/msedge.exe"
  done
  for _b in "$_lad" "$_pf" "$_pf86"; do
    [ -n "$_b" ] && _cands="$_cands
$_b/Chromium/Application/chrome.exe"
  done
  # Brave is not searched for (see the header); ENSEMBLE_BROWSER may name it.
  _cands="$_cands
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome
${HOME:-/nonexistent}/Applications/Google Chrome.app/Contents/MacOS/Google Chrome
/opt/google/chrome/chrome
/usr/bin/google-chrome-stable
/usr/bin/google-chrome
/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge
/opt/microsoft/msedge/msedge
/usr/bin/microsoft-edge-stable
/usr/bin/microsoft-edge
/Applications/Chromium.app/Contents/MacOS/Chromium
/usr/bin/chromium
/snap/bin/chromium
/usr/bin/chromium-browser"
  _oldifs="$IFS"
  IFS='
'
  for _c in $_cands; do
    if usable "$_c"; then IFS="$_oldifs"; browser="$_c"; return 0; fi
  done
  IFS="$_oldifs"
  for _n in google-chrome-stable google-chrome chrome msedge microsoft-edge-stable microsoft-edge chromium chromium-browser; do
    _c="$(command -v "$_n" 2>/dev/null || true)"
    if usable "$_c"; then browser="$_c"; return 0; fi
  done
  no_browser_reason="no Chromium-family browser found (looked for $LOOKED_FOR)"
  return 1
}

no_browser() {
  echo "NO BROWSER: $no_browser_reason; the Scout reports this gap"
  exit 3
}

# The version without launching the browser on Windows: a Windows build keeps
# its version as a sibling directory name of the executable, so reading that
# directory needs no browser process in the user's desktop session (what
# chrome.exe --version does there is not relied on); elsewhere --version.
detect_version() {
  case "$(lc "$browser")" in
    *.exe)
      if command -v cygpath >/dev/null 2>&1; then browser_is_winexe=1; fi
      browser_version="$(ls -1 "$(dirname "$browser")" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -n 1)"
      [ -n "$browser_version" ] && browser_version="$browser_version (install directory)"
      ;;
    *)
      browser_version="$("$browser" --version 2>/dev/null | head -n 1)"
      ;;
  esac
  [ -n "$browser_version" ] || browser_version="unknown"
}

# A native Windows browser needs a Windows path for its profile directory.
native_path() {
  if [ "$browser_is_winexe" -eq 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

# Runs "$@" for at most $1 seconds.
run_limited() {
  _secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_secs" "$@"; return $?
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$_secs" "$@"; return $?
  fi
  "$@" &
  _pid=$!
  ( sleep "$_secs"; kill "$_pid" 2>/dev/null ) &
  _wd=$!
  wait "$_pid"; _rc=$?
  kill "$_wd" 2>/dev/null
  return $_rc
}

# Removes a profile directory, retrying while the browser's children let go.
remove_dir() {
  for _i in 1 2 3 4 5; do
    rm -rf "$1" 2>/dev/null
    [ -e "$1" ] || return 0
    sleep 1
  done
  return 1
}

# --- modes ------------------------------------------------------------------------
if [ -n "$url" ]; then
  check_url "$url"
  check_path "$path"
  # Every name this run would create, refused up front when one exists.
  case "$mode" in
    check)  refuse_existing "$path.check-profile" ;;
    raw)    refuse_existing "$path" ;;
    render) refuse_existing "$path" "$path.rendered.html" "$path.provenance.txt" "$path.profile" ;;
  esac
fi

if [ "$mode" = check ]; then
  find_browser || no_browser
  detect_version
  if [ -n "$path" ]; then
    prof="$path.check-profile"
    mkdir -p "$(dirname "$prof")" || refuse "cannot create the folder for $prof"
    make_new_dir "$prof"
  else
    prof="$(mktemp -d "${TMPDIR:-/tmp}/scout-fetch-check.XXXXXX")" || { echo "CHECK FAILED: no temporary directory"; exit 4; }
  fi
  out="$(run_limited "$CHECK_TIMEOUT" "$browser" --headless=new --disable-gpu --no-first-run --no-default-browser-check "--user-data-dir=$(native_path "$prof")" --dump-dom "$CHECK_URL" 2>/dev/null)"
  rc=$?
  remove_dir "$prof" || echo "NOTE: the check profile directory could not be removed: $prof"
  echo "BROWSER: $browser"
  echo "VERSION: $browser_version"
  if [ -n "$out" ]; then
    ua="$(printf '%s' "$out" | grep -Eo '(Headless)?Chrome/[0-9.]+' | head -n 1)"
    echo "RENDER: ok (an offline page rendered headless; engine ${ua:-unreported})"
    exit 0
  fi
  echo "RENDER: FAILED - the browser ran and returned no DOM (exit $rc)"
  exit 4
fi

mkdir -p "$(dirname "$path")" || refuse "cannot create the folder for $path"

echo "URL: $url"
echo "FILE: $path"
echo "STATE: raw download (curl), not rendered"
not_rendered=""
[ "$mode" = render ] && not_rendered=', so nothing was rendered (a render never lands without the raw file beside it)'
create_new "$path"
# One request per hop, no -L: a redirect's target is checked before it is
# requested. Each hop rewrites only the file this run created.
cur="$url"
hops=0
while :; do
  : >| "$path"   # a body-less response must not leave the previous hop's bytes
  wo="$(curl -q -sS -f --proto =https --max-time 60 --max-filesize 20000000 \
        -w '%{http_code} %{redirect_url}' -o "$path" "$cur")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$path"
    echo "DOWNLOAD FAILED: curl exit $rc; nothing landed$not_rendered"
    exit 5
  fi
  code="${wo%% *}"
  next="${wo#* }"
  case "$code" in
    3??) [ -n "$next" ] || break ;;
    *)   break ;;
  esac
  hops=$((hops + 1))
  if [ "$hops" -gt "$MAX_REDIRECTS" ]; then
    rm -f "$path"
    echo "DOWNLOAD FAILED: more than $MAX_REDIRECTS redirects; nothing landed$not_rendered"
    exit 5
  fi
  if ! url_problem "$next"; then
    rm -f "$path"
    echo "REFUSED: $cur redirects to $next, which the kit does not request ($url_reason); nothing landed$not_rendered" >&2
    exit 2
  fi
  echo "REDIRECT: $code to $next (checked before it was requested)"
  cur="$next"
done
[ "$cur" = "$url" ] || echo "FINAL URL: $cur"
measure "$path"
raw_sha="$m_sha"; raw_bytes="$m_bytes"; raw_prose="$m_prose"; raw_script="$m_script"
echo "READING: $m_reading"

[ "$mode" = render ] || exit 0

# --- render -------------------------------------------------------------------------
echo ""
find_browser || no_browser
detect_version
rendered="$path.rendered.html"
sidecar="$path.provenance.txt"
prof="$path.profile"
make_new_dir "$prof"
create_new "$rendered"
flag_line="--headless=new --disable-gpu --no-first-run --no-default-browser-check --virtual-time-budget=10000 --user-data-dir=<PATH>.profile --dump-dom"
time_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# The render is of the URL the download ended at: its host passed the check.
run_limited "$RENDER_TIMEOUT" "$browser" --headless=new --disable-gpu --no-first-run --no-default-browser-check \
  --virtual-time-budget=10000 "--user-data-dir=$(native_path "$prof")" --dump-dom "$cur" \
  >| "$rendered" 2> "$prof/kit-browser-console.txt"
rc=$?
console_head="$(head -n 5 "$prof/kit-browser-console.txt" 2>/dev/null)"
if remove_dir "$prof"; then profile_state="removed"; else profile_state="NOT REMOVED ($prof)"; fi

if [ ! -s "$rendered" ]; then
  rm -f "$rendered"
  echo "RENDER FAILED: the browser returned no DOM (exit $rc; judged by the output file, which is empty)."
  [ -n "$console_head" ] && { echo "Browser console, for diagnosis only (never the verdict):"; printf '%s\n' "$console_head" | sed 's/^/  /'; }
  echo "PROFILE: $profile_state"
  echo "The raw file stays at $path. Report the gap; the Operator's browser is the escalation."
  exit 4
fi

echo "STATE: rendered with headless Chromium, not fetched"
echo "BROWSER: $browser"
echo "VERSION: $browser_version"
echo "RENDERED: $rendered"
measure "$rendered"
echo "PROFILE: $profile_state"
[ "$rc" -eq 0 ] || echo "NOTE: the browser exited $rc after writing the DOM; the file above is what it wrote."

create_new "$sidecar"
{
  echo "url: $url"
  echo "final-url: $cur"
  echo "time-utc: $time_utc"
  echo "browser: $browser"
  echo "browser-version: $browser_version"
  echo "flags: $flag_line"
  echo "browser-exit: $rc"
  echo "raw-file: $path"
  echo "raw-sha256: $raw_sha"
  echo "raw-bytes: $raw_bytes"
  echo "raw-prose-characters: $raw_prose"
  echo "raw-script-bytes: $raw_script"
  echo "rendered-file: $rendered"
  echo "rendered-sha256: $m_sha"
  echo "rendered-bytes: $m_bytes"
  echo "rendered-prose-characters: $m_prose"
  echo "rendered-script-bytes: $m_script"
  echo "profile-directory: $profile_state"
  echo "provenance: $PROVENANCE_LINE"
} >| "$sidecar"
echo "SIDECAR: $sidecar"
echo "PROVENANCE: $PROVENANCE_LINE"
exit 0
