#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/refocus.sh, the SessionStart
# stale-resume line and the PreCompact cold-compaction stop.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It writes nothing outside a temp directory it
# removes on the way out, and it never reads a real transcript or touches a
# deployed home. On Windows run it from Git Bash: a bare 'bash' typed in
# PowerShell may start WSL's bash.
#
# Every case feeds the hook one input on stdin, as the harness does, and
# asserts stdout, stderr and the exit code: silence is exit 0 with nothing on
# either stream; the line is exit 0 with exactly that line on stdout; a pass
# is exit 0 with nothing; a block is exit 2 with exactly the block message on
# stderr and nothing on stdout. No case may put anything else on stderr.
# The clock is fixed: a date shim first on PATH answers date +%s with
# FAKE_NOW, so idle times are exact. Transcripts are synthetic, written in the
# shapes read on real 2.1.296 lines (the 2.1.282 shape for the synthetic
# line), with timestamps made from FAKE_NOW by the fixture's own epoch-to-ISO
# helper; two anchor cases give the hook fixed ISO times instead, so its date
# arithmetic is checked independently of that helper.
#
# Each branch has its own floor (the human's words, 2026-10-13): the resume
# line 100,000 tokens ("resume line: 100k"), the block 280,000 ("floor:
# 280k"). The spec's two texts were written at 190K, above the line's floor
# and below the block's, so they are checked against the fixture's own
# templates (the templates must give them verbatim at 3h12m and 190K), the
# 190K resume case gives the spec's line itself, and every other case runs
# through those templates.
#
# THE CASES. SessionStart: resume, expired, 300,000 tokens, 3h12m gives the
# line; 190,000 gives the spec's line; 99,999 silent and 100,000 the line;
# not expired at 500,000 silent; fork expired the line; startup, clear and
# compact with the fields silent; the fields absent silent; an agent_id
# silent; empty and
# malformed input silent; idle formatted at 59m and at 25h0m; rounding to the
# nearest K; a crash forced inside the branch fails silent. PreCompact: manual,
# cold 2h, 300K blocks with the exact message, and so does 3h12m; cold at 190K
# and at 80K pass; 279,999 passes and 280,000 blocks; warm 30m
# passes; an auto trigger, cold and large, passes; the escape
# word first (anyway keep X, Anyway, ANYWAY, keep it) passes, and keep anyway,
# anywayish and anyway2 block; a synthetic assistant line last with the real
# one 2h old blocks; a sidechain line last with the real one 2h old blocks; an
# away_summary 10m ago after a response 2h ago passes, and one before that
# response blocks; a compact_boundary after a cold 300K response passes (the
# size is unknown since), and one before that response blocks; 5-minute-only cache writes at 10m idle block (5m in the
# message) and at 4m pass; no cache writes at all at 10m idle pass (one hour
# assumed); a missing transcript, no transcript_path, a transcript with no
# assistant line, empty and malformed input pass; the Windows-escaped path
# (where cygpath answers) and the POSIX path both resolve; unparsable and
# zone-offset timestamps pass; idle exactly equal to the lifetime passes and
# one second more blocks; decoy "timestamp", "input_tokens" and "usage" keys
# inside message content are ignored in both directions; a usage line with a
# count missing passes; two anchor times (2000-03-01, 2024-02-29) block with
# the idle the calendar gives; a crash forced inside the branch passes; a 10
# MB transcript blocks in under 1 second; and a cold line older than the 8 MB
# window at the head of a 10 MB transcript is not read.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../../hooks/refocus.sh"
[ -f "$HOOK" ] || { echo "FAIL (setup): hook not found at $HOOK"; exit 1; }

PASSED=0
FAILED=0
SKIPPED=0

TMPBASE="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMPBASE"' EXIT

bad() { echo "FAIL ($1): $2"; FAILED=$((FAILED + 1)); }
good() { echo "PASS ($1): $2"; PASSED=$((PASSED + 1)); }
skip() { echo "SKIP ($1): $2"; SKIPPED=$((SKIPPED + 1)); }

# --- The fixed clock ----------------------------------------------------------
BIN="$TMPBASE/bin"
mkdir -p "$BIN"
printf '#!/bin/sh\nprintf "%%s\\n" "$FAKE_NOW"\n' > "$BIN/date"
chmod +x "$BIN/date"
NOW=1791900000

