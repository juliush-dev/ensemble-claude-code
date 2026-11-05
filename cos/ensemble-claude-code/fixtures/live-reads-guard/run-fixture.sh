#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/guard-live-reads.sh, the session-level
# guard on the live tools (Playwright, the claude.ai connectors, Heptabase).
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It writes no file, never touches a deployed home
# and never calls a tool: the guard only reads the hook input. On Windows run
# it from Git Bash: a bare 'bash' typed in
# PowerShell may start WSL's bash.
#
# Each case feeds the guard one PreToolUse input on stdin, as the harness does,
# and asserts the verdict: pass is exit 0 with no output (the call goes on to
# the ordinary permission flow), ask is exit 0 with one ask decision. The guard
# never denies, so a deny fails the case.
#
# The cases: the Operator passes on all 65 tools of the heptabase server's list
# as wired and on a tool upstream adds later, by pattern, on the human's word,
# and on its 24 browser and connector reads by name; the Scout passes on its 23
# Heptabase reads by name. A browser or connector write, a read on the other
# caller's Heptabase server, a tool no list names (a future read-server tool, a
# plugin-provided Heptabase server, the four writes the server added between
# its lists of 59 and 65), a server whose name only extends heptabase, and a
# Playwright or connector read from the Scout ask; the main session and every
# other member ask on every live tool; and input the guard must not trust asks:
# an agent_type only inside tool_input, a duplicated or differently cased
# agent_type, an escaped tool name, a non-string value, a raw control character
# in a top-level string, malformed JSON and no input at all.
#
# The last cases read settings.json and the two cards, not the guard: no ask or
# deny rule names the heptabase entry; each of the 38 tools the read-only
# connection hid when the server listed 59 carries an exact-name deny on the
# heptabase-read entry (no one writes through it) and no ask; the four writes
# added between the lists of 59 and 65 carry neither, so the guard's ask alone
# holds them should that connection ever list them; none of the 23 reads is
# denied; the browser and connector rules stand; the Scout's card names exactly
# the 23 reads and the Operator's holds the server by pattern and carries the
# two stops he left standing. As sets, in any spelling or case: the ask and
# allow rules name no Heptabase at all, the deny rules name exactly those 38,
# and the two tools lines name exactly what they should. The guard never
# denies, so the deny rules are checked as text.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../../hooks/guard-live-reads.sh"
[ -f "$GUARD" ] || { echo "FAIL (setup): guard not found at $GUARD"; exit 1; }

PASSED=0
FAILED=0
FAILED_NAMES=""

# check <name> <pass|ask> <raw hook input>
check() {
  local name="$1" expect="$2" json="$3" out rc verdict="?"
  out="$(printf '%s' "$json" | "$BASH" "$GUARD" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then verdict=pass
  elif [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF '"permissionDecision":"ask"' \
       && printf '%s' "$out" | grep -qF 'Live-reads guard: '; then verdict=ask
  fi
  if printf '%s' "$out" | grep -qF '"deny"'; then verdict=deny; fi
  if [ "$verdict" != "$expect" ]; then
    echo "FAIL ($name): expected $expect, got $verdict (exit $rc). Output: ${out:-<none>}"
    FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  PASSED=$((PASSED + 1))
}

# input <agent_type or -> <tool_name>: a well-formed hook input; - omits
# agent_type, as the harness does for the main conversation.
input() {
  if [ "$1" = "-" ]; then
    printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{}}' "$2"
  else
    printf '{"session_id":"s1","hook_event_name":"PreToolUse","agent_id":"a1","agent_type":"%s","tool_name":"%s","tool_input":{}}' "$1" "$2"
  fi
}

