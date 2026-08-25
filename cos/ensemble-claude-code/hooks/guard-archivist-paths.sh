#!/usr/bin/env bash
# provenance: pursuit claude-code-cos-realization (contracts/2026-07-07-claude-code-cos-realization/)
#   refined by pursuit guard-mediation-refinement (contracts/2026-07-19-guard-mediation-refinement/),
#   the user's word 2026-07-19: "Let's go with the trio" (R1+R2+R3).
# Ensemble (ensemble-claude-code) - PreToolUse path guard on Edit|Write.
#
# This guard now serves TWO wirings, selected by its first argument ($1):
#
#   archivist      (default) - full notebook-only scoping. Auto-approval covers
#                  own-root notebook surfaces ONLY; everything else (own-root
#                  non-notebook paths, and ALL foreign-root paths) downgrades to
#                  an explicit ask. Wired nowhere since 2026-08-25: the
#                  Archivist card's wiring was lifted on the human's word and its
#                  notebook-and-inbox-only boundary is doctrine on the card. Kept
#                  in the file, unwired; the default remains "archivist" so an
#                  argument-less call is strict-by-default, not silently permissive.
#
#   main-session   - foreign-root-only mode. The main session is the
#                  Concertmaster: its own-root notebook closure writes (Aim,
#                  Registry, Lanes, contract/charter surfaces) must stay
#                  frictionless, AND it legitimately edits non-notebook files in
#                  arbitrary projects. So this mode auto-passes EVERYTHING
#                  own-root and asks ONLY on a proven foreign-root write (a
#                  write outside the session's own root - e.g. into another
#                  lane's sibling worktree, or a stray foreign path). That
#                  delivers mechanical topology-face mediation (a lane session
#                  writing main's Lanes.md is foreign-root -> ask) with zero new
#                  friction on legitimate own-root work.
#
# Neither mode ever hard-blocks: the downgrade target is always "ask" - the
# human may still approve at the prompt. Footprint-verified at deploy.
#
# The two modes share one principle and fail toward their own default:
#   - archivist's default disposition is ASK (it whitelists notebook surfaces),
#     so when own/foreign cannot be PROVEN it falls to ask;
#   - main-session's default disposition is PASS (it blacklists only foreign
#     roots), so when foreign cannot be PROVEN it falls to pass - the friction
#     budget dominates: a main session must never be blanket-asked.

set -u

mode="${1:-archivist}"

input="$(cat 2>/dev/null || true)"
fp="$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$fp" ] || exit 0

# Subagent identity when the harness supplies it: PreToolUse input carries
# agent_id / agent_type for subagent calls, both absent in the main
# conversation. The documented way to scope a settings-level hook.
agent_type="$(printf '%s' "$input" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

# JSON escapes backslashes; collapse them, then normalize to forward slashes so
# Windows and POSIX paths match the same way.
norm="$(printf '%s' "$fp" | sed 's/\\\\/\\/g' | tr '\\' '/')"

# The session's own root: CLAUDE_PROJECT_DIR when set, else the session cwd from
# stdin. Normalized the same way, trailing slash stripped.
root="${CLAUDE_PROJECT_DIR:-}"
[ -n "$root" ] || root="$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
root="$(printf '%s' "$root" | sed 's/\\\\/\\/g' | tr '\\' '/')"
root="${root%/}"

