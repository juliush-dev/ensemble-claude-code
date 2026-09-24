#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - SessionStart cue for the main session.
#
# Names the runbook the session's first moments call for, so the load does not
# rest on the session recognizing the moment by itself. SessionStart adds
# plain-text stdout to the session's context; one line here is one line the
# session sees. It speaks to the main session only: input that carries an
# agent_id comes from inside a subagent, and there it prints nothing, so a
# member never reads the main session's cue.
#
# It walks up from the session's cwd, the cwd first, and stops at the first
# directory that answers:
#
#   a project face (notebook/Constitution.md, or a root Constitution.md)
#                              -> "Wrapped project: load onboard ..."
#   the shared external brain  -> no face line; the brain is the one place
#                                 work may happen unwrapped
#   neither, up to the root    -> "No face here: ask the human ..."
#
# and always adds the decision-proposal-discipline line.
#
# The brain is recognized by its root manifesto note, the file whose name
# starts "Shared Long-Term Memory" and ends "Purpose.md", matched by a glob so
# this file stays ASCII. It is a marker in the brain's own tree, never a machine
# path. A brain without that note reads as a place with no face.
#
# Wired on matcher startup|resume|clear|fork in settings.json, beside the
# harness marker and the compaction marker, which keeps compact; SessionStart
# hooks run in parallel, so it adds no wait to theirs. Never blocks: exit 0 on every path, nothing on stderr, and
# any failure before the output prints nothing. Bash builtins only, because
# each process a hook starts costs tens of milliseconds under Git Bash on
# every session start. ASCII only, LF endings.

set -u
exec 2>/dev/null

IFS= read -r -d '' input || true

re='"agent_id"[[:space:]]*:'
[[ "$input" =~ $re ]] && exit 0

# The cwd comes from the hook's stdin JSON; JSON escapes backslashes, so they
# are collapsed, then turned to forward slashes so one parent walk serves
# Windows, UNC and POSIX paths alike.
cwd=""
re='"cwd"[[:space:]]*:[[:space:]]*"([^"]*)"'
[[ "$input" =~ $re ]] && cwd="${BASH_REMATCH[1]}"
cwd="${cwd//\\\\/\\}"
cwd="${cwd//\\//}"
[ -n "$cwd" ] || exit 0
while [ "${#cwd}" -gt 1 ] && [ "${cwd%/}" != "$cwd" ]; do cwd="${cwd%/}"; done

place="none"
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
exit 0
