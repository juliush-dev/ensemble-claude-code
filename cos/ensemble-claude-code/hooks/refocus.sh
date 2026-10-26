#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - refocus: the stale-resume line and the
# cold-compaction stop.
#
# One script, two events, branching on the input's hook_event_name.
#
# SessionStart (wired on matcher resume|fork; the script re-checks source).
#   Claude Code 2.1.251 and later send a resumed or forked session that holds
#   a response from Claude three fields: seconds_since_last_response,
#   context_tokens, prompt_cache_likely_expired. When source is resume or
#   fork, the cache has likely expired and context_tokens is at least
#   RESUME_FLOOR_TOKENS, one line goes to stdout, which SessionStart adds to
#   the session's context. It is written as fact, not as an instruction,
#   because imperative hook text can trip prompt-injection defenses. Silent on
#   every other path: a present agent_id (a subagent), another source, the
#   cache still warm, a smaller context, any of the three fields absent, empty
#   or malformed input.
#
# PreCompact (wired on matcher manual; the script re-checks trigger).
#   A manual /compact on a conversation whose prompt cache has gone cold
#   re-reads the whole history at full price before it summarizes. This
#   branch blocks it (exit 2; for a manual /compact Claude Code shows stderr
#   to the user) and recommends a fresh session, when both hold:
#     idle    now minus the last activity is MORE than the cache lifetime
#             (exactly equal passes);
#     size    the context is at least BLOCK_FLOOR_TOKENS.
#   It never blocks an automatic compaction: blocking one can fail the
#   request in flight. ESCAPE_WORD as the first word of the /compact text
#   (any letter case, followed by a non-word character or the end) lets the
#   compaction run. A PreCompact systemMessage is discarded, so stderr is the
#   only channel; it is fd 3 here, a copy of the original stderr, and fd 2 is
#   /dev/null so nothing else ever reaches the user.
#
#   The PreCompact input carries no idle field, so the hook reads the
#   transcript (transcript_path, JSON-unescaped). That format is
#   undocumented; it was read on 2.1.282 and 2.1.296 transcripts:
#     - the last activity is the last main-conversation assistant line in the
#       last TAIL_BYTES of the file: a line holding "type":"assistant",
#       without "isSidechain":true and without "model":"<synthetic>" (a
#       synthetic line is no API request and leaves the cache as it was);
#       its time is the LAST "timestamp" on the line (2.1.296 writes the
#       line's own timestamp after the message object);
#     - a later "subtype":"away_summary" line counts as activity, so its
#       timestamp wins when later (an inference that errs toward allowing);
#     - a later "subtype":"compact_boundary" line means the conversation was
#       compacted since that reply, so its size is unknown and the compaction
#       runs;
#     - the context is the sum of input_tokens, cache_creation_input_tokens,
#       cache_read_input_tokens and output_tokens, each the first occurrence
#       after the line's last "usage":{ (the usage object repeats them inside
#       "iterations"; a key inside message text is JSON-escaped and never
#       matches);
#     - the cache lifetime is one hour, or five minutes when that usage's
#       cache_creation shows ephemeral_5m_input_tokens above 0 and
#       ephemeral_1h_input_tokens at 0 or absent.
#   Fail open: an unreadable or missing transcript, no qualifying line, a
#   missing count, an unparsable timestamp, an unreadable clock, or any crash
#   (the EXIT trap) all exit 0. Subagent transcripts live in a separate
#   subagents folder and never reach this path.
#
# Portability: bash 3.1 or later (BASH_REMATCH, nocasematch), plus tail -c,
# grep -F/-v/-n/-o/-E and date +%s, all in Git Bash, Linux and macOS. No tac,
# jq, awk or date -d; ISO 8601 times (UTC, Z suffix only) become epoch
# seconds in bash arithmetic. A timestamp in any other zone form fails open.
#
# Exit 0 on every path but the block. ASCII only, LF endings.

set -u
# Byte semantics: under a UTF-8 locale grep treats invalid UTF-8, such as a
# character the read window cuts in two, as binary data and does not print the
# line holding it.
export LC_ALL=C

# The three values the human set (2026-10-13: "floor: 280k, escape: anyway",
# then "resume line: 100k"). Each branch has its own floor; each value is one
# line to change.
RESUME_FLOOR_TOKENS=100000
BLOCK_FLOOR_TOKENS=280000
ESCAPE_WORD=anyway

# How much of the transcript's end is read for the last activity.
TAIL_BYTES=8388608

block=0
trap 'if [ "$block" = 1 ]; then exit 2; fi; exit 0' EXIT
exec 3>&2 2>/dev/null

input=""
IFS= read -r -d '' input || true
[ -n "$input" ] || exit 0

