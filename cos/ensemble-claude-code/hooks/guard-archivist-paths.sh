#!/usr/bin/env bash
# provenance: pursuit claude-code-cos-realization (contracts/2026-07-07-claude-code-cos-realization/)
#   refined by pursuit guard-mediation-refinement (contracts/2026-07-19-guard-mediation-refinement/),
#   the user's word 2026-07-19: "Let's go with the trio" (R1+R2+R3).
#   amended 2026-08-30 by pursuit session-scoped-guard-grants, the user's gate
#   word "land as recommended" (the Examiner's twenty-first-firing evaluation)
#   - the session grant check in the main-session block below.
#   FIT repairs 2026-08-30 (canonical-order minimality floor, hooks-dir
#   self-cover refusal, grant-line CR/whitespace trimming, set -f around the
#   segment-count loop) - closing the four findings the FIT read raised
#   against that same session grant check.
#   re-examination repairs 2026-08-30 (dual-form self-cover, bidirectional
#   containment, three-segment floor, header truth, set -f restore) -
#   closing the five residues the re-examination raised against that same
#   session grant check.
#   reworded 2026-08-30 at the thirteenth pre-release beat's findings
#   (HIGH-1 Branch B, the user's word "reword"; MED-1) - the drive-rooted
#   user-home path shape removed from both minimality-floor comment blocks
#   so the leak scanner's placeholder-path check passes; no claim changed.
#   amended 2026-08-30 by route grants-for-members (R2), the user's
#   correction "for this session alone - its dispatched members included" -
#   grant consumption opened to a session's dispatched members (each hand
#   meeting the granted tree under the rules already governing it); the
#   distinct self-widening ask (Rider A) added, since widening the grant
#   surface itself stays Concertmaster-only.
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
#
# Session-scoped grant mechanism (main-session mode only, amended 2026-08-30):
# a foreign-root ask this guard would otherwise raise can be pre-empted by a
# grant the Concertmaster itself wrote for the session - one absolute root per
# line in hooks/session-roots/<session_id>.txt, beside this script (located
# via the script's own directory, never $CLAUDE_CONFIG_DIR, so the grant
# travels with the guard). session_id is parsed from the same PreToolUse input
# as every other field here, validated (non-empty, [0-9A-Za-z-]+ only). A
# grant is consumed by the dispatching session AND its dispatched members
# alike (amended 2026-08-30, route grants-for-members - the user's
# correction "for this session alone - its dispatched members included"): a
# call carrying an agent_id meets the granted tree under the same rules
# governing any own-root write, no agent_id exclusion on the match itself.
# Widening the grant surface stays Concertmaster-only - a distinct ask
# (Rider A, below) fires instead when an agent_id-carrying hand's write
# targets the grant-file directory itself, catching the straightforward and
# case-varied (case-folded, MED-1) forms of that write. It does not catch a
# Bash-shaped write that never goes through the Edit|Write tool wiring this
# guard is invoked through - that bypass is unclosed, named in the route's
# recorded Gaps 2026-08-30-1. Each grant line is trimmed first
# (leading/trailing whitespace and a trailing CR, so a CRLF-terminated grant
# file still parses) then normalized and canonicalized FIRST - unlike the
# scratch_roots loop below, which normalizes its own candidate roots but
# canonicalizes only the target; a grant line gets the full canonicalize()
# treatment before the minimality floor is counted on that CANONICAL result,
# never the raw line: the root must resolve to at least three path segments
# below its anchor - the drive root, the users directory, and any whole
# user home are refused; the shallowest grantable root is a Projects-level
# folder immediately below a user home (three segments from the anchor),
# and a project folder nested one level inside that (four segments) is
# also accepted - so ".."/"." padding on the raw line buys nothing the
# canonicalization does not also collapse away, and a
# grant line can never widen to a whole drive, a whole top-level directory,
# or a whole user home. A canonical root that equals, contains, or is
# contained by this script's own hooks directory (the grant file's own home)
# is refused outright, checked in both directions so a grant landing INSIDE
# the hooks dir (e.g. <hooks>/session-roots) is caught the same as one
# covering it - and checked against both the long and short (Windows 8.3)
# canonical forms of the hooks directory, so a grant line phrased in either
# naming convention cannot evade the test the way a lexical prefix check
# alone could (the same dual-form treatment the scratchpad exemption above
# gives its own candidate roots, via cygpath -m -l / -m -s, degrading to the
# single plain form where cygpath is absent). This is the same
# no-self-widening principle Rider A checks below for the target side (a
# dispatched member's write landing in <hooks_dir>/session-roots), applied
# here to a grant LINE instead: a grant covering the hooks directory, or one
# landing inside it, would make every later write to a grant file in it
# silent. A line that fails any test, or
# that does not canonicalize to a recognized absolute anchor at all, is
# skipped, never treated as a match. The surviving canonical root is
# prefix-matched against the already-canonical target; a match sets
# own_root=1, the same verdict an own-root write earns.
# The grant file is written by the Concertmaster (via the Write tool, so the
# guard's own ask still carries the widening to the human the first time it is
# needed) and removed by the SessionEnd litter-flag hook; this script never
# creates the session-roots/ directory itself, and its absence is the
# ordinary case - tolerated the same as a missing grant file for one session.
# Whether --resume/--continue reuse a prior run's session id is undocumented
# (checked 2026-08-29 against the official hooks documentation, which is
# silent on it); both possible branches are benign here regardless: reuse
# after the grant file was already cleaned up just returns to the ordinary ask
# path, and reuse after a crash (file never cleaned) resumes that session's
# own prior grant, never a foreign session's.

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

