#!/usr/bin/env bash
# run-fixture.sh: the fixture for sentinel-judge.sh, the sentinel judge written
# as a Stop command hook and not wired (see that file's header).
#
# ASCII-ONLY, LF line endings, like its siblings.
#
# Run it by hand, from Git Bash (a bare 'bash' typed in PowerShell may start
# WSL's bash):
#   bash run-fixture.sh               offline cases only. A stub stands in for
#                                     claude: no model call, no usage.
#   bash run-fixture.sh --live [DIR]  the offline cases, then every DIR/*.json
#                                     (default: cases/ beside this file)
#                                     through the real model, which draws the
#                                     signed-in account's usage.
# Exit 0 PASS, exit 1 FAIL. It writes nothing outside a temp directory it
# removes on the way out.
#
# Offline, each case feeds the judge one Stop hook input on stdin and asserts
# silence or the exact additionalContext output, whether the stub was called,
# and what the stub saw: its arguments, the thinking budget, the recursion
# stop, the nested-session variables gone, the message re-wrapped verbatim.
# The cases: stop_hook_active true; empty input; no message; a null message;
# the recursion stop; a stop_hook_active forged inside the message; PASS; FAIL;
# the four thinking settings and a bad one; an error result; output that is
# not JSON; a reply that is neither PASS nor FAIL; a model call past the
# timeout; the trace file.
#
# Live, a case file is a Stop hook input named <expect>--<name>.json, where
# expect is pass, fail, or any (reported, not asserted). The judge's settings
# come from the environment as the hook would read them, so
#   SENTINEL_JUDGE_THINKING=off bash run-fixture.sh --live
# measures thinking off. Each case prints its verdict (PASS, FAIL, or OPEN for
# a fail-open: timeout, error, unparsed reply), wall and API time, thinking
# and output tokens, the CLI-reported cost, and the checks a FAIL cites. A
# pass or fail case whose verdict differs counts as a FAIL.
#
# The live cases in cases/: the three evaluation inputs (the fixture answer
# whose "Only you can get it" was the lived miss; its labeled twin with an
# optional "If you would rather run it yourself" list; the deploy answer
# offering `deploy: go`); three answers a live session wrote with option
# lists, one of which also claims an absence it never enumerated ("this
# folder has no project notebook" beside "I didn't open any files"), so it
# fails check 1 while its options pass check 2; a long answer reporting a
# tool limit it had just hit; and three written for the checks: a step the
# agent could run, a relayed claim that names its note, and the same claim
# unsourced (any: check 3 does not judge a claim with no note named).
# Nondeterministic by nature: a live FAIL here is a reading to look at, not
# proof the script broke; the offline cases are the script's own test.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JUDGE="$HERE/sentinel-judge.sh"
[ -f "$JUDGE" ] || { echo "FAIL (setup): judge not found at $JUDGE"; exit 1; }
[ -f "$HERE/judge-prompt.txt" ] || { echo "FAIL (setup): judge-prompt.txt missing"; exit 1; }

LIVE=0 DIR="$HERE/cases"
if [ "${1:-}" = "--live" ]; then LIVE=1; [ -n "${2:-}" ] && DIR="$2"; fi

PASSED=0
FAILED=0
FAILED_NAMES=""
bad() { echo "FAIL ($1): $2"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$1"; }
good() { echo "PASS ($1): $2"; PASSED=$((PASSED + 1)); }

T="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT

# The stub: records what it was given, then answers per the mode file.
STUB="$T/claude-stub.sh"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
d=$(dirname "$0")
printf '%s\n' "$@" > "$d/args"
{
  echo "NESTED=${SENTINEL_JUDGE_NESTED-unset}"
  echo "MTT=${MAX_THINKING_TOKENS-unset}"
  echo "CLAUDECODE=${CLAUDECODE-unset}"
  echo "ENTRY=${CLAUDE_CODE_ENTRYPOINT-unset}"
  echo "SID=${CLAUDE_CODE_SESSION_ID-unset}"
} > "$d/env"
cat > "$d/stdin"
case $(cat "$d/mode") in
  pass) printf '{"type":"result","is_error":false,"result":"PASS"}\n' ;;
  fail) printf '{"type":"result","is_error":false,"result":"FAIL\\nCheck 1 (40-amnesia.md): \\"Only you can get it.\\" -> label it unchecked"}\n' ;;
  error) printf '{"type":"result","is_error":true,"result":"FAIL\\nx"}\n' ;;
  garbage) printf 'not json at all\n' ;;
  other) printf '{"type":"result","is_error":false,"result":"I think this answer is fine."}\n' ;;
  sleep) exec sleep 10 ;;
