#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - session-level PreToolUse guard on the live
# tools: matcher mcp__playwright__.*|mcp__claude_ai_.*|mcp__heptabase.*|
# mcp__plugin_heptabase_.* in settings.json.
# ASCII-only, LF line endings (the subtree's *.sh eol=lf attribute).
#
# Reads flow for the Operator, and Heptabase reads for the Scout too; every
# tool of the heptabase server flows for the Operator, writes included, on the
# human's word; everything else asks. A call passes silently only
# when the tool is on the calling agent's own list below: the Operator
# (top-level agent_type exactly "operator") has the browser and connector reads
# by exact name and the heptabase server by pattern; the Scout (exactly
# "scout") has only the Heptabase reads of the heptabase-read server, the
# read-only connection. A silent pass is not an approval: the call goes on to
# the ordinary permission flow (in auto mode, the classifier), and this guard
# adds no allow. Every other call is downgraded to an explicit ask: any other
# write, any other tool the lists do not name (a tool upstream added later, a
# connector no curation has admitted), the same call from the main session or
# any other agent, and input this guard cannot parse. Never a hard block: the
# human may approve at the prompt.
#
# Fail-closed once it runs. Every path ends in the ask but three silent exits,
# the Scout's list, the Operator's Heptabase pattern and the Operator's list,
# and each is reached only after the input has scanned as one top-level JSON
# object whose top-level tool_name and agent_type each appear exactly once, as
# strings, with no raw control character in any top-level string, so a value
# cannot forge a line of the scanner's output, and match. The scanner holds the
# top-level grammar; below it it tracks strings and brackets only and validates
# nothing else, which is enough because nothing there is ever read. A guard that
# does not run asks nothing. The exact-name ask rules on every known browser and
# connector write in settings.json stay as a second layer, so such a write
# still asks if this guard ever fails to run. Heptabase has no ask rule, so
# this guard is the only mechanical ask there.
#
# Top-level keys only. The two fields are read by a small JSON scanner (awk)
# that tracks nesting and string state, so an "agent_type" or "tool_name" key
# inside tool_input (arguments the model writes, which injected content can
# shape) is never mistaken for the harness's own field. The harness supplies
# agent_type for subagent calls (the agent file's name), and omits it in the
# ordinary main conversation; it is ALSO present on the main thread of a
# session started with --agent (without agent_id) - agent_id, not agent_type
# alone, is what tells a subagent call from a main-thread call. Benign here:
# a `claude --agent operator` main thread IS the Operator, so the read lift
# still fits it, and this COS never launches with --agent. The same holds for
# "scout": the lift keys on the name string alone, so any agent file named
# scout gets the Heptabase reads, never a write.
#
# The read list re-verifies against the enumerated tool inventory on every
# version move and every re-enumeration, together with the ask rules.

set -u

ask() {
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Live-reads guard: $1 Reads flow for the Operator, as does all its Heptabase work, and Heptabase reads for the Scout; every other live call asks, and the prompt is the gate."}}
JSON
  exit 0
}

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || ask "no tool input reached the guard."