# Case-fold a canonical path for a case-insensitive-filesystem comparison
# (Windows, default macOS): a byte-exact compare of two canonical paths
# still misses a flipped-case variant of the same real file or directory
# (MED-1, FIT read 2026-08-30 - the Rider A and grant-loop self-cover
# comparisons below were byte-exact before this repair). Used only to fold
# BOTH sides of a self-widening comparison immediately before it runs;
# canonical forms stored elsewhere (root_canon, canon, grant lines) stay
# case-preserving, since the own-root prefix match is not this guard's
# reported defect and folding it is out of scope here.
lc() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
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
  # both pass untouched - the friction budget honored. The Archivist's own
  # silent exit (agent_type = "archivist") sits further down, AFTER Rider A
  # (HIGH-1, FIT read 2026-08-30) - see the comment there for why.
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
  # $TEMP/claude, $TMP/claude (only those that are set), and on POSIX (only when
  # NONE of the three Windows vars was set, so a Windows host never exempts a
  # literal /tmp/claude path) two forms under ${TMPDIR:-/tmp}: the bare /claude
  # root added in the posix_tmp block below, and the per-uid /claude-<uid> form
  # matched in the case below. For each Windows-derived root, when cygpath is
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
  # The POSIX roots under ${TMPDIR:-/tmp} are a POSIX-host fallback: built ONLY
  # when no Windows scratchpad root was derived (none of LOCALAPPDATA/TEMP/TMP
  # set). This is an environment test, not an OS test (no uname): on a Windows
  # host these vars are always set, so a literal "/tmp/claude/..." target is NOT
  # exempted there - it grades foreign and asks, matching the DISPOSITIONS prose
  # ("on POSIX"). An env test (rather than "case $(uname -s) in MINGW*|...") also
  # keeps the exemption correct when the env is cleared to simulate a POSIX host,
  # and adds no external-tool dependency.
  #
  # Two POSIX forms live here. The bare ${TMPDIR:-/tmp}/claude root is added
  # below; the per-uid ${TMPDIR:-/tmp}/claude-<uid> form a Linux host advertises
  # (observed 2026-08-25 as /tmp/claude-1000 on the user's Linux host) is matched
  # in the case below as a claude-<digits> segment anchored to posix_tmp, the
  # normalized ${TMPDIR:-/tmp} base. A digits-only segment test, not claude-$(id -u):
  # id -u is the running session's uid, but the fixtures simulate a POSIX host where
  # it differs, and a real Linux host's uid is whatever it is - the segment test
  # matches the advertised form on any POSIX host without pinning one uid. The cost
  # is that it also exempts another uid's claude-<n> dir under the same tmp base, a
  # narrow widening still bounded by the tmp-base anchor and the ..-fall-through
  # below.
  posix_tmp=""
  if [ "$win_root" -eq 0 ]; then
    posix_tmp="$(norm_root "${TMPDIR:-/tmp}")"
    scratch_roots="$scratch_roots
