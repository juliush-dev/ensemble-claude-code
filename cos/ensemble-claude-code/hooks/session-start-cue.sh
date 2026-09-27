#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - SessionStart cue for the main session.
#
# Names the runbook the session's first moments call for, so the load does not
# rest on the session recognizing the moment by itself, and carries the
# main-session rules when the launcher did not. SessionStart adds plain-text
# stdout to the session's context; one line here is one line the session sees.
# SessionStart fires in the main session only (a member gets SubagentStart),
# and input that carries an agent_id prints nothing besides, which also covers
# a whole session started as an agent (claude --agent).
#
# Two parts, both on startup, resume, clear and fork; on compact only the
# second, read from the input's "source" field:
#
# 1. The cue. It walks up from the session's cwd, the cwd first, and stops at
#    the first directory that answers:
#
#      a project face (notebook/Constitution.md, or a root Constitution.md)
#                                 -> "Wrapped project: load onboard ..."
#      the shared external brain  -> no face line; the brain is the one place
#                                    work may happen unwrapped
#      neither, up to the root    -> "No face here: ask the human ..."
#
#    and always adds the decision-proposal-discipline line. It needs the cwd;
#    without one it prints nothing.
#
#    The brain is recognized by its root manifesto note, the file whose name
#    starts "Shared Long-Term Memory" and ends "Purpose.md", matched by a glob
#    so this file stays ASCII. It is a marker in the brain's own tree, never a
#    machine path. A brain without that note reads as a place with no face.
#
# 2. The fallback. The launcher appends the home's CONCERTMASTER.md (the
#    Concertmaster's own rules) to the main session's system prompt and sets
#    ENSEMBLE_CONCERTMASTER_APPENDED=1 for the session. When that marker is
#    absent (a session started without the launcher), this prints one header
#    line and then the file, so the main session still holds its rules; on
#    compact it prints them again, because hook-added text does not survive the
#    summary. The file is found in the hook folder's parent, the home. Hook
#    stdout is capped at 10,000 characters (above it the model sees a
#    2,000-character preview), so fixtures/session-cue/run-fixture.sh
#    keeps the longest print under a 9,000-character limit. A claude started
#    from inside a launched session inherits the marker without the flag and
#    gets no fallback; the probe (probe-context.ps1) passes the flag itself.
#
# Wired on matcher startup|resume|clear|compact|fork in settings.json, beside
# the harness marker and the compaction marker; SessionStart hooks run in
# parallel, so it adds no wait to theirs. Never blocks: exit 0 on every path,
# nothing on stderr, and any failure before the output prints nothing. Bash
# builtins only, because each process a hook starts costs tens of milliseconds
# under Git Bash on every session start. ASCII only, LF endings.

set -u
exec 2>/dev/null

IFS= read -r -d '' input || true

re='"agent_id"[[:space:]]*:'
[[ "$input" =~ $re ]] && exit 0

event=""
re='"source"[[:space:]]*:[[:space:]]*"([^"]*)"'
[[ "$input" =~ $re ]] && event="${BASH_REMATCH[1]}"

# The home is the hook folder's parent.
hookdir="${0%/*}"
[ "$hookdir" = "$0" ] && hookdir="${0%\\*}"
[ "$hookdir" = "$0" ] && hookdir="."
rules="$hookdir/../CONCERTMASTER.md"

cue() {
  # The cwd comes from the hook's stdin JSON; JSON escapes backslashes, so they
  # are collapsed, then turned to forward slashes so one parent walk serves
  # Windows, UNC and POSIX paths alike.
  local cwd="" place="none" d p
  re='"cwd"[[:space:]]*:[[:space:]]*"([^"]*)"'
  [[ "$input" =~ $re ]] && cwd="${BASH_REMATCH[1]}"
  cwd="${cwd//\\\\/\\}"
  cwd="${cwd//\\//}"
  [ -n "$cwd" ] || return 0
  while [ "${#cwd}" -gt 1 ] && [ "${cwd%/}" != "$cwd" ]; do cwd="${cwd%/}"; done

  d="$cwd"
  while :; do
    if [ -f "$d/notebook/Constitution.md" ] || [ -f "$d/Constitution.md" ]; then
      place="face"; break
    fi
    if compgen -G "$d/Shared Long-Term Memory*Purpose.md" >/dev/null; then
      place="brain"; break
    fi
    p="${d%/*}"
    [ "$p" = "$d" ] && break
    d="$p"
  done

  case "$place" in
    face) echo "[session-cue] Wrapped project: load onboard before working." ;;
    none) echo "[session-cue] No face here: ask the human before working (wrap offer)." ;;
  esac
  echo "[session-cue] Load decision-proposal-discipline before the first ask."
}

fallback() {
  local line
  [ -n "${ENSEMBLE_CONCERTMASTER_APPENDED:-}" ] && return 0
  [ -f "$rules" ] && [ -r "$rules" ] || return 0
  echo "[session-cue] This session was not launched with the main-session rules appended; they follow in full."
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "${line%$'\r'}"
  done < "$rules"
}

[ "$event" = "compact" ] || cue
fallback
exit 0