# The scanner prints three lines:
#   ok | bad                 one well-formed top-level JSON object, or not
#   tool <count> <value>     top-level tool_name keys seen, and the value
#   agent <count> <value>    top-level agent_type keys seen, and the value
# A value is the raw JSON string content, escapes left as written, so an
# escaped spelling never matches a plain name. A non-string value is recorded
# as a marker that matches nothing. A raw control character in a top-level
# string makes the input bad: JSON forbids it, the harness writes it escaped,
# and a raw newline in a value would otherwise print a line of its own here.
parsed="$(printf '%s' "$input" | LC_ALL=C awk '
BEGIN { RS = "\001" }
{ s = s $0 }
END {
  bad = (NR > 1)
  n = length(s)
  sp = 0              # bracket stack depth; the top-level object is depth 1
  started = 0; ended = 0
  instr = 0; esc = 0; tok = ""
  inlit = 0
  expect = "key"      # depth-1 grammar: key, colon, value, comma
  strrole = ""        # role of the depth-1 string being read: key or value
  curkey = ""; nkeys = 0
  nt = 0; na = 0; tv = ""; av = ""
  for (i = 1; i <= n && !bad; i++) {
    c = substr(s, i, 1)
    if (instr) {
      if (sp == 1 && c ~ /[\001-\037]/) { bad = 1; break }
      if (esc) { esc = 0; if (sp == 1) tok = tok c; continue }
      if (c == "\\") { esc = 1; if (sp == 1) tok = tok c; continue }
      if (c != "\"") { if (sp == 1) tok = tok c; continue }
      instr = 0
      if (sp == 1) {
        if (strrole == "key") { curkey = tok; nkeys++; expect = "colon" }
        else {
          if (curkey == "tool_name") tv = tok
          if (curkey == "agent_type") av = tok
          expect = "comma"
        }
      }
      tok = ""
      continue
    }
    if (inlit) {
      if (c ~ /[A-Za-z0-9.+-]/) continue
      inlit = 0
    }
    if (c == " " || c == "\t" || c == "\r" || c == "\n") continue
    if (ended) { bad = 1; break }
    if (!started) {
      if (c != "{") { bad = 1; break }
      started = 1; sp = 1; stack[1] = "{"; expect = "key"
      continue
    }
    if (sp == 1) {
      if (c == "\"") {
        if (expect == "key") strrole = "key"
        else if (expect == "value") strrole = "value"
        else { bad = 1; break }
        instr = 1; tok = ""
        continue
      }
      if (c == ":") {
        if (expect != "colon") { bad = 1; break }
        if (curkey == "tool_name") nt++
        if (curkey == "agent_type") na++
        expect = "value"
        continue
      }
      if (c == ",") {
        if (expect != "comma") { bad = 1; break }
        expect = "key"
        continue
      }
      if (c == "}") {
        if (!(expect == "comma" || (expect == "key" && nkeys == 0))) { bad = 1; break }
        sp = 0; ended = 1
        continue
      }
      if (c == "{" || c == "[") {
        if (expect != "value") { bad = 1; break }
        if (curkey == "tool_name") tv = "\002nonstring"
        if (curkey == "agent_type") av = "\002nonstring"
        sp++; stack[sp] = c
        continue
      }
      if (c ~ /[A-Za-z0-9.+-]/) {
        if (expect != "value") { bad = 1; break }
        if (curkey == "tool_name") tv = "\002nonstring"
        if (curkey == "agent_type") av = "\002nonstring"
        inlit = 1; expect = "comma"
        continue
      }
      bad = 1; break
    }
    # Nested (depth 2 and below): track strings and brackets only.
    if (c == "\"") { instr = 1; tok = ""; continue }
    if (c == "{" || c == "[") { sp++; stack[sp] = c; continue }
    if (c == "}" || c == "]") {
      if ((c == "}" && stack[sp] != "{") || (c == "]" && stack[sp] != "[")) { bad = 1; break }
      sp--
      if (sp == 1) expect = "comma"
      continue
    }
  }
  if (instr || !started || !ended || sp != 0) bad = 1
  print (bad ? "bad" : "ok")
  print "tool " nt " " tv
  print "agent " na " " av
}' 2>/dev/null)" || ask "the tool input could not be scanned."

status="$(printf '%s\n' "$parsed" | sed -n '1p')"
[ "$status" = "ok" ] || ask "the tool input is not one well-formed JSON object."

tool_line="$(printf '%s\n' "$parsed" | sed -n '2p')"
agent_line="$(printf '%s\n' "$parsed" | sed -n '3p')"

case "$tool_line" in
  "tool 1 "*) tool="${tool_line#tool 1 }" ;;
  *) ask "the tool name is missing or given more than once." ;;
esac
case "$agent_line" in
  "agent 1 "*) agent="${agent_line#agent 1 }" ;;
  *) ask "the call does not come from the Operator or the Scout." ;;