# Lexically canonicalize an absolute forward-slash path: resolve "." and ".."
# segments as pure string operations (the target need not exist, so no realpath
# on it - Edit/Write targets may not be created yet). A leading drive ("C:") or
# root slash anchor is preserved; ".." never escapes above the anchor. This is
# what closes the ..-escape hole: an escaping path is reduced to its true
# location BEFORE the own-root and notebook tests run.
canonicalize() {
  _p="$1"
  case "$_p" in
    [A-Za-z]:/*) _anchor="${_p%%/*}"; _rest="${_p#"$_anchor"/}" ;;
    /*)          _anchor="";          _rest="${_p#/}" ;;
    *)           _anchor="";          _rest="$_p" ;;
  esac
  _out=""
  _oldifs="$IFS"
  _oldf="$-"
  set -f
  IFS='/'
  for _seg in $_rest; do
    case "$_seg" in
      ''|'.') : ;;
      '..')   _out="${_out%/*}" ;;
      *)      _out="$_out/$_seg" ;;
    esac
  done
  IFS="$_oldifs"
  case "$_oldf" in *f*) ;; *) set +f ;; esac
  printf '%s' "$_anchor$_out"
}

# Absolute vs relative. An absolute Windows drive path (C:/...) or POSIX/UNC
# path (/...) is judged against root as-is (after canonicalization); a relative
# path is resolved against root FIRST (it is written from the session's own
# cwd), then canonicalized. Relative no longer means "inherently own-root": a
# relative "../sibling/..." resolves and canonicalizes OUT of the root and
# grades foreign, exactly like its absolute twin.
case "$norm" in
  [A-Za-z]:/*|/*) is_abs=1 ;;
  *)              is_abs=0 ;;
esac

# The root, canonicalized the same lexical way so the prefix test compares like
# with like (the root exists, but pure-string canonicalization keeps the two
# sides consistent even if root itself carried a "." or "..").
root_canon=""
[ -n "$root" ] && root_canon="$(canonicalize "$root")"

# own_root: 1 own-root, 0 foreign-root, -1 undeterminable (absolute path but no
# root to judge against). canon holds the canonical target path when a root was
# available to resolve/judge against; it stays empty otherwise. The prefix match
# tests "$root_canon"/* - the trailing "/" means a SIBLING worktree
# (…/oscc-workbench-lanes/… vs root …/oscc-workbench) is correctly NOT captured
# as own-root, so the lane-worktree gotcha stays closed.
canon=""
if [ "$is_abs" -eq 0 ]; then
  if [ -n "$root_canon" ]; then
    canon="$(canonicalize "$root_canon/$norm")"
    case "$canon" in
      "$root_canon"/*) own_root=1 ;;
      *)               own_root=0 ;;
    esac
  else
    # Relative path with no determinable root: inherently own-root, unchanged.
    own_root=1
  fi
elif [ -n "$root_canon" ]; then
  canon="$(canonicalize "$norm")"
  case "$canon" in
    "$root_canon"/*) own_root=1 ;;
    *)               own_root=0 ;;
  esac
else
  # Absolute path with no root to judge against: undeterminable, unchanged.
  own_root=-1
fi

ask() {
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$1"}}
JSON
  exit 0
}

if [ "$mode" = "main-session" ]; then
  # Foreign-root-only: ask ONLY on a proven foreign-root write. Own-root
  # (own_root=1) and undeterminable (own_root=-1, fail to main's PASS default)
  # both pass untouched - the friction budget honored.
  # The Archivist writes the team's memory in any repo without asking (the
  # user's word, 2026-08-25); its notebook-and-inbox-only boundary is doctrine
  # on its card, not a prompt. Every other caller is unchanged.
  [ "$agent_type" = "archivist" ] && exit 0
  # The harness's own per-session scratchpad is never a topology surface or a
  # project tree; on the user's word 2026-08-25 writes there ask nobody. The
  # scratchpad root is derived from the environment so one script serves without a
  # host-specific pattern. A SET of candidate roots is built and the target is
  # exempt if it is under ANY of them as an anchored prefix, because a host can
  # advertise its scratchpad in a form the anchored LOCALAPPDATA root misses: on
  # this Windows host LOCALAPPDATA is long-form but TEMP/TMP and the harness's own
  # advertised scratchpad path are 8.3 short-form (a "~1" segment), so a
  # single long-form root would not match the real path and the write would ask.
  # Candidates, each normalized to forward slashes exactly as fp/cwd are (backslash
  # collapse then tr, trailing slash stripped): $LOCALAPPDATA/Temp/claude,
  # $TEMP/claude, $TMP/claude (only those that are set), and on POSIX
  # ${TMPDIR:-/tmp}/claude (appended only when NONE of the three Windows vars was
  # set, so a Windows host never exempts a literal /tmp/claude path). For each
  # Windows-derived root, when cygpath is
  # available, both the long ("cygpath -m -l") and short 8.3 ("cygpath -m -s")
  # forms are added too; cygpath is applied to the root's existing parent
  # (.../Temp) and /claude re-appended, since the /claude leaf need not exist yet,
  # and skipped silently when cygpath is absent. The POSIX default means a root
  # always exists, so the exemption never depends on a host-specific pattern. A
  # path carrying any ".." segment falls through to the own-root test first so a
  # ".../claude/../../elsewhere" escape cannot ride the exemption; a path matching
  # no candidate root also falls to the own-root test (it asks when foreign) -
  # fail toward asking, per the guard-hardening bound.
  norm_root() {
    printf '%s' "$1" | sed 's/\\\\/\\/g' | tr '\\' '/' | sed 's:/*$::'
  }
  scratch_roots=""
  add_win_root() {
    # $1: a normalized forward-slash Windows scratchpad root ending in /claude.
    _r="$1"
    scratch_roots="$scratch_roots
$_r"
    if command -v cygpath >/dev/null 2>&1; then
      _parent="${_r%/claude}"
      _l="$(cygpath -m -l "$_parent" 2>/dev/null)"
      [ -n "$_l" ] && scratch_roots="$scratch_roots
${_l%/}/claude"
      _s="$(cygpath -m -s "$_parent" 2>/dev/null)"
      [ -n "$_s" ] && scratch_roots="$scratch_roots
${_s%/}/claude"
    fi
  }
  win_root=0
  [ -n "${LOCALAPPDATA:-}" ] && { add_win_root "$(norm_root "$LOCALAPPDATA")/Temp/claude"; win_root=1; }
  [ -n "${TEMP:-}" ] && { add_win_root "$(norm_root "$TEMP")/claude"; win_root=1; }
  [ -n "${TMP:-}" ] && { add_win_root "$(norm_root "$TMP")/claude"; win_root=1; }
  # The POSIX root ${TMPDIR:-/tmp}/claude is a POSIX-host fallback: appended ONLY
  # when no Windows scratchpad root was derived (none of LOCALAPPDATA/TEMP/TMP
  # set). This is an environment test, not an OS test (no uname): on a Windows
  # host these vars are always set, so a literal "/tmp/claude/..." target is NOT
  # exempted there - it grades foreign and asks, matching the DISPOSITIONS prose
  # ("on POSIX"). An env test (rather than "case $(uname -s) in MINGW*|...") also
  # keeps the exemption correct when the env is cleared to simulate a POSIX host,
  # and adds no external-tool dependency.
  if [ "$win_root" -eq 0 ]; then
    scratch_roots="$scratch_roots
$(norm_root "${TMPDIR:-/tmp}")/claude"
  fi

  in_scratch=0
  case "$norm" in
    */../*|../*|*/..) : ;;
    *)
      _target="${canon:-$norm}"
      _oldifs="$IFS"
      IFS='