# fmt_idle <seconds>: XhYm, or Ym under an hour.
fmt_idle() {
  local s=$1 h m
  h=$((s / 3600))
  m=$((s % 3600 / 60))
  if [ "$h" -gt 0 ]; then
    printf '%dh%dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

# fmt_k <tokens>: rounded to the nearest thousand, with K.
fmt_k() { printf '%dK' $((($1 + 500) / 1000)); }

# iso_epoch <ISO 8601 UTC time>: epoch seconds on stdout, or status 1.
iso_epoch() {
  local re='^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]+)?Z$'
  [[ "$1" =~ $re ]] || return 1
  local y=$((10#${BASH_REMATCH[1]})) mo=$((10#${BASH_REMATCH[2]})) d=$((10#${BASH_REMATCH[3]}))
  local hh=$((10#${BASH_REMATCH[4]})) mi=$((10#${BASH_REMATCH[5]})) ss=$((10#${BASH_REMATCH[6]}))
  [ "$mo" -ge 1 ] && [ "$mo" -le 12 ] && [ "$d" -ge 1 ] && [ "$d" -le 31 ] || return 1
  [ "$hh" -le 23 ] && [ "$mi" -le 59 ] && [ "$ss" -le 60 ] || return 1
  # Days from 1970-01-01 to the civil date (proleptic Gregorian).
  local era yoe doy doe
  y=$((mo <= 2 ? y - 1 : y))
  era=$((y / 400))
  yoe=$((y - era * 400))
  doy=$(((153 * (mo > 2 ? mo - 3 : mo + 9) + 2) / 5 + d - 1))
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  printf '%d' $(((era * 146097 + doe - 719468) * 86400 + hh * 3600 + mi * 60 + ss))
}

ev=""
re='"hook_event_name"[[:space:]]*:[[:space:]]*"([A-Za-z]+)"'
[[ "$input" =~ $re ]] && ev="${BASH_REMATCH[1]}"

# --- SessionStart -------------------------------------------------------------
if [ "$ev" = SessionStart ]; then
  re='"agent_id"[[:space:]]*:'
  [[ "$input" =~ $re ]] && exit 0
  re='"source"[[:space:]]*:[[:space:]]*"(resume|fork)"'
  [[ "$input" =~ $re ]] || exit 0
  re='"prompt_cache_likely_expired"[[:space:]]*:[[:space:]]*true'
  [[ "$input" =~ $re ]] || exit 0
  re='"seconds_since_last_response"[[:space:]]*:[[:space:]]*([0-9]+)'
  [[ "$input" =~ $re ]] || exit 0
  secs="${BASH_REMATCH[1]}"
  re='"context_tokens"[[:space:]]*:[[:space:]]*([0-9]+)'
  [[ "$input" =~ $re ]] || exit 0
  ctx="${BASH_REMATCH[1]}"
  [ "${#secs}" -le 12 ] && [ "${#ctx}" -le 12 ] || exit 0
  secs=$((10#$secs))
  ctx=$((10#$ctx))
  [ "$ctx" -ge "$RESUME_FLOOR_TOKENS" ] || exit 0
  printf '[refocus] This conversation resumed after %s idle at about %s tokens; its prompt cache had expired, so this first request re-reads the whole history. The first reply opens with one refocus line: compact now with a stated focus while the history is cached again, or a fresh session with its resume prompt.\n' "$(fmt_idle "$secs")" "$(fmt_k "$ctx")"
  exit 0
fi

# --- PreCompact ---------------------------------------------------------------
[ "$ev" = PreCompact ] || exit 0

re='"trigger"[[:space:]]*:[[:space:]]*"manual"'
[[ "$input" =~ $re ]] || exit 0

# The escape word, as the first word of the /compact text.
re='"custom_instructions"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
if [[ "$input" =~ $re ]]; then
  ci="${BASH_REMATCH[1]}"
  re='^[[:space:]]*([A-Za-z]+)([^A-Za-z0-9_]|$)'
  if [[ "$ci" =~ $re ]]; then
    first="${BASH_REMATCH[1]}"
    shopt -s nocasematch
    [[ "$first" == "$ESCAPE_WORD" ]] && exit 0
    shopt -u nocasematch
  fi
fi

re='"transcript_path"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
[[ "$input" =~ $re ]] || exit 0
tp="${BASH_REMATCH[1]}"
tp="${tp//\\\\/\\}"
[ -n "$tp" ] && [ -f "$tp" ] && [ -r "$tp" ] || exit 0

# One pass over the transcript's end: the qualifying lines, then only the
# fields this hook reads, each prefixed by its line number in that stream.
toks="$(tail -c "$TAIL_BYTES" "$tp" |
  grep -F -e '"type":"assistant"' -e '"subtype":"away_summary"' -e '"subtype":"compact_boundary"' |
  grep -vF -e '"isSidechain":true' -e '"model":"<synthetic>"' |
  grep -noE -e '"type":"assistant"' -e '"subtype":"away_summary"' -e '"subtype":"compact_boundary"' -e '"usage":\{' \
    -e '"timestamp":"[^"]*"' -e '"(input_tokens|cache_creation_input_tokens|cache_read_input_tokens|output_tokens|ephemeral_1h_input_tokens|ephemeral_5m_input_tokens)":[0-9]+' |
  tail -n 400)"
[ -n "$toks" ] || exit 0

# Walk the tokens line by line; keep the last assistant line's fields, the
# last away_summary time and the last compact_boundary line.
a_n=0 a_ts="" a_in="" a_cc="" a_cr="" a_out="" a_1h="" a_5m=""
w_n=0 w_ts="" b_n=0
cur=0 kind="" ts="" in_u=0 t_in="" t_cc="" t_cr="" t_out="" t_1h="" t_5m=""
finish() {
  if [ "$kind" = a ]; then
    if [ "$in_u" = 1 ]; then
      a_n=$cur a_ts=$ts a_in=$t_in a_cc=$t_cc a_cr=$t_cr a_out=$t_out a_1h=$t_1h a_5m=$t_5m
    else
      a_n=$cur a_ts="" a_in=""
    fi
  elif [ "$kind" = w ]; then
    w_n=$cur w_ts=$ts
  elif [ "$kind" = b ]; then
    b_n=$cur
  fi
}
while IFS= read -r line; do
  n="${line%%:*}"
  tok="${line#*:}"
  case "$n" in '' | *[!0-9]*) continue ;; esac
  if [ "$n" != "$cur" ]; then
    finish
    cur=$n kind="" ts="" in_u=0 t_in="" t_cc="" t_cr="" t_out="" t_1h="" t_5m=""
  fi
  case "$tok" in
    '"type":"assistant"') kind=a ;;
    '"subtype":"away_summary"') kind=w ;;
    '"subtype":"compact_boundary"') kind=b ;;
    '"usage":{') in_u=1 t_in="" t_cc="" t_cr="" t_out="" t_1h="" t_5m="" ;;
    '"timestamp":"'*) ts="${tok#\"timestamp\":\"}" ts="${ts%\"}" ;;
    *)
      [ "$in_u" = 1 ] || continue
      key="${tok%%\":*}" key="${key#\"}"
      val="${tok##*:}"
      case "$key" in
        input_tokens) [ -n "$t_in" ] || t_in=$val ;;
        cache_creation_input_tokens) [ -n "$t_cc" ] || t_cc=$val ;;
        cache_read_input_tokens) [ -n "$t_cr" ] || t_cr=$val ;;
        output_tokens) [ -n "$t_out" ] || t_out=$val ;;
        ephemeral_1h_input_tokens) [ -n "$t_1h" ] || t_1h=$val ;;
        ephemeral_5m_input_tokens) [ -n "$t_5m" ] || t_5m=$val ;;
      esac
      ;;
  esac