esac

# The Scout's read list: the 23 Heptabase read tools the heptabase-read server
# (the read-only connection) listed when the server listed 65 tools, exact
# names. Nothing else passes for it, the four writes the server added between
# its lists of 59 and 65 included.
if [ "$agent" = "scout" ]; then
  case "$tool" in
    mcp__heptabase-read__list_cards|\
    mcp__heptabase-read__list_tags|\
    mcp__heptabase-read__list_whiteboards|\
    mcp__heptabase-read__search_by_keyword|\
    mcp__heptabase-read__search_by_semantic|\
    mcp__heptabase-read__search_object_content|\
    mcp__heptabase-read__read_object|\
    mcp__heptabase-read__read_pdf|\
    mcp__heptabase-read__read_whiteboard|\
    mcp__heptabase-read__read_journal_range|\
    mcp__heptabase-read__read_database|\
    mcp__heptabase-read__read_image|\
    mcp__heptabase-read__render_cards|\
    mcp__heptabase-read__read_system_manual_page|\
    mcp__heptabase-read__read_whiteboard_layout|\
    mcp__heptabase-read__screenshot_whiteboard|\
    mcp__heptabase-read__lint_whiteboard|\
    mcp__heptabase-read__get_file_download_url|\
    mcp__heptabase-read__query_database|\
    mcp__heptabase-read__read_card_highlights|\
    mcp__heptabase-read__read_backlinks|\
    mcp__heptabase-read__list_inbox_items|\
    mcp__heptabase-read__read_space_instructions)
      exit 0 ;;
  esac
  ask "this tool is not on the Scout's read list (only the Heptabase reads of the read-only connection are)."
fi
[ "$agent" = "operator" ] || ask "the call does not come from the Operator or the Scout."

# The Operator's Heptabase: every tool of the heptabase server passes, on the
# human's word. A pattern, since the hosted toolset moves without a release.
# The rest of the name must be plain, so an escaped spelling still
# asks; neither heptabase-read nor a plugin-provided server matches. It may not
# hold a double underscore or open with an underscore, the seam between a server
# name and a tool name, so a server named heptabase__evil or heptabase_ asks too.
# No tool the server lists needs either.
case "$tool" in
  mcp__heptabase__*[!A-Za-z0-9_-]*|mcp__heptabase__*__*|mcp__heptabase___*) ;;
  mcp__heptabase__?*) exit 0 ;;
esac

# The Operator's read list: 24 read-shaped browser and connector tools, exact
# names. Anything not named asks.
case "$tool" in
  mcp__playwright__browser_snapshot|\
  mcp__playwright__browser_console_messages|\
  mcp__playwright__browser_network_requests|\
  mcp__playwright__browser_network_request|\
  mcp__playwright__browser_wait_for|\
  mcp__playwright__browser_close|\
  mcp__playwright__browser_resize|\
  mcp__playwright__browser_tabs|\
  mcp__playwright__browser_hover|\
  mcp__playwright__browser_take_screenshot|\
  mcp__playwright__browser_navigate|\
  mcp__playwright__browser_navigate_back|\
  mcp__claude_ai_Gmail__search_threads|\
  mcp__claude_ai_Gmail__get_thread|\
  mcp__claude_ai_Gmail__get_message|\
  mcp__claude_ai_Gmail__list_labels|\
  mcp__claude_ai_Gmail__list_drafts|\
  mcp__claude_ai_Gmail__get_draft|\
  mcp__claude_ai_Google_Drive__search_files|\
  mcp__claude_ai_Google_Drive__read_file_content|\
  mcp__claude_ai_Google_Drive__get_file_metadata|\
  mcp__claude_ai_Google_Drive__list_recent_files|\
  mcp__claude_ai_Google_Drive__get_file_permissions|\
  mcp__claude_ai_Google_Drive__download_file_content)
    exit 0 ;;
esac

ask "this tool is not on the Operator's read list (a write, or a tool no curation has classed)."