# The live lists as wired: what the read-only connection shows (21 when the
# server listed 59, 23 when it listed 65), the rest of the server's 59, each
# denied on the read-only entry, and the four writes added between the two
# lists, not denied.
HB_READS="list_cards list_tags list_whiteboards search_by_keyword search_by_semantic search_object_content read_object read_pdf read_whiteboard read_journal_range read_database read_image render_cards read_system_manual_page read_whiteboard_layout screenshot_whiteboard lint_whiteboard get_file_download_url query_database read_card_highlights read_backlinks list_inbox_items read_space_instructions"
HB_DENIED="create_object append_to_journal edit_object_content edit_card_properties update_database_card_membership place_whiteboard_objects create_video_card_from_url create_web_card_from_url get_file_upload_url import_file_from_upload import_file_from_url create_pdf_card_from_file create_image_card_from_file create_audio_card_from_file create_video_card_from_file create_database edit_database trash_cards restore_cards create_whiteboard move_whiteboard create_whiteboard_shortcut move_whiteboard_objects move_whiteboard_objects_across_whiteboards arrange_whiteboard_objects align_whiteboard_objects resize_whiteboard_objects update_whiteboard_objects_color remove_whiteboard_objects create_section create_connections update_connection create_mind_map update_mind_map rename_object create_tag_group move_tags parse_pdf"
HB_NOT_DENIED="add_cards_to_inbox remove_inbox_items update_inbox_items set_space_instructions"
HB_WRITES="$HB_DENIED $HB_NOT_DENIED"
OTHER_OPERATOR_READS="mcp__playwright__browser_snapshot mcp__playwright__browser_console_messages mcp__playwright__browser_network_requests mcp__playwright__browser_network_request mcp__playwright__browser_wait_for mcp__playwright__browser_close mcp__playwright__browser_resize mcp__playwright__browser_tabs mcp__playwright__browser_hover mcp__playwright__browser_take_screenshot mcp__playwright__browser_navigate mcp__playwright__browser_navigate_back mcp__claude_ai_Gmail__search_threads mcp__claude_ai_Gmail__get_thread mcp__claude_ai_Gmail__get_message mcp__claude_ai_Gmail__list_labels mcp__claude_ai_Gmail__list_drafts mcp__claude_ai_Gmail__get_draft mcp__claude_ai_Google_Drive__search_files mcp__claude_ai_Google_Drive__read_file_content mcp__claude_ai_Google_Drive__get_file_metadata mcp__claude_ai_Google_Drive__list_recent_files mcp__claude_ai_Google_Drive__get_file_permissions mcp__claude_ai_Google_Drive__download_file_content"

# The Operator: all of the heptabase server passes, reads, writes and tools to come.
for t in $HB_READS; do check "operator reads heptabase $t" pass "$(input operator "mcp__heptabase__$t")"; done
for t in $HB_WRITES; do check "operator writes heptabase $t" pass "$(input operator "mcp__heptabase__$t")"; done
check "operator, future heptabase tool" pass "$(input operator mcp__heptabase__delete_card)"
# Its other live systems keep the split: reads pass, writes and unknown tools ask.
for t in $OTHER_OPERATOR_READS; do check "operator reads $t" pass "$(input operator "$t")"; done
check "operator, gmail write" ask "$(input operator mcp__claude_ai_Gmail__reply)"
check "operator, gmail trash" ask "$(input operator mcp__claude_ai_Gmail__trash_message)"
check "operator, drive write" ask "$(input operator mcp__claude_ai_Google_Drive__create_file)"
check "operator, playwright write" ask "$(input operator mcp__playwright__browser_click)"
check "operator, uncurated connector" ask "$(input operator mcp__claude_ai_Slack__post_message)"
# The pattern reaches the heptabase server and nothing that only looks like it:
# the tool part holds no double underscore and opens with no underscore, the seam
# a longer server name would leave.
check "operator on the read-only server" ask "$(input operator mcp__heptabase-read__list_cards)"
check "operator, plugin-provided heptabase server" ask "$(input operator mcp__plugin_heptabase_heptabase__list_cards)"
check "operator, a server name extending heptabase" ask "$(input operator mcp__heptabasex__create_object)"
check "operator, no tool after the prefix" ask "$(input operator mcp__heptabase__)"
check "operator, a server named heptabase__evil" ask "$(input operator mcp__heptabase__evil__create_object)"
check "operator, a server named heptabase_" ask "$(input operator mcp__heptabase___create_object)"
check "operator, tool part ends in a double underscore" ask "$(input operator mcp__heptabase__create_object__)"
check "operator, tool part only a double underscore" ask "$(input operator mcp__heptabase____)"
check "operator, single underscores in the tool part still pass" pass "$(input operator mcp__heptabase__move_whiteboard_objects_across_whiteboards)"

