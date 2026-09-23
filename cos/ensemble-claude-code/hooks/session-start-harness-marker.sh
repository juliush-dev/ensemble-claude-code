#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - SessionStart harness-version marker.
#
# Compares the installed Claude Code version with the version this COS was
# last weighed against, line 1 of the home's HARNESS.md ("weighed: X.Y.Z").
# SessionStart adds plain-text stdout to the session's context, so one line
# here is one line the session sees.
#
#   equal, or either version unknown   -> silent
#   installed OLDER than weighed        -> one line in any project: update
#   installed NEWER than weighed        -> one line only where the cwd
#                                          carries
#                                          charters/harness-evolution/charter.md,
#                                          the charter of the tending that
#                                          weighs each new version; silent
#                                          everywhere else
#
# Wired with no matcher, so it runs on every session start (startup, resume,
# clear, compact, fork), with a short per-hook timeout in settings.json so a
# hung `claude --version` cannot hold a session start. Never blocks: exit 0 on
# every path, nothing on stderr. The one external command is
# `claude --version`; everything else is a bash builtin, because each process
# a hook starts costs tens of milliseconds under Git Bash on every session
# start. ASCII only, LF endings.

set -u
exec 2>/dev/null

IFS= read -r -d '' input || true

# The home is the hook folder's parent.
hookdir="${0%/*}"
[ "$hookdir" = "$0" ] && hookdir="${0%\\*}"
[ "$hookdir" = "$0" ] && hookdir="."
harness="$hookdir/../HARNESS.md"
[ -f "$harness" ] || exit 0

# Weighed version: line 1 of HARNESS.md, CR tolerated.
first=""
IFS= read -r first < "$harness" || [ -n "$first" ] || exit 0
first="${first%$'\r'}"
[[ "$first" =~ ^weighed:[[:space:]]*([0-9]+(\.[0-9]+)*)[[:space:]]*$ ]] || exit 0
weighed="${BASH_REMATCH[1]}"

# Installed version: the first dotted number `claude --version` prints.
command -v claude >/dev/null || exit 0
ver_out="$(claude --version)" || exit 0
[[ "$ver_out" =~ ([0-9]+(\.[0-9]+)+) ]] || exit 0
installed="${BASH_REMATCH[1]}"

[ "$installed" = "$weighed" ] && exit 0

# version_lt A B: true when A sorts before B, field by field, numerically
# (the order sort -V gives dotted numbers; a missing field counts as 0).
version_lt() {
  local IFS=.
  local -a a=($1) b=($2)
  local i x y n=${#a[@]}
  [ ${#b[@]} -gt "$n" ] && n=${#b[@]}
  for ((i = 0; i < n; i++)); do
    x=$((10#${a[i]:-0}))
    y=$((10#${b[i]:-0}))
    [ "$x" -lt "$y" ] && return 0
    [ "$x" -gt "$y" ] && return 1
  done
  return 1
}

if version_lt "$installed" "$weighed"; then
  echo "[harness-marker] Claude Code $installed is installed; this COS was weighed against $weighed and expects the latest. Update Claude Code. Older versions weaken the guards named in HARNESS.md in this COS home."
  exit 0
fi
version_lt "$weighed" "$installed" || exit 0

# Installed is newer: speak only where the tending that weighs it lives.
# The cwd comes from the hook's stdin JSON; JSON escapes backslashes, so they
# are collapsed for Windows paths to resolve.
cwd=""
re='"cwd"[[:space:]]*:[[:space:]]*"([^"]*)"'
[[ "$input" =~ $re ]] && cwd="${BASH_REMATCH[1]}"
cwd="${cwd//\\\\/\\}"
[ -n "$cwd" ] && [ -f "$cwd/charters/harness-evolution/charter.md" ] || exit 0

echo "[harness-marker] Claude Code $installed is installed; this COS was last weighed against $weighed (HARNESS.md in this COS home). The harness-evolution beat is owed. Run it before COS work that might build by hand what the new version offers."
exit 0