# iso <epoch>: YYYY-MM-DDTHH:MM:SS.123Z, by civil-from-days (not the hook's
# days-from-civil, so the two check each other).
iso() {
  local s=$1 days sod z era doe yoe y doy mp d m
  days=$((s / 86400)) sod=$((s % 86400))
  z=$((days + 719468))
  era=$((z / 146097))
  doe=$((z - era * 146097))
  yoe=$(((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365))
  y=$((yoe + era * 400))
  doy=$((doe - (365 * yoe + yoe / 4 - yoe / 100)))
  mp=$(((5 * doy + 2) / 153))
  d=$((doy - (153 * mp + 2) / 5 + 1))
  m=$((mp < 10 ? mp + 3 : mp - 9))
  [ "$m" -le 2 ] && y=$((y + 1))
  printf '%04d-%02d-%02dT%02d:%02d:%02d.123Z' "$y" "$m" "$d" $((sod / 3600)) $((sod % 3600 / 60)) $((sod % 60))
}
ago() { iso $((NOW - $1)); }

# jesc: one string escaped for JSON.
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# --- Transcript lines ---------------------------------------------------------
TEXT='[{"type":"text","text":"Done."}]'
# aline <ts> <in> <cc> <cr> <out> <e1h> <e5m> [content] [isSidechain]
# The 2.1.296 shape: message first, its usage repeating the counts inside
# iterations, then type, uuid and the line's own timestamp.
aline() {
  printf '{"parentUuid":"p","isSidechain":%s,"message":{"model":"claude-opus-5-5","id":"msg_x","type":"message","role":"assistant","content":%s,"container":null,"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s,"output_tokens_details":{"thinking_tokens":10},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":%s,"ephemeral_5m_input_tokens":%s},"inference_geo":"global","iterations":[{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s},"type":"message"}],"speed":"standard"},"context_management":null},"requestId":"req_x","type":"assistant","uuid":"u","timestamp":"%s","userType":"external","entrypoint":"cli","cwd":"C:\\\\work","sessionId":"s1","version":"2.1.296","gitBranch":"main"}\n' \
    "${9:-false}" "${8:-$TEXT}" "$2" "$3" "$4" "$5" "$6" "$7" "$2" "$5" "$4" "$3" "$7" "$6" "$1"
}
# big <ts>: an assistant line at 300,000 tokens, 1-hour writes.
big() { aline "$1" 2 600 299000 398 600 0; }
# mid <ts>: the same at 190,000 tokens, below the block's floor.
mid() { aline "$1" 2 600 189000 398 600 0; }
# uline <ts> [text]
uline() {
  printf '{"parentUuid":"p","isSidechain":false,"type":"user","message":{"role":"user","content":"%s"},"uuid":"u","timestamp":"%s","userType":"external","cwd":"C:\\\\work","sessionId":"s1","version":"2.1.296"}\n' "${2:-hello}" "$1"
}
# away <ts>
away() {
  printf '{"parentUuid":"p","isSidechain":false,"type":"system","subtype":"away_summary","content":"While you were away, nothing changed.","timestamp":"%s","uuid":"u","isMeta":false,"userType":"external","cwd":"C:\\\\work","sessionId":"s1","version":"2.1.296"}\n' "$1"
}
# bnd <ts>: a manual compaction's boundary, 300K down to 31K.
bnd() {
  printf '{"parentUuid":null,"logicalParentUuid":"p","isSidechain":false,"type":"system","subtype":"compact_boundary","content":"Conversation compacted","level":"info","compactMetadata":{"trigger":"manual","preTokens":300000,"postTokens":31053},"timestamp":"%s","uuid":"u"}\n' "$1"
}
# synth <ts>: the 2.1.282 shape, type and timestamp before the message.
synth() {
  printf '{"parentUuid":"p","isSidechain":false,"type":"assistant","uuid":"u","timestamp":"%s","message":{"id":"x","container":null,"model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence","type":"message","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}},"content":[{"type":"text","text":"No response requested."}]},"isApiErrorMessage":false}\n' "$1"
}

# tr_file <name> <line>...: a transcript; sets T.
tr_file() {
  T="$TMPBASE/$1.jsonl"
  shift
  printf '%s\n' "$@" > "$T"
}

# --- Inputs -------------------------------------------------------------------
# ss <source> [fields json fragment] [agent_id]
ss() {
  local agent=""
  [ -z "${3:-}" ] || agent="\"agent_id\":\"$3\",\"agent_type\":\"Builder\","
  printf '{"session_id":"s1","transcript_path":"/x/s1.jsonl","cwd":"C:\\\\work",%s"hook_event_name":"SessionStart","source":"%s","model":"claude-opus-5-5"%s}' "$agent" "$1" "${2:-}"
}
# fields <secs> <ctx> <expired>
fields() { printf ',"seconds_since_last_response":%s,"context_tokens":%s,"prompt_cache_likely_expired":%s,"estimated_cache_write_usd":1.1396' "$1" "$2" "$3"; }
# pc <path> [trigger] [custom_instructions as JSON]
pc() {
  printf '{"session_id":"s1","transcript_path":"%s","cwd":"C:\\\\work","hook_event_name":"PreCompact","trigger":"%s","custom_instructions":%s}' "$(jesc "$1")" "${2:-manual}" "${3:-null}"
}

# run <input> [VAR=value...]: sets OUT, RC, ERR.
run() {
  local in="$1"
  shift
  OUT="$(printf '%s' "$in" | env -u BASH_ENV "PATH=$BIN:$PATH" "FAKE_NOW=$NOW" "$@" "$BASH" "$HOOK" 2>"$TMPBASE/err")"
  RC=$?
  ERR="$(cat "$TMPBASE/err")"
}

# --- Expected text ------------------------------------------------------------
# The two texts as the spec gives them, verbatim.
SPEC_LINE='[refocus] This conversation resumed after 3h12m idle at about 190K tokens; its prompt cache had expired, so this first request re-reads the whole history. The first reply opens with one refocus line: compact now with a stated focus while the history is cached again, or a fresh session with its resume prompt.'
SPEC_BLOCK='Compaction stopped: this conversation has been idle 3h12m, past its 1h prompt cache, so compacting would first re-read all of its ~190K tokens at full price. A fresh session costs less: run /clear, then name the work to pick up; its Handoff carries the state, so no resume note is needed (asking this conversation for one costs the same full re-read). To compact anyway: /compact anyway <focus>'
# line <idle> <K>
line() { printf '[refocus] This conversation resumed after %s idle at about %s tokens; its prompt cache had expired, so this first request re-reads the whole history. The first reply opens with one refocus line: compact now with a stated focus while the history is cached again, or a fresh session with its resume prompt.' "$1" "$2"; }
# blockmsg <idle> <lifetime> <K>
blockmsg() { printf 'Compaction stopped: this conversation has been idle %s, past its %s prompt cache, so compacting would first re-read all of its ~%s tokens at full price. A fresh session costs less: run /clear, then name the work to pick up; its Handoff carries the state, so no resume note is needed (asking this conversation for one costs the same full re-read). To compact anyway: /compact anyway <focus>' "$1" "$2" "$3"; }

# --- Assertions ---------------------------------------------------------------
quiet() {
  if [ "$RC" = 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then good "$1" "silent, exit 0"
  else bad "$1" "want silence and exit 0; got exit $RC, stdout [$OUT], stderr [$ERR]"; fi
}
says() {
  if [ "$RC" = 0 ] && [ "$OUT" = "$2" ] && [ -z "$ERR" ]; then good "$1" "the line, exit 0"
  else bad "$1" "want the line [$2] and exit 0; got exit $RC, stdout [$OUT], stderr [$ERR]"; fi
}
blocks() {
  if [ "$RC" = 2 ] && [ -z "$OUT" ] && [ "$ERR" = "$2" ]; then good "$1" "blocked, exit 2"
  else bad "$1" "want exit 2 with [$2] on stderr; got exit $RC, stdout [$OUT], stderr [$ERR]"; fi
}

# --- The fixture's own helper -------------------------------------------------
if [ "$(iso 951868800)" = 2000-03-01T00:00:00.123Z ] && [ "$(iso 1709208000)" = 2024-02-29T12:00:00.123Z ]; then
  good helper "iso() gives the calendar's dates"
else
  bad helper "iso() is wrong: $(iso 951868800), $(iso 1709208000)"
fi
if [ "$(env "PATH=$BIN:$PATH" FAKE_NOW=42 date +%s)" = 42 ]; then
  good clock "the date shim answers date +%s"
else
  bad clock "the date shim is not first on PATH"
fi
if [ "$(line 3h12m 190K)" = "$SPEC_LINE" ] && [ "$(blockmsg 3h12m 1h 190K)" = "$SPEC_BLOCK" ]; then
  good templates "both templates give the spec's texts verbatim"
else
  bad templates "a template drifted from the spec's text"
fi

# --- SessionStart -------------------------------------------------------------
run "$(ss resume "$(fields 11520 300000 true)")"; says ss-line "$(line 3h12m 300K)"
run "$(ss resume "$(fields 11520 190000 true)")"; says ss-190k-spec-line "$SPEC_LINE"
run "$(ss resume "$(fields 7200 99999 true)")"; quiet ss-floor-below
run "$(ss resume "$(fields 7200 100000 true)")"; says ss-floor-at "$(line 2h0m 100K)"
run "$(ss resume "$(fields 7200 500000 false)")"; quiet ss-not-expired
run "$(ss fork "$(fields 11520 300000 true)")"; says ss-fork "$(line 3h12m 300K)"
for src in startup clear compact; do
  run "$(ss "$src" "$(fields 11520 300000 true)")"; quiet "ss-source-$src"
done
run "$(ss resume)"; quiet ss-fields-absent
run "$(ss resume ',"context_tokens":300000,"prompt_cache_likely_expired":true')"; quiet ss-seconds-absent
run "$(ss resume ',"seconds_since_last_response":11520,"prompt_cache_likely_expired":true')"; quiet ss-tokens-absent
run "$(ss resume ',"seconds_since_last_response":11520,"context_tokens":300000')"; quiet ss-expired-absent
run "$(ss resume "$(fields 11520 300000 true)" a1)"; quiet ss-agent-id
run ""; quiet ss-empty
run '{"hook_event_name":"SessionStart","source":"resume","seconds_since_last_response":'; quiet ss-malformed
run 'not json at all'; quiet ss-garbage
run "$(ss resume "$(fields 3540 300000 true)")"; says ss-idle-59m "$(line 59m 300K)"
run "$(ss resume "$(fields 90000 300000 true)")"; says ss-idle-25h "$(line 25h0m 300K)"
run "$(ss resume "$(fields 11520 282340 true)")"; says ss-round-down "$(line 3h12m 282K)"
run "$(ss resume "$(fields 11520 282500 true)")"; says ss-round-up "$(line 3h12m 283K)"
printf 'readonly secs\n' > "$TMPBASE/crash-secs"
run "$(ss resume "$(fields 11520 300000 true)")" "BASH_ENV=$TMPBASE/crash-secs"; quiet ss-crash-fails-silent

# --- PreCompact ---------------------------------------------------------------
tr_file cold2h "$(uline "$(ago 7300)")" "$(big "$(ago 7200)")"
COLD="$T"
run "$(pc "$COLD")"; blocks pc-cold-2h "$(blockmsg 2h0m 1h 300K)"
tr_file cold312 "$(big "$(ago 11520)")"
run "$(pc "$T")"; blocks pc-cold-3h12m "$(blockmsg 3h12m 1h 300K)"
tr_file cold190 "$(mid "$(ago 11520)")"
run "$(pc "$T")"; quiet pc-cold-190k-below-floor
tr_file under "$(aline "$(ago 7200)" 2 600 278999 398 600 0)"
run "$(pc "$T")"; quiet pc-floor-below
tr_file atfloor "$(aline "$(ago 7200)" 2 600 279000 398 600 0)"
run "$(pc "$T")"; blocks pc-floor-at "$(blockmsg 2h0m 1h 280K)"
tr_file warm "$(big "$(ago 1800)")"
run "$(pc "$T")"; quiet pc-warm-30m
tr_file small "$(aline "$(ago 7200)" 2 600 79000 398 600 0)"
run "$(pc "$T")"; quiet pc-cold-80k
run "$(pc "$COLD" auto)"; quiet pc-auto
run "$(pc "$COLD" manual '"anyway keep X"')"; quiet pc-escape-anyway
run "$(pc "$COLD" manual '"Anyway"')"; quiet pc-escape-Anyway
run "$(pc "$COLD" manual '"ANYWAY, keep it"')"; quiet pc-escape-ANYWAY-comma
run "$(pc "$COLD" manual '"keep anyway"')"; blocks pc-escape-not-first "$(blockmsg 2h0m 1h 300K)"
run "$(pc "$COLD" manual '"anywayish"')"; blocks pc-escape-longer-word "$(blockmsg 2h0m 1h 300K)"
run "$(pc "$COLD" manual '"anyway2 keep"')"; blocks pc-escape-with-digit "$(blockmsg 2h0m 1h 300K)"
run "$(pc "$COLD" manual '"keep the pickup point"')"; blocks pc-focus-text "$(blockmsg 2h0m 1h 300K)"
tr_file synthlast "$(big "$(ago 7200)")" "$(uline "$(ago 60)")" "$(synth "$(ago 30)")"
run "$(pc "$T")"; blocks pc-synthetic-last "$(blockmsg 2h0m 1h 300K)"
tr_file sidelast "$(big "$(ago 7200)")" "$(aline "$(ago 30)" 2 600 299000 398 600 0 "$TEXT" true)"
run "$(pc "$T")"; blocks pc-sidechain-last "$(blockmsg 2h0m 1h 300K)"
tr_file awaylater "$(big "$(ago 7200)")" "$(away "$(ago 600)")"
run "$(pc "$T")"; quiet pc-away-after
tr_file awaybefore "$(away "$(ago 9000)")" "$(big "$(ago 7200)")"
run "$(pc "$T")"; blocks pc-away-before "$(blockmsg 2h0m 1h 300K)"
tr_file boundafter "$(big "$(ago 9000)")" "$(bnd "$(ago 7200)")"
run "$(pc "$T")"; quiet pc-boundary-after
tr_file boundbefore "$(bnd "$(ago 9000)")" "$(big "$(ago 7200)")"
run "$(pc "$T")"; blocks pc-boundary-before "$(blockmsg 2h0m 1h 300K)"
tr_file fivemin "$(aline "$(ago 600)" 2 5000 295000 398 0 5000)"
run "$(pc "$T")"; blocks pc-5m-cold "$(blockmsg 10m 5m 300K)"
tr_file fivewarm "$(aline "$(ago 240)" 2 5000 295000 398 0 5000)"
run "$(pc "$T")"; quiet pc-5m-warm
tr_file nowrites "$(aline "$(ago 600)" 2 0 299600 398 0 0)"
run "$(pc "$T")"; quiet pc-no-writes-1h-assumed
run "$(pc "$TMPBASE/missing.jsonl")"; quiet pc-missing-transcript
run '{"session_id":"s1","hook_event_name":"PreCompact","trigger":"manual","custom_instructions":null}'; quiet pc-no-path
tr_file noasst "$(uline "$(ago 9000)")" "$(uline "$(ago 7200)")"
run "$(pc "$T")"; quiet pc-no-assistant
run ""; quiet pc-empty
run '{"hook_event_name":"PreCompact","trigger":"manual","transcript_path":"'; quiet pc-malformed
if command -v cygpath >/dev/null 2>&1; then
  WP="$(cygpath -w "$COLD")"
  run "$(pc "$WP")"; blocks pc-windows-path "$(blockmsg 2h0m 1h 300K)"
else
  skip pc-windows-path "no cygpath here"
fi
run "$(pc "$COLD")"; blocks pc-posix-path "$(blockmsg 2h0m 1h 300K)"
tr_file badts "$(aline '2026-10-12 20:19:04' 2 600 299000 398 600 0)"
run "$(pc "$T")"; quiet pc-unparsable-timestamp
tr_file zonets "$(aline '2026-01-01T00:00:00.000+02:00' 2 600 299000 398 600 0)"
run "$(pc "$T")"; quiet pc-zone-offset-timestamp
tr_file equal "$(big "$(ago 3600)")"
run "$(pc "$T")"; quiet pc-idle-equal-lifetime
tr_file oneover "$(big "$(ago 3601)")"
run "$(pc "$T")"; blocks pc-idle-one-over "$(blockmsg 1h0m 1h 300K)"
DECOY_RECENT='[{"type":"text","text":"a decoy \"timestamp\":\"'"$(ago 30)"'\" and \"input_tokens\":5"},{"type":"tool_use","id":"t1","name":"Probe","input":{"timestamp":"'"$(ago 30)"'","input_tokens":1,"usage":{"input_tokens":1,"cache_read_input_tokens":1}}}]'
tr_file decoy1 "$(aline "$(ago 7200)" 2 600 299000 398 600 0 "$DECOY_RECENT")"
run "$(pc "$T")"; blocks pc-decoy-recent-ignored "$(blockmsg 2h0m 1h 300K)"
DECOY_OLD='[{"type":"tool_use","id":"t1","name":"Probe","input":{"timestamp":"'"$(ago 90000)"'","input_tokens":900000,"usage":{"input_tokens":900000}}}]'
tr_file decoy2 "$(aline "$(ago 600)" 2 600 299000 398 600 0 "$DECOY_OLD")"
run "$(pc "$T")"; quiet pc-decoy-old-ignored
tr_file decoy3 "$(aline "$(ago 7200)" 2 600 49000 398 600 0 "$DECOY_OLD")"
run "$(pc "$T")"; quiet pc-decoy-large-ignored
tr_file nocount "$(big "$(ago 7200)" | sed -e 's/"cache_read_input_tokens":299000,//g')"
run "$(pc "$T")"; quiet pc-count-missing
tr_file anchor2000 "$(aline 2000-03-01T00:00:00.000Z 2 600 299000 398 600 0)"
run "$(pc "$T")" FAKE_NOW=$((951868800 + 7200)); blocks pc-anchor-2000 "$(blockmsg 2h0m 1h 300K)"
tr_file anchor2024 "$(aline 2024-02-29T12:00:00Z 2 600 299000 398 600 0)"
run "$(pc "$T")" FAKE_NOW=$((1709208000 + 11520)); blocks pc-anchor-leap-day "$(blockmsg 3h12m 1h 300K)"
printf 'readonly ctx\n' > "$TMPBASE/crash-ctx"
run "$(pc "$COLD")" "BASH_ENV=$TMPBASE/crash-ctx"; quiet pc-crash-fails-open

# --- Size and the read window ---------------------------------------------------
PAD="$(printf '%9000s' '' | tr ' ' 'x')"
CHUNK="$TMPBASE/chunk"
{ uline "$(ago 20000)" "$PAD"; aline "$(ago 19000)" 2 600 150000 398 600 0 "[{\"type\":\"text\",\"text\":\"$PAD\"}]"; } > "$CHUNK"
USERS="$TMPBASE/users"
uline "$(ago 20000)" "$PAD" > "$USERS"
grow() {
  local f="$1" n
  n=$(wc -c < "$f")
  while [ "$n" -lt 10485760 ]; do
    cat "$f" "$f" > "$f.2" && mv "$f.2" "$f"
    n=$(wc -c < "$f")
  done
}
grow "$CHUNK"
grow "$USERS"
BIG="$TMPBASE/big.jsonl"
{ cat "$CHUNK"; big "$(ago 7200)"; } > "$BIG"
run "$(pc "$BIG")"
TIMEFORMAT='%R'
{ time run "$(pc "$BIG")"; } 2> "$TMPBASE/time"
SECS="$(tr -d '\r\n' < "$TMPBASE/time")"
blocks pc-10mb-verdict "$(blockmsg 2h0m 1h 300K)"
case "$SECS" in
  0.* | .*) good pc-10mb-speed "$(wc -c < "$BIG" | tr -d ' ') bytes in ${SECS}s" ;;
  *) bad pc-10mb-speed "$(wc -c < "$BIG" | tr -d ' ') bytes took ${SECS}s, want under 1s" ;;
esac
WIN="$TMPBASE/window.jsonl"
{ big "$(ago 30000)"; cat "$USERS"; } > "$WIN"
run "$(pc "$WIN")"; quiet pc-outside-window

echo
echo "refocus fixture: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" = 0 ]
