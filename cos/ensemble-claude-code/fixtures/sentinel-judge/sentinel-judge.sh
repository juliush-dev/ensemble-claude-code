#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - the sentinel judge, written as a Stop
# command hook and NOT WIRED. It lives in fixtures/, which the deploy scripts
# never copy (they take hooks/*.sh and tools/*.sh), no settings.json item runs
# it, and settings-shipped.txt does not list hooks.Stop. Its job is offline
# measurement. Wiring it, if it passes, is a git mv of this file and
# judge-prompt.txt into hooks/, both deploy scripts taught to copy the prompt
# file (they copy hooks/*.sh only), one hooks.Stop command item in
# settings.json, and the hooks.Stop line in settings-shipped.txt.
#
# Why a command hook and not a prompt hook: on Claude Code 2.1.283 a prompt
# hook on Stop reaches its model wrapped as a stopping condition, with
# thinking off and the whole conversation transcript attached, cut to half
# the model's window (read in the binary; the transcript size and thinking off
# then measured on the hook path). A command hook chooses what it sends.
#
# As the hook would run: it reads the Stop hook input JSON on stdin and takes
# only last_assistant_message. stop_hook_active true passes at once, with no
# model call. Otherwise the message alone, re-wrapped as
# {"last_assistant_message": ...}, goes to Haiku through a nested claude -p,
# with judge-prompt.txt (beside this file) as the whole system prompt. The
# model replies PASS, or FAIL with one line per failing check. On PASS the
# script prints nothing. On FAIL it prints the Stop hook's
# hookSpecificOutput.additionalContext form. The hooks reference says that
# form continues the conversation (a continuation turn, labeled Stop hook
# feedback, under the same stop_hook_active and 8-continuation cap as
# decision block). Run under "async": true, the same output would instead
# reach Claude on the next turn with no continuation.
#
# The nested call runs outside Claude Code's Stop-hook stopping-condition
# wrapper and without the conversation transcript: claude -p --safe-mode
# (hooks, CLAUDE.md, skills and MCP off, so the judge cannot fire itself),
# --setting-sources "" and --tools "", --no-session-persistence (no transcript
# lands in the config home's projects/), the nested-session variables unset,
# and SENTINEL_JUDGE_NESTED=1 as a second recursion stop. It signs in with the
# session's own login (the subscription); it never reads an API key.
#
# Settings, from the environment:
#   SENTINEL_JUDGE_THINKING  off | low (a 1024-token budget, the default) |
#                            default (Claude Code's own for the model) | <N>
#                            (a budget of N tokens). Sets MAX_THINKING_TOKENS.
#   SENTINEL_JUDGE_MODEL     default claude-haiku-4-5-20251001
#   SENTINEL_JUDGE_TIMEOUT   seconds for the model call, default 60
#   SENTINEL_JUDGE_CLAUDE    the claude executable, default claude on PATH
#   SENTINEL_JUDGE_TRACE     a file path; when set, the raw claude -p JSON
#                            result is written there (stderr to <path>.err)
#
# Fails open: no input, no message, an unknown setting, a missing prompt file,
# a timeout, an error result or a reply that is neither PASS nor FAIL prints
# nothing and exits 0, so the answer stands. Exit 0 on every path, nothing on
# stderr. Bash builtins apart from the claude call and timeout. ASCII, LF.

set -u
exec 2>/dev/null
trap 'exit 0' EXIT

[ -n "${SENTINEL_JUDGE_NESTED:-}" ] && exit 0
IFS= read -r -d '' in || true
[[ $in =~ '"stop_hook_active"'[[:space:]]*:[[:space:]]*true ]] && exit 0
re='"last_assistant_message"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
[[ $in =~ $re ]] || exit 0
msg=${BASH_REMATCH[1]}
[ -n "$msg" ] || exit 0

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
prompt=$here/judge-prompt.txt
[ -f "$prompt" ] || exit 0

case ${SENTINEL_JUDGE_THINKING:-low} in
  off) mt=0 ;;
  low) mt=1024 ;;
  default) mt='' ;;
  ''|*[!0-9]*) exit 0 ;;
  *) mt=${SENTINEL_JUDGE_THINKING} ;;
esac
model=${SENTINEL_JUDGE_MODEL:-claude-haiku-4-5-20251001}
to=${SENTINEL_JUDGE_TIMEOUT:-60}
[[ $to =~ ^[0-9]+$ ]] || exit 0
cl=${SENTINEL_JUDGE_CLAUDE:-claude}
trace=${SENTINEL_JUDGE_TRACE:-}

out=$(
  unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID \
    CLAUDE_CODE_CHILD_SESSION CLAUDE_PID CLAUDE_EFFORT CLAUDE_CODE_EFFORT_LEVEL \
    CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN \
    CLAUDE_CODE_BRIDGE_SESSION_ID CLAUDE_CODE_SESSION_ATTENDED \
    CLAUDE_CODE_SSE_PORT CLAUDE_CODE_EXECPATH MAX_THINKING_TOKENS
  export SENTINEL_JUDGE_NESTED=1
  [ -n "$mt" ] && export MAX_THINKING_TOKENS=$mt
  cd "${TMPDIR:-/tmp}" || exit 1
  err=/dev/null
  [ -n "$trace" ] && err=$trace.err
  printf '{"last_assistant_message": "%s"}\n' "$msg" |
    timeout "$to" "$cl" -p --model "$model" --system-prompt-file "$prompt" \
      --setting-sources "" --tools "" --safe-mode --no-session-persistence \
      --output-format json 2>"$err"
) || exit 0
[ -n "$trace" ] && printf '%s\n' "$out" > "$trace"

[[ $out =~ '"is_error"'[[:space:]]*:[[:space:]]*false ]] || exit 0
re='"result"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
[[ $out =~ $re ]] || exit 0
r=${BASH_REMATCH[1]}
# The reply is still JSON-escaped here, so it drops into the output as is.
[[ $r =~ ^([[:space:]]|\\n)*FAIL ]] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"[sentinel-judge] %s\\n\\nRevise the answer to meet the check. If the judge misread it, say so in one line and keep the answer."}}\n' "$r"
