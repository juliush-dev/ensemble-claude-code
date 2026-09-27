#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - PreToolUse nudge on Bash|PowerShell.
# An agent's first shell-boundary crossing gets one note beside the tool result:
# on Git Bash the host's two traps, everywhere the cross-shell-command-discipline
# pointer. Once per agent: an empty marker <session_id>.<agent_id, or main> in
# ${TMPDIR:-/tmp}/ensemble-cross-shell-nudge/, removed at SessionEnd by
# session-end-litter-flag.sh. A crossing is a nested interpreter (wsl, bash/sh
# -c, powershell/pwsh, cmd /c, ssh, docker exec|run), or python/py/node in a
# Bash call on Git Bash, where they are Windows programs; quoted text and
# which/type/command -v/where lookups are dropped first. Never denies or asks:
# exit 0 always, no stderr, no note when the marker cannot be written. Bash
# builtins only (one mkdir per session), ASCII, LF.

set -u
exec 2>/dev/null
trap 'exit 0' EXIT
IFS= read -r -d '' in || true
re='"session_id"[[:space:]]*:[[:space:]]*"([0-9A-Za-z-]+)"'
[[ $in =~ $re ]] || exit 0
sid=${BASH_REMATCH[1]} who=main h=''
re='"agent_id"[[:space:]]*:[[:space:]]*"([0-9A-Za-z_-]+)"'
[[ $in =~ $re ]] && who=${BASH_REMATCH[1]}
dir=${TMPDIR:-/tmp}/ensemble-cross-shell-nudge
[ -e "$dir/$sid.$who" ] && exit 0
re='"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
[[ $in =~ $re ]] || exit 0
c=${BASH_REMATCH[1]//\\n/ }; c=${c//\\\"/\"}
for w in 'which ' 'type ' 'command -v ' 'where ' 'where.exe '; do c=${c//"$w"/_}; done
strip() { local IFS=$1 i o='' p; set -f; p=($c); set +f; for ((i=0; i<${#p[@]}; i+=2)); do o+=" ${p[i]}"; done; c=$o; }
strip '"'; strip "'"
shopt -s nocasematch; p='(^|[[:space:];&|(`])'
n="$p(wsl(\.exe)?([[:space:]]|$)|(ba|z|da)?sh(\.exe)?[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*-[[:alnum:]]*c([^[:alnum:]_]|$)|(powershell|pwsh)(\.exe)?([^[:alnum:]_]|$)|cmd(\.exe)?[[:space:]]+//?[ck]([^[:alnum:]_]|$)|ssh[[:space:]]|docker(\.exe)?[[:space:]]+(exec|run)([^[:alnum:]_]|$))"
case $OSTYPE in msys*|cygwin*)
  h=' Host traps: the Bash tool halves backslash pairs, in heredocs too, so write backslash-bearing files with the Write tool; Windows Python cannot open /c/... paths, so give it C:/... paths.'
  [[ $in =~ '"tool_name"'[[:space:]]*:[[:space:]]*'"Bash"' ]] && n="$n|$p(python3?|py|node)(\.exe)?[[:space:]]" ;;
esac
[[ $c =~ $n ]] || exit 0
[ -d "$dir" ] || mkdir -p "$dir" || exit 0
set -C; : > "$dir/$sid.$who" || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[cross-shell-nudge] First shell-boundary crossing for this agent.%s Load cross-shell-command-discipline before the next nontrivial crossing."}}\n' "$h"