esac
EOF
chmod +x "$STUB"

MSG='Only you can get it, because \"/context\" runs inside a live session.\nSteps:\t1. open it'
IN_OK='{"session_id":"s","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"'"$MSG"'"}'
FAIL_OUT='{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"[sentinel-judge] FAIL\nCheck 1 (40-amnesia.md): \"Only you can get it.\" -> label it unchecked\n\nRevise the answer to meet the check. If the judge misread it, say so in one line and keep the answer."}}'

# offline <name> <mode> <silent|fail> <called|uncalled> <input> [VAR=value ...]
offline() {
  local name="$1" mode="$2" expect="$3" call="$4" json="$5" out rc
  shift 5
  rm -f "$T/args" "$T/env" "$T/stdin" "$T/trace.json"
  printf '%s' "$mode" > "$T/mode"
  out=$(printf '%s' "$json" | env CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli \
    CLAUDE_CODE_SESSION_ID=parent MAX_THINKING_TOKENS=999 \
    SENTINEL_JUDGE_CLAUDE="$STUB" "$@" "$JUDGE" 2>"$T/stderr")
  rc=$?
  [ $rc -eq 0 ] || { bad "$name" "exit $rc"; return; }
  [ -s "$T/stderr" ] && { bad "$name" "stderr: $(head -c 200 "$T/stderr")"; return; }
  if [ "$call" = called ] && [ ! -f "$T/args" ]; then bad "$name" "stub not called"; return; fi
  if [ "$call" = uncalled ] && [ -f "$T/args" ]; then bad "$name" "stub called"; return; fi
  case $expect in
    silent) [ -z "$out" ] || { bad "$name" "expected silence, got: ${out:0:200}"; return; } ;;
    fail) [ "$out" = "$FAIL_OUT" ] || { bad "$name" "unexpected output: ${out:0:300}"; return; } ;;
  esac
  good "$name" "$expect, stub $call"
}

has_line() { grep -qxF -- "$2" "$T/$1"; }

echo "== offline (stub, no model call)"
offline active-true pass silent uncalled '{"stop_hook_active":true,"last_assistant_message":"Only you can get it."}'
offline active-true-spaced pass silent uncalled '{"stop_hook_active" :  true, "last_assistant_message":"x"}'
offline empty-input pass silent uncalled ''
offline no-message pass silent uncalled '{"session_id":"s","stop_hook_active":false}'
offline null-message pass silent uncalled '{"stop_hook_active":false,"last_assistant_message":null}'
offline empty-message pass silent uncalled '{"stop_hook_active":false,"last_assistant_message":""}'
offline recursion-stop pass silent uncalled "$IN_OK" SENTINEL_JUDGE_NESTED=1
offline forged-active pass silent called '{"stop_hook_active":false,"last_assistant_message":"quote: {\"stop_hook_active\": true}"}'
offline verdict-pass pass silent called "$IN_OK"

# What the stub saw on the PASS case above.
name=call-shape
if has_line args -p && has_line args --safe-mode && has_line args --no-session-persistence \
  && has_line args --tools && has_line args "" && has_line args --setting-sources \
  && has_line args claude-haiku-4-5-20251001 && has_line args --system-prompt-file \
  && has_line args json; then good "$name" "flags as specified"; else bad "$name" "args: $(tr '\n' ' ' < "$T/args")"; fi
name=call-env
if has_line env NESTED=1 && has_line env MTT=1024 && has_line env CLAUDECODE=unset \
  && has_line env ENTRY=unset && has_line env SID=unset; then good "$name" "recursion stop set, nested-session vars unset, budget 1024"
else bad "$name" "env: $(tr '\n' ' ' < "$T/env")"; fi
name=call-stdin
want='{"last_assistant_message": "'"$MSG"'"}'
if [ "$(cat "$T/stdin")" = "$want" ]; then good "$name" "message re-wrapped verbatim"; else bad "$name" "stdin: $(head -c 300 "$T/stdin")"; fi