$posix_tmp/claude"
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
      # POSIX per-uid form: a claude-<digits> dir directly under the tmp base
      # (posix_tmp is non-empty only on a POSIX host, win_root=0), so a Linux
      # /tmp/claude-<uid>/... scratchpad matches without pinning one uid. The
      # first segment after the base is taken and exempted only when non-empty
      # and all digits, so claude-1abc, claude-1000-attacker, claude-9_evil do
      # not ride the exemption (a case glob's [0-9]* would let them through).
      if [ -n "$posix_tmp" ]; then
        case "$_target" in
          "$posix_tmp"/claude-*/*)
            _seg="${_target#"$posix_tmp"/claude-}"
            _seg="${_seg%%/*}"
            case "$_seg" in
              ''|*[!0-9]*) ;;
              *) in_scratch=1 ;;
            esac
            ;;
        esac
      fi
      ;;
  esac
  [ "$in_scratch" -eq 1 ] && exit 0

  # session_id and agent_id are parsed unconditionally here (not gated on
  # own_root=0), because Rider A's self-widening ask below needs agent_id
  # regardless of own_root - it must hold even when the session's own root
  # happens to contain the hooks dir (own_root=1 would otherwise exit
  # silently at the gate that follows).
  session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  case "$session_id" in
    ''|*[!0-9A-Za-z-]*) session_id="" ;;
  esac
  agent_id="$(printf '%s' "$input" | sed -n 's/.*"agent_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

  # This guard's own hooks directory, canonicalized once in BOTH its long and
  # short (Windows 8.3, e.g. RUNNER~1) canonical forms - the same treatment
  # the scratchpad exemption above gives its own candidate roots (cygpath -m
  # -l / -m -s), reused here because a lexical-prefix self-cover test is
  # evadable by an 8.3-form path against a long-form $0, or the reverse
  # (observed live, both directions). Needed unconditionally (not only when a
  # grant file exists) by both the grant loop's self-cover test below and by
  # Rider A's self-widening-target test that follows it. Only computed when
  # dirname "$0" itself carries a recognized absolute anchor; otherwise both
  # forms stay empty and the checks that use them simply never match (fails
  # toward the pre-repair behavior, never toward a new hazard). cygpath is
  # applied directly to the hooks directory itself (unlike the scratchpad
  # block, which applies it to a not-yet-existing leaf's parent) since the
  # hooks directory always exists while this script is running from it;
  # where cygpath is absent, or a given form comes back empty, that variable
  # degrades to the single plain canonicalize() result, so the tests still
  # run, just without the second form.
  hooks_dir_raw="$(norm_root "$(dirname "$0")")"
  hooks_dir_canon_l=""
  hooks_dir_canon_s=""
  case "$hooks_dir_raw" in
    [A-Za-z]:/*|/*)
      if command -v cygpath >/dev/null 2>&1; then
        _hl="$(cygpath -m -l "$hooks_dir_raw" 2>/dev/null)"
        [ -n "$_hl" ] && hooks_dir_canon_l="$(canonicalize "$(norm_root "$_hl")")"
        _hs="$(cygpath -m -s "$hooks_dir_raw" 2>/dev/null)"
        [ -n "$_hs" ] && hooks_dir_canon_s="$(canonicalize "$(norm_root "$_hs")")"
      fi
      [ -n "$hooks_dir_canon_l" ] || hooks_dir_canon_l="$(canonicalize "$hooks_dir_raw")"
      [ -n "$hooks_dir_canon_s" ] || hooks_dir_canon_s="$hooks_dir_canon_l"
      ;;
    *)
      # LOW-2 (latent, currently unreachable): if dirname "$0" is not
      # absolute, both canonical forms stay empty and every check that
      # depends on them - the grant loop's self-cover refusal, Rider A's
      # self-widening-target test - simply never matches, same as when the
      # hooks directory cannot be resolved at all. Every settings.json
      # wiring invokes this script with an absolute path today, so this
      # branch does not fire in practice; named here so a future rewiring
      # that loses that guarantee does not silently reopen self-widening.
      ;;
  esac

  # Case-folded copies of both canonical hooks-directory forms, computed
  # once here and reused by both self-widening tests below (the grant
  # loop's self-cover refusal and Rider A) so a flipped-case path on a
  # case-insensitive filesystem is caught the same as a byte-exact one
  # (MED-1, FIT read 2026-08-30). Folding "" yields "", so these stay
  # harmlessly empty when the hooks directory could not be resolved above.
  hooks_dir_canon_l_lc="$(lc "$hooks_dir_canon_l")"
  hooks_dir_canon_s_lc="$(lc "$hooks_dir_canon_s")"

  # Session-scoped grant check: only a foreign-root verdict (own_root=0) has
  # anything to gain from a grant match - own-root and undeterminable
  # verdicts already pass below, untouched.
  if [ "$own_root" -eq 0 ]; then
    # A grant is consumed by the dispatching session AND its dispatched
    # members alike - a member's hand meets the granted tree under the same
    # rules governing any own-root write, no agent_id exclusion on the match
    # itself (amended 2026-08-30, route grants-for-members, the user's
    # correction). Widening the grant surface stays Concertmaster-only,
    # guarded separately by Rider A below - never by excluding
    # agent_id-carrying calls from consuming a grant here.
    if [ -n "$session_id" ]; then
      grant_file="$(dirname "$0")/session-roots/$session_id.txt"
      if [ -f "$grant_file" ]; then
        while IFS= read -r _line || [ -n "$_line" ]; do
          # Trim a trailing CR (CRLF-terminated grant files) and leading/
          # trailing whitespace before any other check.
          _line="$(printf '%s' "$_line" | sed 's/\r$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
          case "$_line" in
            ''|'#'*) continue ;;
          esac
          _gr="$(norm_root "$_line")"
          case "$_gr" in
            [A-Za-z]:/*|/*) : ;;
            *)               continue ;;
          esac
          # Canonicalize FIRST, then hold the CANONICAL result to the
          # minimality floor - a raw "../.." padded line buys nothing the
          # canonicalization does not also discard before the count runs.
          _gr_canon="$(canonicalize "$_gr")"
          case "$_gr_canon" in
            [A-Za-z]:/*) _gcanon_anchor="${_gr_canon%%/*}"; _gcanon_rest="${_gr_canon#"$_gcanon_anchor"/}" ;;
            /*)          _gcanon_rest="${_gr_canon#/}" ;;
            *)           continue ;;
          esac
          # Minimality floor: refuse a canonical root fewer than three
          # segments below its anchor - the drive root, the users directory,
          # and any whole user home are refused; a Projects-level folder
          # immediately below a user home (three segments) is the shallowest
          # grantable root, a project folder nested one level inside that
          # (four segments) also kept -
          # Concertmaster's announced ruling raising the floor from two
          # segments (which accepted a whole user home) to three, so a grant
          # line can never widen to a whole drive, a whole top-level dir, or
          # a whole user home, regardless of how it was padded on the raw
          # line.
          _seg_count=0
          _oldifs2="$IFS"
          _oldf2="$-"
          set -f
          IFS='/'
          for _gseg in $_gcanon_rest; do
            case "$_gseg" in '') continue ;; esac
            _seg_count=$((_seg_count + 1))
          done
          IFS="$_oldifs2"
          case "$_oldf2" in *f*) ;; *) set +f ;; esac
          [ "$_seg_count" -ge 3 ] || continue
          # No-self-widening: a canonical root that equals, contains, or is
          # contained by this script's own hooks directory is refused - both
          # directions (a grant covering the hooks dir, or landing inside it,
          # e.g. <hooks>/session-roots), tested against both the long and
          # short (8.3) canonical forms of the hooks directory computed
          # above, so a grant line phrased in either naming convention is
          # caught. Same principle as Rider A's self-widening-target check
          # below. Both sides are case-folded before the compare (MED-1, FIT
          # read 2026-08-30) - a byte-exact compare on a case-insensitive
          # filesystem (Windows, default macOS) misses a flipped-case grant
          # line that still names the same real hooks directory.
          _self_cover=0
          _gr_canon_lc="$(lc "$_gr_canon")"
          case "$hooks_dir_canon_l_lc" in
            "$_gr_canon_lc"|"$_gr_canon_lc"/*) _self_cover=1 ;;
          esac
          case "$_gr_canon_lc" in
            "$hooks_dir_canon_l_lc"|"$hooks_dir_canon_l_lc"/*) _self_cover=1 ;;
          esac
          if [ "$hooks_dir_canon_s" != "$hooks_dir_canon_l" ]; then
            case "$hooks_dir_canon_s_lc" in
              "$_gr_canon_lc"|"$_gr_canon_lc"/*) _self_cover=1 ;;
            esac
            case "$_gr_canon_lc" in
              "$hooks_dir_canon_s_lc"|"$hooks_dir_canon_s_lc"/*) _self_cover=1 ;;
            esac
          fi
          [ "$_self_cover" -eq 1 ] && continue
          # own_root=0 here guarantees canon is non-empty (a root was already
          # available to judge the target against), so no separate
          # ".."-escape guard is needed on this side of the match.
          case "$canon" in
            "$_gr_canon"/*) own_root=1 ;;
          esac
          [ "$own_root" -eq 1 ] && break
        done < "$grant_file"
      fi
    fi
  fi

  # Rider A - the distinct self-widening ask: a dispatched member (agent_id
  # non-empty) writing to, or into, the grant-file directory itself
  # (<hooks_dir>/session-roots) is attempted self-widening of the grant
  # mechanism, not an ordinary foreign-root write - checked here, BEFORE the
  # own-root gate below, so it holds even when own_root=1 (the session's own
  # root happens to contain the hooks dir). Tested against both the long and
  # short (8.3) canonical forms of the hooks directory computed above, same
  # reasoning as the grant loop's self-cover test, and case-folded on both
  # sides before the compare (MED-1, FIT read 2026-08-30) so a flipped-case
  # path on a case-insensitive filesystem is caught the same as a byte-exact
  # one. An ask, never a deny - the "neither mode ever hard-blocks" invariant
  # holds here too; the Concertmaster's own hand (no agent_id) is untouched by
  # this check and keeps the ordinary once-per-root foreign-root ask below.
  # This catches the straightforward and case-varied forms of a self-widening
  # write; it does not catch a Bash-shaped write that bypasses the Edit|Write
  # tool wiring this guard is invoked through entirely - unclosed, named in
  # the route's recorded Gaps 2026-08-30-1.
  if [ -n "$agent_id" ]; then
    _sw_target_lc="$(lc "${canon:-$norm}")"
    _sw_hit=0
    if [ -n "$hooks_dir_canon_l" ]; then
      _sw_root_lc="$hooks_dir_canon_l_lc/session-roots"
      case "$_sw_target_lc" in
        "$_sw_root_lc"|"$_sw_root_lc"/*) _sw_hit=1 ;;
      esac
    fi
    if [ "$_sw_hit" -eq 0 ] && [ -n "$hooks_dir_canon_s" ]; then
      _sw_root_lc="$hooks_dir_canon_s_lc/session-roots"
      case "$_sw_target_lc" in
        "$_sw_root_lc"|"$_sw_root_lc"/*) _sw_hit=1 ;;
      esac
    fi
    [ "$_sw_hit" -eq 1 ] && ask "Main-session path guard: this write targets the session-grant directory itself, from a dispatched member (agent_id present). A member may consume a grant the Concertmaster wrote, never widen or overwrite the grant mechanism itself - attempted self-widening, distinct from an ordinary foreign-root write. Not auto-accepted; the human may still approve explicitly."
  fi

  # The Archivist writes the team's memory in any repo without asking (the
  # user's word, 2026-08-25); its notebook-and-inbox-only boundary is doctrine
  # on its card, not a prompt. This exit sits HERE - after Rider A, not at the
  # top of main-session mode - so a dispatched Archivist targeting the
  # grant-file directory itself (<hooks_dir>/session-roots) still meets
  # Rider A's distinct self-widening ask instead of passing silently (HIGH-1,
  # FIT read 2026-08-30: the early exit previously sat before Rider A and
  # swallowed that case). Every other archivist write reaches this same
  # silent exit unchanged - the disposition change is scoped to session-roots
  # targets only.
  [ "$agent_type" = "archivist" ] && exit 0

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