'
      for _root in $scratch_roots; do
        case "$_root" in '') continue ;; esac
        case "$_target" in
          "$_root"/*) in_scratch=1 ;;
        esac
      done
      IFS="$_oldifs"
      ;;
  esac
  [ "$in_scratch" -eq 1 ] && exit 0
  [ "$own_root" -eq 0 ] || exit 0
  ask "Main-session path guard: this write targets a path outside the session's own root (a foreign root - e.g. another lane's worktree, or a stray external path). Cross-root writes - including a lane session touching main's topology face - are not auto-accepted; the human may still approve explicitly."
fi

# archivist mode. Foreign-root or undeterminable (own_root != 1) -> ask (R1):
# a canonical path (absolute, or a relative one resolved against root) not
# provably under the session's own root downgrades regardless of basename,
# closing the old match-anywhere fallback hole (a foreign Gaps.md no longer
# auto-passes) and the ..-escape hole (a "../sibling" or "<root>/../sibling"
# path canonicalizes out and grades foreign).
[ "$own_root" -eq 1 ] || ask "Archivist path guard: this path is not under the session's own root. Cross-root notebook-named writes are not auto-accepted; the human may still approve explicitly."

# Path relative to the workspace root, computed from the CANONICAL path so the
# notebook test sees ".."-free segments: strip the canonical root prefix when a
# canonical path was formed; otherwise (no determinable root) fall back to the
# already-relative norm as-is.
if [ -n "$canon" ]; then
  rel="$canon"
  case "$canon" in
    "$root_canon"/*) rel="${canon#"$root_canon"/}" ;;
  esac
else
  rel="$norm"
fi

# Own-root notebook check. contracts/ and charters/ are notebook roots only
# directly under the workspace root; a body file merely sitting under a code dir
# named routes/, iterations/, contracts/, or charters/ (e.g. src/routes/x.ts)
# is NOT a notebook surface and falls to the ask below. The named face files are
# ANCHORED basenames: they pass only here, after own-root is proven above -
# never match-anywhere. Lanes.md (R2) is the topology face, a legitimate
# main-side closure surface: an own-root Lanes.md passes, a foreign-root one was
# already asked at the R1 gate above (the mediation).
is_notebook=0
case "$rel" in
  contracts/*|charters/*) is_notebook=1 ;;
  *)
    base="${rel##*/}"
    case "$base" in
      Handoff.md|Gaps.md|Aim.md|Registry.md|Constitution.md|Lanes.md|LITTER-FLAG.md) is_notebook=1 ;;
    esac
    ;;
esac

[ "$is_notebook" -eq 1 ] && exit 0

ask "Archivist path guard: this path does not look like a notebook surface. Body writes belong to the Builder; auto-acceptance is withheld, the human may still approve explicitly."