done <<EOF
$toks
EOF
finish

[ "$a_n" -gt 0 ] || exit 0
[ "$b_n" -gt "$a_n" ] && exit 0
[ -n "$a_ts" ] && [ -n "$a_in" ] && [ -n "$a_cc" ] && [ -n "$a_cr" ] && [ -n "$a_out" ] || exit 0
for v in "$a_in" "$a_cc" "$a_cr" "$a_out" "$a_1h" "$a_5m"; do
  [ "${#v}" -le 12 ] || exit 0
done

last="$(iso_epoch "$a_ts")" || exit 0
if [ "$w_n" -gt "$a_n" ] && [ -n "$w_ts" ]; then
  wt="$(iso_epoch "$w_ts")" && [ "$wt" -gt "$last" ] && last=$wt
fi

ctx=$((10#$a_in + 10#$a_cc + 10#$a_cr + 10#$a_out))
[ "$ctx" -ge "$BLOCK_FLOOR_TOKENS" ] || exit 0

life=3600 life_s=1h
if [ "$((10#${a_5m:-0}))" -gt 0 ] && [ "$((10#${a_1h:-0}))" -eq 0 ]; then
  life=300 life_s=5m
fi

now="$(date +%s)" || exit 0
case "$now" in '' | *[!0-9]*) exit 0 ;; esac
idle=$((now - last))
[ "$idle" -gt "$life" ] || exit 0

block=1
printf 'Compaction stopped: this conversation has been idle %s, past its %s prompt cache, so compacting would first re-read all of its ~%s tokens at full price. A fresh session costs less: run /clear, then name the work to pick up; its Handoff or Current state carries the state, so no resume note is needed (asking this conversation for one costs the same full re-read). To compact anyway: /compact %s <focus>\n' \
  "$(fmt_idle "$idle")" "$life_s" "$(fmt_k "$ctx")" "$ESCAPE_WORD" >&3
exit 2