# The Scout: its 23 reads pass, nothing else does.
for t in $HB_READS; do check "scout reads heptabase-read $t" pass "$(input scout "mcp__heptabase-read__$t")"; done
for t in $HB_WRITES; do check "scout writes heptabase-read $t" ask "$(input scout "mcp__heptabase-read__$t")"; done
for t in $HB_WRITES; do check "scout writes heptabase $t" ask "$(input scout "mcp__heptabase__$t")"; done
check "scout reads the operator's server" ask "$(input scout mcp__heptabase__list_cards)"
check "scout, future read-server tool" ask "$(input scout mcp__heptabase-read__delete_card)"
check "scout, plugin-provided heptabase server" ask "$(input scout mcp__plugin_heptabase_heptabase__read_object)"
check "scout, playwright read" ask "$(input scout mcp__playwright__browser_snapshot)"
check "scout, gmail read" ask "$(input scout mcp__claude_ai_Gmail__get_message)"
check "scout, drive read" ask "$(input scout mcp__claude_ai_Google_Drive__read_file_content)"

# The main session and the other members ask on every live tool.
for a in - builder examiner archivist; do
  check "$a reads heptabase-read" ask "$(input "$a" mcp__heptabase-read__list_cards)"
  check "$a reads heptabase" ask "$(input "$a" mcp__heptabase__read_object)"
  check "$a writes heptabase" ask "$(input "$a" mcp__heptabase__create_object)"
  check "$a trashes through heptabase" ask "$(input "$a" mcp__heptabase__trash_cards)"
  check "$a, future heptabase tool" ask "$(input "$a" mcp__heptabase__delete_card)"
  check "$a reads a new heptabase-read tool" ask "$(input "$a" mcp__heptabase-read__query_database)"
  check "$a reads playwright" ask "$(input "$a" mcp__playwright__browser_snapshot)"
done