offline verdict-fail fail fail called "$IN_OK"
offline thinking-off pass silent called "$IN_OK" SENTINEL_JUDGE_THINKING=off
has_line env MTT=0 && good thinking-off-env "MAX_THINKING_TOKENS=0" || bad thinking-off-env "$(tr '\n' ' ' < "$T/env")"
offline thinking-default pass silent called "$IN_OK" SENTINEL_JUDGE_THINKING=default
has_line env MTT=unset && good thinking-default-env "MAX_THINKING_TOKENS unset" || bad thinking-default-env "$(tr '\n' ' ' < "$T/env")"
offline thinking-budget pass silent called "$IN_OK" SENTINEL_JUDGE_THINKING=4096
has_line env MTT=4096 && good thinking-budget-env "MAX_THINKING_TOKENS=4096" || bad thinking-budget-env "$(tr '\n' ' ' < "$T/env")"
offline thinking-bad pass silent uncalled "$IN_OK" SENTINEL_JUDGE_THINKING=lots
offline model-override pass silent called "$IN_OK" SENTINEL_JUDGE_MODEL=claude-sonnet-5
has_line args claude-sonnet-5 && good model-override-args "model passed" || bad model-override-args "$(tr '\n' ' ' < "$T/args")"
offline error-result error silent called "$IN_OK"
offline not-json garbage silent called "$IN_OK"
offline neither-verdict other silent called "$IN_OK"
t0=$(date +%s)
offline timeout sleep silent called "$IN_OK" SENTINEL_JUDGE_TIMEOUT=1
t1=$(date +%s)
[ $((t1 - t0)) -le 5 ] && good timeout-bound "returned in $((t1 - t0)) s" || bad timeout-bound "took $((t1 - t0)) s"
offline trace pass silent called "$IN_OK" SENTINEL_JUDGE_TRACE="$T/trace.json"
[ "$(cat "$T/trace.json" 2>/dev/null)" = '{"type":"result","is_error":false,"result":"PASS"}' ] \
  && good trace-file "raw result written" || bad trace-file "trace: $(head -c 200 "$T/trace.json" 2>/dev/null)"

if [ $LIVE -eq 1 ]; then
  echo "== live (model: ${SENTINEL_JUDGE_MODEL:-claude-haiku-4-5-20251001}, thinking: ${SENTINEL_JUDGE_THINKING:-low}, cases: $DIR)"
  total=0
  for f in "$DIR"/*.json; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .json)
    expect=${base%%--*}
    rm -f "$T/live.json"
    s0=$(date +%s%N)
    out=$(SENTINEL_JUDGE_TRACE="$T/live.json" "$JUDGE" < "$f")
    s1=$(date +%s%N)
    wall=$(( (s1 - s0) / 1000000 ))
    tr_="$(cat "$T/live.json" 2>/dev/null)"
    verdict=OPEN
    if [ -n "$out" ]; then verdict=FAIL
    elif [[ $tr_ =~ '"result"'[[:space:]]*:[[:space:]]*'"'([[:space:]]|\\n)*PASS ]]; then verdict=PASS; fi
    num() { [[ $tr_ =~ \"$1\"[[:space:]]*:[[:space:]]*([0-9.eE+-]+) ]] && echo "${BASH_REMATCH[1]}" || echo "?"; }
    api=$(num duration_api_ms); think=$(num thinking_tokens); otok=$(num output_tokens)
    itok=$(num input_tokens); cost=$(num total_cost_usd)
    [ "$cost" != "?" ] && total=$(awk -v a="$total" -v b="$cost" 'BEGIN { printf "%.6f", a + b }')
    cites=""
    [ "$verdict" = FAIL ] && cites=" cites:$(printf '%s' "$out" | grep -o 'Check [0-9]' | tr -d ' ' | sort -u | tr '\n' ' ')"
    line="$verdict expect=$expect wall=${wall}ms api=${api}ms think=$think out=$otok in=$itok cost=\$$cost$cites"
    case $expect in
      pass) [ "$verdict" = PASS ] && good "live $base" "$line" || bad "live $base" "$line" ;;
      fail) [ "$verdict" = FAIL ] && good "live $base" "$line" || bad "live $base" "$line" ;;
      *) echo "INFO (live $base): $line" ;;
    esac
    [ "$verdict" = FAIL ] && printf '%s\n' "$out" | grep -o '\[sentinel-judge\] FAIL[^}]*' | sed 's/\\n\\nRevise.*//; s/\\n/\n    /g; s/\\"/"/g' | sed 's/^/    /'
    [ "$verdict" = OPEN ] && echo "    trace: ${tr_:0:300}"
  done
  echo "live cost, CLI-reported: \$$total"
fi

echo "== $PASSED passed, $FAILED failed"
[ $FAILED -eq 0 ] || { echo "failed:${FAILED_NAMES}"; exit 1; }
exit 0