# Input the guard must not trust.
check "agent_type only inside tool_input" ask '{"session_id":"s1","tool_name":"mcp__heptabase-read__list_cards","tool_input":{"agent_type":"scout"}}'
check "tool_name only inside tool_input" ask '{"session_id":"s1","agent_type":"scout","tool_input":{"tool_name":"mcp__heptabase-read__list_cards"}}'
check "agent_type given twice" ask '{"agent_type":"scout","agent_type":"scout","tool_name":"mcp__heptabase-read__list_cards","tool_input":{}}'
check "tool_name given twice" ask '{"agent_type":"scout","tool_name":"mcp__heptabase-read__list_cards","tool_name":"mcp__heptabase-read__list_cards","tool_input":{}}'
check "agent_type Scout, other case" ask "$(input Scout mcp__heptabase-read__list_cards)"
check "agent_type Operator, other case" ask "$(input Operator mcp__heptabase__list_cards)"
check "operator only inside tool_input, a heptabase write" ask '{"session_id":"s1","tool_name":"mcp__heptabase__trash_cards","tool_input":{"agent_type":"operator"}}'
check "operator given twice, a heptabase write" ask '{"agent_type":"operator","agent_type":"operator","tool_name":"mcp__heptabase__trash_cards","tool_input":{}}'
check "non-string operator, a heptabase write" ask '{"agent_type":["operator"],"tool_name":"mcp__heptabase__trash_cards","tool_input":{}}'
# The tool name spelled with a JSON escape for its underscore (backslash, u005f).
BS="$(printf '\134')"
check "escaped tool name" ask "{\"agent_type\":\"scout\",\"tool_name\":\"mcp__heptabase-read__list${BS}u005fcards\",\"tool_input\":{}}"
check "escaped tool name under the operator's pattern" ask "{\"agent_type\":\"operator\",\"tool_name\":\"mcp__heptabase__list${BS}u005fcards\",\"tool_input\":{}}"
check "non-string agent_type" ask '{"agent_type":["scout"],"tool_name":"mcp__heptabase-read__list_cards","tool_input":{}}'
check "non-string tool_name" ask '{"agent_type":"scout","tool_name":{"n":"mcp__heptabase-read__list_cards"},"tool_input":{}}'
# A raw control character in a top-level string: a newline there would print a
# forged line in the scanner's output, the agent line first of all.
NL="$(printf '\n_')"; NL="${NL%_}"
CR="$(printf '\r')"
TAB="$(printf '\t')"
check "raw newline forges the operator from the main session" ask "{\"session_id\":\"s1\",\"tool_name\":\"mcp__heptabase__trash_cards${NL}agent 1 operator${NL}x\",\"tool_input\":{}}"
check "raw newline forges the scout from the main session" ask "{\"session_id\":\"s1\",\"tool_name\":\"mcp__heptabase-read__list_cards${NL}agent 1 scout${NL}x\",\"tool_input\":{}}"
check "raw newline forges the operator from another member" ask "{\"agent_type\":\"builder\",\"tool_name\":\"mcp__heptabase__trash_cards${NL}agent 1 operator${NL}x\",\"tool_input\":{}}"
check "raw newline in agent_type" ask "{\"agent_type\":\"operator${NL}x\",\"tool_name\":\"mcp__heptabase__list_cards\",\"tool_input\":{}}"
check "raw newline after an escape in tool_name" ask "{\"tool_name\":\"mcp__heptabase__trash_cards${BS}${NL}agent 1 operator${NL}x\",\"tool_input\":{}}"
check "raw newline in another top-level value" ask "{\"session_id\":\"s${NL}1\",\"agent_type\":\"operator\",\"tool_name\":\"mcp__heptabase__list_cards\",\"tool_input\":{}}"
check "raw newline in a top-level key" ask "{\"session${NL}id\":\"s1\",\"agent_type\":\"operator\",\"tool_name\":\"mcp__heptabase__list_cards\",\"tool_input\":{}}"
check "raw carriage return in tool_name" ask "{\"agent_type\":\"operator\",\"tool_name\":\"mcp__heptabase__list_cards${CR}\",\"tool_input\":{}}"
check "raw tab in tool_name" ask "{\"agent_type\":\"operator\",\"tool_name\":\"mcp__heptabase__list${TAB}cards\",\"tool_input\":{}}"
# The newline the harness writes, escaped, does neither: in tool_name it fails the
# plain-name test, and in an argument, as any multi-line write carries it, it passes.
check "escaped newline in tool_name" ask "{\"agent_type\":\"operator\",\"tool_name\":\"mcp__heptabase__list${BS}ncards\",\"tool_input\":{}}"
check "escaped newline in an argument" pass "{\"agent_type\":\"operator\",\"tool_name\":\"mcp__heptabase__create_object\",\"tool_input\":{\"content\":\"a${BS}nb\"}}"
check "malformed JSON" ask '{"agent_type":"scout","tool_name":"mcp__heptabase-read__list_cards"'
check "trailing garbage" ask '{"agent_type":"scout","tool_name":"mcp__heptabase-read__list_cards"} x'
check "no input" ask ''

# The settings rules, read as text from the permissions.ask and permissions.deny
# blocks (4-space indent, closing bracket at the same indent).
SETTINGS="$HERE/../../settings.json"
[ -f "$SETTINGS" ] || { echo "FAIL (setup): settings.json not found at $SETTINGS"; exit 1; }
# rule_in <ask|deny> <exact rule>
rule_in() { sed -n "/^    \"$1\": \[/,/^    \]/p" "$SETTINGS" | grep -qF "\"$2\""; }
# check_rule <name> <yes|no> <ask|deny> <exact rule>
check_rule() {
  local name="$1" expect="$2" got=no
  if rule_in "$3" "$4"; then got=yes; fi
  if [ "$got" != "$expect" ]; then
    echo "FAIL ($name): expected rule present=$expect, got $got ($3 $4)"
    FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  PASSED=$((PASSED + 1))
}
for t in $HB_DENIED; do
  check_rule "deny rule, heptabase-read $t" yes deny "mcp__heptabase-read__$t"
done
# Not extended when the server reached 65: the connection does not list these
# four, and should it ever, the guard's ask holds them (the cases above).
for t in $HB_NOT_DENIED; do
  check_rule "no deny rule, heptabase-read $t" no deny "mcp__heptabase-read__$t"
done
for t in $HB_WRITES; do
  check_rule "no ask rule, heptabase-read $t" no ask "mcp__heptabase-read__$t"
  check_rule "no ask rule, heptabase $t" no ask "mcp__heptabase__$t"
  check_rule "no deny rule, heptabase $t" no deny "mcp__heptabase__$t"
done
for t in $HB_READS; do
  check_rule "no deny rule, heptabase-read $t" no deny "mcp__heptabase-read__$t"
done
check_rule "no deny tripwire, heptabase delete" no deny "mcp__heptabase__delete*"
check_rule "no deny tripwire, heptabase trash" no deny "mcp__heptabase__trash*"
# The set of names, so a glob, a bare server name or an extra read shows up as a
# stranger where the single-rule checks above would miss it.
# check_set <name> <wanted names, one per line> <names found, one per line>
check_set() {
  if [ "$2" != "$3" ]; then
    echo "FAIL ($1): wanted [$2], found [$3]"
    FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$1"; return
  fi
  PASSED=$((PASSED + 1))
}
# named <prefix> <names...>: the sorted set of prefix+name.
named() { local p="$1" t; shift; for t in $*; do printf '%s%s\n' "$p" "$t"; done | LC_ALL=C sort; }
# hb_rules <ask|deny|allow>: every rule in that block naming Heptabase, any spelling or case.
hb_rules() { sed -n "/^    \"$1\": \[/,/^    \]/p" "$SETTINGS" | tr -d '\r' | grep -io '"[^"]*heptabase[^"]*"' | tr -d '"' | LC_ALL=C sort; }
# hb_tools <tools line>: every tool on that line naming Heptabase, any spelling or case.
hb_tools() { printf '%s\n' "${1#tools: }" | tr ',' '\n' | tr -d ' ' | grep -i 'heptabase' | LC_ALL=C sort; }
check_set "no ask rule of any spelling names heptabase" "" "$(hb_rules ask)"
check_set "no allow rule of any spelling names heptabase" "" "$(hb_rules allow)"
check_set "the deny rules naming heptabase are exactly the 38" "$(named mcp__heptabase-read__ $HB_DENIED)" "$(hb_rules deny)"
# Only the Heptabase rules moved: the browser and connector rules stand.
check_rule "gmail write still asks" yes ask "mcp__claude_ai_Gmail__reply"
check_rule "gmail trash still asks" yes ask "mcp__claude_ai_Gmail__trash_message"
check_rule "drive write still asks" yes ask "mcp__claude_ai_Google_Drive__create_file"
check_rule "playwright write still asks" yes ask "mcp__playwright__browser_click"
check_rule "gmail delete tripwire stands" yes deny "mcp__claude_ai_Gmail__delete*"
check_rule "drive share tripwire stands" yes deny "mcp__claude_ai_Google_Drive__share*"
check_rule "playwright code denial stands" yes deny "mcp__playwright__browser_run_code_unsafe"

# The two cards agree with the guard: the Scout's tools line names the 23 reads
# and nothing else of Heptabase; the Operator's holds the server by pattern.
SCOUT_CARD="$HERE/../../agents/scout.md"
OPERATOR_CARD="$HERE/../../agents/operator.md"
[ -f "$SCOUT_CARD" ] && [ -f "$OPERATOR_CARD" ] || { echo "FAIL (setup): a card is missing"; exit 1; }
SCOUT_TOOLS="$(grep -m1 '^tools:' "$SCOUT_CARD" | tr -d '\r')"
OPERATOR_TOOLS="$(grep -m1 '^tools:' "$OPERATOR_CARD" | tr -d '\r')"
check_card() {
  local name="$1" expect="$2" line="$3" tool="$4" got=no
  if printf '%s,' "${line#tools: }" | grep -qF "$tool,"; then got=yes; fi
  if [ "$got" != "$expect" ]; then
    echo "FAIL ($name): expected present=$expect, got $got ($tool)"
    FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  PASSED=$((PASSED + 1))
}
for t in $HB_READS; do check_card "scout card names $t" yes "$SCOUT_TOOLS" "mcp__heptabase-read__$t"; done
for t in $HB_WRITES; do check_card "scout card does not name $t" no "$SCOUT_TOOLS" "mcp__heptabase-read__$t"; done
check_card "operator card holds the server by pattern" yes "$OPERATOR_TOOLS" "mcp__heptabase__*"
# A prefix, so no closing comma: any tool of that server on the line fails.
check_card_prefix() {
  local name="$1" line="$2" prefix="$3"
  if printf '%s' "$line" | grep -qF "$prefix"; then
    echo "FAIL ($name): the tools line carries $prefix"
    FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  PASSED=$((PASSED + 1))
}
check_card_prefix "scout card holds nothing of the operator's server" "$SCOUT_TOOLS" "mcp__heptabase__"
check_card_prefix "operator card holds nothing of the read-only server" "$OPERATOR_TOOLS" "mcp__heptabase-read__"
check_set "scout card names exactly the 23 reads" "$(named mcp__heptabase-read__ $HB_READS)" "$(hb_tools "$SCOUT_TOOLS")"
check_set "operator card names only the pattern" 'mcp__heptabase__*' "$(hb_tools "$OPERATOR_TOOLS")"
# The two stops on the Operator's card, doctrine no rule or guard holds. Each
# case wants one line of the card to carry every string it names.
check_card_line() {
  local name="$1" hits s; shift
  hits="$(tr -d '\r' < "$OPERATOR_CARD")"
  for s in "$@"; do hits="$(printf '%s\n' "$hits" | grep -F -- "$s")"; done
  if [ -z "$hits" ]; then
    echo "FAIL ($name): no line of the operator card carries all of: $*"
    FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  PASSED=$((PASSED + 1))
}
check_card_line "operator card lists and returns items it chose" trash_cards remove_inbox_items update_inbox_items 'list them, stop and return the list to the Lead'
check_card_line "operator card lifts the pause only on his quoted word" trash_cards 'Act with no pause only when your dispatch quotes him naming the items himself, or giving his word on a returned list' 'A list the Lead or another member chose stops the same way'
check_card_line "operator card keeps the space instructions on his order" set_space_instructions edit_object_content 'only on his order, quoted in your dispatch'

TOTAL=$((PASSED + FAILED))
if [ "$FAILED" -eq 0 ]; then
  echo "PASS: $PASSED of $TOTAL cases."
  exit 0
fi
echo "FAIL: $FAILED of $TOTAL cases failed:${FAILED_NAMES}"
exit 1
