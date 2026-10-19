#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - the here.now gate: a session-level
# PreToolUse guard on Bash|PowerShell, for every caller.
# ASCII-only, LF line endings (the subtree's *.sh eol=lf attribute).
#
# here.now site and Drive writes are live external writes, a hard human gate;
# a publish is owner-only by default (the kit locks and checks it), a public
# one is the human's explicit word. The Operator works here.now through its
# kit tools/herenow.sh; this guard holds the Operator's shell to that kit, lets
# the reads through, lets an ordered write through only when its local source
# lies inside the session's root, and puts every other write in front of the
# human. Two rules, keyed on the hook input's top-level agent_type:
#
#   THE OPERATOR (agent_type exactly "operator") - an ALLOWLIST. These forms
#   pass or ask, everything else is blocked (exit 2) with the forms printed
#   (K is "$CLAUDE_CONFIG_DIR/tools/herenow.sh"):
#     K check; K manifest "<path>"                                  pass
#     K site-ls; K site-files "<slug>"; K site-cat "<slug>" "<path>" pass
#     K drive-ls; K drive-ls "<drive>" ["<prefix>"];
#     K drive-cat "<drive>" "<path>"                                pass
#     K publish "<path>" [--slug <slug>] [--title "<text>"]
#         [--description "<text>"] --ordered, the target inside the root  pass
#     K publish ... --ordered, outside the root or the check unmade   ask
#     K publish ... (no flag)                                        ask
#     K publish ... --public                                         ask
#     K drive-put "<drive>" "<path>" --from "<local-file>" --ordered,
#         the local file inside the root                             pass
#     K drive-put ... otherwise                                      ask
#   --ordered with --public, or any option twice, blocks. --ordered means the
#   Operator's dispatch quotes the human's order for this act; the gate cannot
#   see the order, so the flag is honor-based, bounded by the root check here,
#   the kit's owner-only sequence and refusals, and the classifier. A pass is
#   not an approval: the call goes on to the ordinary permission flow (in auto
#   mode, the classifier). An ask names the act (the target, new site or slug;
#   the drive, path and local file); when the local source lies outside the
#   session's root and its grants, or the check could not be made, the reason
#   says so. That judgment is delegated to guard-archivist-paths.sh
#   main-session, as the OpenKnowledge guard delegates its targets, so one path
#   law judges every surface; the delegate's own exemptions (the session's
#   scratchpad, a session grant) count as inside. A root the gate cannot know
#   (neither CLAUDE_PROJECT_DIR nor the input's cwd) leaves the check unmade,
#   since the delegate passes what it cannot place. A shell with one purpose
#   takes an allowlist (the Scout guard's header says why); the Operator's
#   shell has one purpose. A PowerShell call from the Operator is blocked: its
#   shell is Bash.
#
#   ANY OTHER CALLER (agent_type absent, ordinarily the bare main session, or
#   present but not "operator", another member) - a shape gate. A command
#   carrying a here.now publish, site, Drive or credential shape anywhere in
#   its text asks: publish.sh, drive.sh, here.now/api, HERENOW_API_KEY,
#   HERENOW_DRIVE_TOKEN, .herenow/credentials, "herenow.sh publish",
#   "herenow.sh site-" or "herenow.sh drive-" (matched without regard to case,
#   quotes or the slash direction). here.now publishing, site and Drive work
#   dispatch to the Operator through its kit, and a key file is never read by
#   hand. The kit's check and manifest, which never read the key or call the
#   network, and a keyless curl of a site's own address pass; everything else
#   passes untouched. Ask, not block, so the human's own lived command still
#   runs on his prompt.
#
# The Operator's accepted forms, word by word (single or repeated spaces
# between words; nothing else may appear):
#   - the kit is named as "$CLAUDE_CONFIG_DIR/tools/herenow.sh", quoted or not,
#     the variable name in exactly that case, or by the config directory's own
#     expanded path in any of the forms this host spells it (quoted; unquoted
#     only when it has no space; compared case-insensitively on Windows). This
#     kit-word block is copied from hooks/guard-scout-bash.sh, the kit's name
#     aside; change both together;
#   - a local path (publish's target, drive-put's --from, manifest's path) is
#     double-quoted, non-empty, with no $, backtick or double quote inside, no
#     \\ pair and no trailing backslash (so bash reads the same string this
#     guard reads);
#   - a site or Drive path (site-cat's, drive-cat's, drive-put's, a drive-ls
#     prefix) is double-quoted, non-empty, with no $, backtick, double quote or
#     backslash, no leading / and no .. segment;
#   - a drive name is double-quoted, non-empty, with no $, backtick, double
#     quote or backslash, and does not start with -;
#   - a slug (site-files, site-cat, --slug) takes [a-z0-9-]+, bare or
#     double-quoted; --title and --description take a double-quoted value with
#     no $, backtick, double quote or backslash; each option at most once.
#     Every other flag is blocked (the kit refuses them too, each with its harm
#     named).
# JSON escapes other than \" and \\ (a newline, a tab, \u...) and any control
# character block.
#
# Top-level keys only. agent_type, tool_name, cwd and session_id are read by
# the live-reads guard's awk scanner (extended to two more keys), which tracks
# nesting and string state, so a key inside tool_input cannot pose as the
# harness's own field. A main-session input that never mentions agent_type
# skips the scanner: whatever it holds, the caller is not the Operator. The
# command is read with the push gate's key-scoped extraction. agent_type is
# also present on the main thread of a session started with --agent (without
# agent_id); agent_id, not agent_type alone, is what tells a subagent call
# from a main-thread call. Benign here: this COS never launches with --agent,
# and a --agent operator main thread would correctly read as the Operator.
#
# Fail direction: an unreadable command from the Operator blocks; from anyone
# else it asks; input whose caller cannot be told asks. A command hook that
# crashes, exits without a decision or outruns its timeout does not block: the
# call goes on through the ordinary permission flow (hooks reference, Timeouts
# and Other exit codes). So every way out but the three verdicts below
# (pass, ask, block) is caught by an EXIT trap and turned into a block for the
# Operator and an ask for everyone else, and the settings.json entry sets an
# explicit timeout. An error inside a compound command does not exit at all:
# bash abandons that command and goes on with the next, so a guard line after
# each branch that could fall through turns that into a verdict too. A
# delegate that fails leaves the write asking, its reason saying the root
# check did not run. What no trap covers: a hook that never
# starts (bash missing), a run the harness kills at its timeout, and a DECIDED
# made readonly before the gate starts (BASH_ENV or a startup file), which
# every verdict assigns, so the run exits 1 with none; the card's
# confirm-first is then the remaining carrier, and the classifier.
#
# Still string-matching, like every house guard: the Bash tool hands this guard
# the command text and bash parses it after. The Operator's forms are kept
# narrow enough that the two readings cannot differ.

set -uf

DECIDED=0
caller="unknown"   # operator | other | unknown

FORMS='  "$CLAUDE_CONFIG_DIR/tools/herenow.sh" check
  "$CLAUDE_CONFIG_DIR/tools/herenow.sh" manifest "<path>"
  "$CLAUDE_CONFIG_DIR/tools/herenow.sh" site-ls
  "$CLAUDE_CONFIG_DIR/tools/herenow.sh" site-files "<slug>"
  "$CLAUDE_CONFIG_DIR/tools/herenow.sh" site-cat "<slug>" "<path>"
  "$CLAUDE_CONFIG_DIR/tools/herenow.sh" drive-ls
  "$CLAUDE_CONFIG_DIR/tools/herenow.sh" drive-ls "<drive>" ["<prefix>"]
  "$CLAUDE_CONFIG_DIR/tools/herenow.sh" drive-cat "<drive>" "<path>"
  "$CLAUDE_CONFIG_DIR/tools/herenow.sh" publish "<path>" [--slug <slug>] [--title "<text>"] [--description "<text>"] [--ordered | --public]
  "$CLAUDE_CONFIG_DIR/tools/herenow.sh" drive-put "<drive>" "<path>" --from "<local-file>" [--ordered]'

block() {
  DECIDED=1
  {
    echo "here.now gate: blocked ($1)."
    echo "Your shell runs one command, the here.now kit, in these forms:"
    echo "$FORMS"
    echo "Conform to one of those forms or stop and report, never reshape around it."
  } >&2
  exit 2
}
ask() {
  DECIDED=1
  # No temporary: a name the ask assigns could be taken (readonly) and cost it.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"here.now gate: %s The prompt is the gate."}}\n' \
    "$(printf '%s' "$1" | tr '\\"' "/'" | tr -d '\000-\037')"
  exit 0
}
pass() { DECIDED=1; exit 0; }
# The trap reads its two variables with defaults, so a readonly name left
# unset cannot trip these reads under set -u.
on_exit() {
  [ "${DECIDED:-0}" = 1 ] && exit "$1"
  if [ "${caller:-unknown}" = operator ]; then
    block "the gate stopped before reaching a verdict (exit status $1), and an unfinished check never passes"
  fi
  ask "the gate stopped before reaching a verdict (exit status $1), and an unfinished check never passes."
}
trap 'on_exit $?' EXIT
trap 'exit 143' HUP INT TERM

OTHER_REASON="here.now publishing, site and Drive work dispatch to the Operator through its kit; a key file is never read by hand."

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || ask "no tool input reached the gate."

# --- the caller -------------------------------------------------------------------
# Scanner output: ok|bad, then "tool <count> <raw value>", "agent ...", "cwd ...",
# "sid ..." for the top-level keys tool_name, agent_type, cwd and session_id. A
# value is the raw JSON string text, escapes as written; a non-string value is a
# marker that matches nothing.
tool=""; cwd_raw=""; sid_raw=""
case "$input" in
  *agent_type*)
    parsed="$(printf '%s' "$input" | LC_ALL=C awk '
BEGIN { RS = "\001" }
{ s = s $0 }
END {
  bad = (NR > 1)
  n = length(s)
  sp = 0
  started = 0; ended = 0
  instr = 0; esc = 0; tok = ""
  inlit = 0
  expect = "key"
  strrole = ""
  curkey = ""; nkeys = 0
  nt = 0; na = 0; nc = 0; ns = 0; tv = ""; av = ""; cv = ""; sv = ""
  for (i = 1; i <= n && !bad; i++) {
    c = substr(s, i, 1)
    if (instr) {
      if (esc) { esc = 0; if (sp == 1) tok = tok c; continue }
      if (c == "\\") { esc = 1; if (sp == 1) tok = tok c; continue }
      if (c != "\"") { if (sp == 1) tok = tok c; continue }
      instr = 0
      if (sp == 1) {
        if (strrole == "key") { curkey = tok; nkeys++; expect = "colon" }
        else {
          if (curkey == "tool_name") tv = tok
          if (curkey == "agent_type") av = tok
          if (curkey == "cwd") cv = tok
          if (curkey == "session_id") sv = tok
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
        if (curkey == "cwd") nc++
        if (curkey == "session_id") ns++
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
        if (curkey == "cwd") cv = "\002nonstring"
        if (curkey == "session_id") sv = "\002nonstring"
        sp++; stack[sp] = c
        continue
      }
      if (c ~ /[A-Za-z0-9.+-]/) {
        if (expect != "value") { bad = 1; break }
        if (curkey == "tool_name") tv = "\002nonstring"
        if (curkey == "agent_type") av = "\002nonstring"
        if (curkey == "cwd") cv = "\002nonstring"
        if (curkey == "session_id") sv = "\002nonstring"
        inlit = 1; expect = "comma"
        continue
      }
      bad = 1; break
    }
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
  print "cwd " nc " " cv
  print "sid " ns " " sv
}' 2>/dev/null)" || ask "the tool input could not be scanned, so the caller cannot be told."
    [ "$(printf '%s\n' "$parsed" | sed -n '1p')" = "ok" ] \
      || ask "the tool input is not one well-formed JSON object, so the caller cannot be told."
    _tl="$(printf '%s\n' "$parsed" | sed -n '2p')"
    _al="$(printf '%s\n' "$parsed" | sed -n '3p')"
    _cl="$(printf '%s\n' "$parsed" | sed -n '4p')"
    _sl="$(printf '%s\n' "$parsed" | sed -n '5p')"
    case "$_tl" in "tool 1 "*) tool="${_tl#tool 1 }" ;; esac
    case "$_cl" in "cwd 1 "*) cwd_raw="${_cl#cwd 1 }" ;; esac
    case "$_sl" in "sid 1 "*) sid_raw="${_sl#sid 1 }" ;; esac
    case "$_al" in
      "agent 0 "*) caller=other ;;
      "agent 1 operator") caller=operator ;;
      "agent 1 "*) caller=other ;;
      *) ask "the hook input carries agent_type more than once, so the caller cannot be told." ;;
    esac
    ;;
  *) caller=other ;;
esac
# A failed assignment above (parsed, _tl to _sl, tool, cwd_raw, sid_raw)
# abandons the whole case with the caller still unknown; it must not fall
# through to the other-caller gate below.
[ "$caller" != unknown ] || ask "the caller could not be told, and an unfinished check never passes."

# --- the command --------------------------------------------------------------------
# Key-scoped, non-greedy capture of the command value (the push gate's
# extraction): stop at the value's own closing quote, a backslash-escaped quote
# counting as interior text, so no other field bleeds into the string.
raw="$(printf '%s' "$input" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1)"

# --- any other caller: the shape gate -------------------------------------------------
if [ "$caller" != operator ]; then
  [ -n "$raw" ] || ask "the command could not be isolated from the tool input; $OTHER_REASON"
  # Decode the escapes (an escaped backslash first), fold case, drop quotes,
  # turn backslashes into slashes and whitespace runs into one space.
  norm="${raw//\\\\/$'\001'}"
  norm="${norm//\\\"/\"}"
  norm="${norm//\\n/ }"; norm="${norm//\\r/ }"; norm="${norm//\\t/ }"
  norm="${norm//$'\001'/\\}"
  norm="$(printf '%s' "$norm" | tr '[:upper:]' '[:lower:]' | tr -d "\"'" | tr '\\' '/' | tr -s ' \t' '  ')"
  case "$norm" in
    *publish.sh*|*drive.sh*|*here.now/api*|*herenow_api_key*|*herenow_drive_token*|*.herenow/credentials*|\
    *'herenow.sh publish'*|*'herenow.sh site-'*|*'herenow.sh drive-'*)
      ask "this command carries a here.now publish, site, Drive or key shape; $OTHER_REASON" ;;
  esac
  pass
fi

# --- the Operator: the allowlist ------------------------------------------------------
# Reached only by the Operator. An error inside a compound command (a failed
# assignment, for one) abandons that command without exiting, and bash goes on
# with the next one; so where a block could fall through, a guard line checks
# the gate is where it means to be.
[ "$caller" = operator ] || ask "the gate lost its place after an internal error, and an unfinished check never passes."
[ "$tool" = "Bash" ] || block "a ${tool:-unnamed} call; the Operator's shell is Bash, and it runs the here.now kit only"
[ -n "$raw" ] || block "no command could be read from the tool input"

printf '%s' "$raw" | LC_ALL=C grep -q '[[:cntrl:]]' && block "a control character in the command"
# JSON escapes: only \" and \\ belong to the accepted forms. \n, \t, \r, \u...
# would decode to a newline, a tab or an arbitrary character.
_rest_esc="${raw//\\\\/}"
case "$_rest_esc" in
  *\\[!\"]*|*\\) block "a newline, tab or other escaped character in the command" ;;
esac
cmd="${raw//\\\\/$'\001'}"
cmd="${cmd//\\\"/\"}"
cmd="${cmd//$'\001'/\\}"

# Trim the ends.
cmd="${cmd#"${cmd%%[! ]*}"}"
cmd="${cmd%"${cmd##*[! ]}"}"

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
norm_root() { printf '%s' "$1" | tr '\\' '/' | sed 's:/*$::'; }
# The drive form of a mixed Windows path (C:/x -> /c/x), built from cygpath's
# own drive prefix: "cygpath -u" alone renders a mounted folder by its mount
# (Git Bash mounts the user's Temp at /tmp), never as /c/...
drive_unix() {
  case "$1" in
    [A-Za-z]:/*)
      _dp="$(cygpath -u "${1%%/*}/" 2>/dev/null)"
      [ -n "$_dp" ] && printf '%s' "${_dp%/}/${1#*:/}" ;;
  esac
}

win_host=0
{ [ -n "${LOCALAPPDATA:-}" ] || [ -n "${TEMP:-}" ] || [ -n "${TMP:-}" ]; } && win_host=1

# --- the kit word ---------------------------------------------------------------
# Copied from hooks/guard-scout-bash.sh with the kit's name changed; change both
# together. The two variable forms match case-sensitively everywhere; the
# expanded path forms case-insensitively on Windows.
literal_words='"$CLAUDE_CONFIG_DIR/tools/herenow.sh"
$CLAUDE_CONFIG_DIR/tools/herenow.sh'
kit_words=""
add_dir_forms() {
  _d="$1"
  [ -n "$_d" ] || return 0
  _forms="$_d
$(norm_root "$_d")"
  if command -v cygpath >/dev/null 2>&1; then
    _ml="$(cygpath -m -l "$_d" 2>/dev/null)"
    _ms="$(cygpath -m -s "$_d" 2>/dev/null)"
    _forms="$_forms
$_ml
$_ms
$(cygpath -u "$_d" 2>/dev/null)
$(drive_unix "$(norm_root "$_d")")
$(drive_unix "$_ml")
$(drive_unix "$_ms")"
  fi
  _oldifs="$IFS"; IFS='
'
  for _f in $_forms; do
    [ -n "$_f" ] || continue
    _f="${_f%/}"; _f="${_f%\\}"
    case "$_f" in
      *\\*) _sep='\' ;;
      *)    _sep='/' ;;
    esac
    _k="$_f${_sep}tools${_sep}herenow.sh"
    kit_words="$kit_words
\"$_k\""
    case "$_k" in
      *' '*|*\\*) ;;
      *) kit_words="$kit_words
$_k" ;;
    esac
  done
  IFS="$_oldifs"
}
add_dir_forms "${CLAUDE_CONFIG_DIR:-}"
_self_home="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
add_dir_forms "$_self_home"

rest=""
_oldifs="$IFS"; IFS='
'
for _w in $literal_words; do
  case "$cmd" in
    "$_w "*) rest="${cmd:${#_w}}"; break ;;
  esac
done
if [ -z "$rest" ]; then
  _cmd_cmp="$cmd"
  [ "$win_host" -eq 1 ] && _cmd_cmp="$(lc "$cmd")"
  for _w in $kit_words; do
    [ -n "$_w" ] || continue
    case "$_w" in *'$'*) continue ;; esac   # an expanded path never holds a variable
    _wc="$_w"
    [ "$win_host" -eq 1 ] && _wc="$(lc "$_w")"
    case "$_cmd_cmp" in
      "$_wc "*) rest="${cmd:${#_w}}"; break ;;
    esac
  done
fi
IFS="$_oldifs"
[ -n "$rest" ] || block "the command is not the here.now kit"

# --- the words after the kit ---------------------------------------------------------
# ltrim: drop leading spaces from $rest.
ltrim() { rest="${rest#"${rest%%[! ]*}"}"; }
# take_quoted <label>: $rest starts with a double quote; sets qv to the text up
# to the closing quote and $rest to what follows, which must be empty or start
# with a space.
take_quoted() {
  case "$rest" in
    \"*) ;;
    \'*) block "a single-quoted $1; double quotes only" ;;
    *)   block "an unquoted $1; double quotes only" ;;
  esac
  rest="${rest#\"}"
  case "$rest" in *\"*) ;; *) block "an unterminated quote" ;; esac
  qv="${rest%%\"*}"
  rest="${rest#*\"}"
  case "$rest" in
    ''|' '*) ;;
    *) block "text glued to the closing quote of the $1" ;;
  esac
}
# A quoted value bash would read differently from this guard.
check_path_value() {
  [ -n "$1" ] || block "an empty path"
  case "$1" in
    *'$'*|*'`'*) block "a \$ or a backtick in the path, which bash would expand" ;;
    *'\\'*) block "a doubled backslash in the path, which bash reads as one" ;;
    *'\') block "a path ending in a backslash, which bash reads as an escaped quote" ;;
  esac
}
check_text_value() {
  [ -n "$1" ] || block "an empty $2"
  case "$1" in
    *'$'*|*'`'*|*'\'*) block "a \$, backtick or backslash in the $2" ;;
  esac
}
# A site or Drive path: a text value, relative to its root, no .. segment.
check_rel_value() {
  check_text_value "$1" "$2"
  case "$1" in /*) block "a $2 starting with /" ;; esac
  case "/$1/" in */../*) block "a .. segment in the $2" ;; esac
}
check_drive_value() {
  check_text_value "$1" "drive name"
  case "$1" in -*) block "a drive name starting with -" ;; esac
}
# take_slug: a slug, bare or double-quoted, into sv.
take_slug() {
  case "$rest" in
    \"*) take_quoted "slug"; sv="$qv" ;;
    *)   sv="${rest%% *}"; rest="${rest:${#sv}}" ;;
  esac
  printf '%s' "$sv" | LC_ALL=C grep -Eq '^[a-z0-9-]+$' || block "a slug outside [a-z0-9-]"
}
# at_end <what>: nothing may follow.
at_end() { ltrim; [ -z "$rest" ] || block "$1"; }

ltrim
sub="${rest%% *}"
rest="${rest:${#sub}}"
have_ordered=0
case "$sub" in
  check)
    at_end "words after check"
    pass ;;
  manifest)
    ltrim
    take_quoted "path"
    check_path_value "$qv"
    at_end "more than one path, or words after the path"
    pass ;;
  site-ls)
    at_end "words after site-ls, which takes none"
    pass ;;
  site-files)
    ltrim; take_slug
    at_end "words after the slug"
    pass ;;
  site-cat)
    ltrim; take_slug
    ltrim; take_quoted "site path"; check_rel_value "$qv" "site path"
    at_end "words after the site path"
    pass ;;
  drive-ls)
    ltrim
    [ -z "$rest" ] && pass
    take_quoted "drive name"; check_drive_value "$qv"
    ltrim
    [ -z "$rest" ] && pass
    take_quoted "prefix"; check_rel_value "$qv" "prefix"
    at_end "more than a drive name and a prefix after drive-ls"
    pass ;;
  drive-cat)
    ltrim; take_quoted "drive name"; check_drive_value "$qv"
    ltrim; take_quoted "drive path"; check_rel_value "$qv" "drive path"
    at_end "words after the drive path"
    pass ;;
  drive-put)
    ltrim; take_quoted "drive name"; check_drive_value "$qv"; drive="$qv"
    ltrim; take_quoted "drive path"; check_rel_value "$qv" "drive path"; dpath="$qv"
    from=""; have_from=0
    while :; do
      ltrim
      [ -n "$rest" ] || break
      opt="${rest%% *}"
      rest="${rest:${#opt}}"
      case "$opt" in
        --from)
          [ "$have_from" -eq 0 ] || block "--from given twice"
          ltrim; take_quoted "local file"; check_path_value "$qv"; from="$qv"; have_from=1 ;;
        --ordered)
          [ "$have_ordered" -eq 0 ] || block "--ordered given twice"
          have_ordered=1 ;;
        -*)
          block "an option drive-put does not take ($opt); only --from and --ordered" ;;
        *)
          block "a stray word or a shell metacharacter after the drive path" ;;
      esac
    done
    [ "$have_from" -eq 1 ] || block "drive-put without --from \"<local-file>\""
    ;;
  publish)
    ltrim
    take_quoted "path"
    check_path_value "$qv"
    target="$qv"
    slug=""; have_slug=0; have_title=0; have_desc=0; have_public=0
    while :; do
      ltrim
      [ -n "$rest" ] || break
      opt="${rest%% *}"
      rest="${rest:${#opt}}"
      case "$opt" in
        --slug)
          [ "$have_slug" -eq 0 ] || block "--slug given twice"
          ltrim
          case "$rest" in
            \"*) take_quoted "slug"; _s="$qv" ;;
            *)   _s="${rest%% *}"; rest="${rest:${#_s}}" ;;
          esac
          printf '%s' "$_s" | LC_ALL=C grep -Eq '^[a-z0-9-]+$' \
            || block "a slug outside [a-z0-9-]"
          slug="$_s"; have_slug=1 ;;
        --title)
          [ "$have_title" -eq 0 ] || block "--title given twice"
          ltrim; take_quoted "title"; check_text_value "$qv" "title"; have_title=1 ;;
        --description)
          [ "$have_desc" -eq 0 ] || block "--description given twice"
          ltrim; take_quoted "description"; check_text_value "$qv" "description"; have_desc=1 ;;
        --ordered)
          [ "$have_ordered" -eq 0 ] || block "--ordered given twice"
          [ "$have_public" -eq 0 ] || block "--ordered with --public; an ordered publish is owner-only, and a public one always asks"
          have_ordered=1 ;;
        --public)
          [ "$have_public" -eq 0 ] || block "--public given twice"
          [ "$have_ordered" -eq 0 ] || block "--ordered with --public; an ordered publish is owner-only, and a public one always asks"
          have_public=1 ;;
        --api-key|--api-key=*|--token|--token=*|--base-url|--base-url=*|--allow-nonherenow-base-url|\
        --claim-token|--claim-token=*|--overwrite|--ttl|--ttl=*|--workspace|--workspace=*|\
        --from-drive|--from-drive=*|--version|--version=*|--spa|--client|--client=*)
          block "the option ${opt%%=*}, which the kit refuses (it names the harm); only --slug, --title, --description, --ordered and --public" ;;
        -*)
          block "an option the kit does not take ($opt)" ;;
        *)
          block "a second path, a stray word or a shell metacharacter after the path" ;;
      esac
    done
    ;;
  *)
    block "no subcommand the kit takes (check, manifest, site-ls, site-files, site-cat, drive-ls, drive-cat, publish or drive-put)" ;;
esac
case "$sub" in
  publish|drive-put) ;;
  *) block "the gate lost its place after an internal error, and an unfinished check never passes" ;;
esac

# --- the writes: whether the local source lies inside the session's root ------------
# judge_root <path>: sets root_state (inside | outside | unmade) and root_note.
root_state=unmade
root_note=""
case "$0" in */*) _hooks="${0%/*}" ;; *) _hooks=. ;; esac
delegate="$_hooks/guard-archivist-paths.sh"
passthru=""
case "$cwd_raw" in *'\"'*|*$'\002'*) cwd_raw="" ;; esac
case "$sid_raw" in *'\"'*|*$'\002'*) sid_raw="" ;; esac
[ -n "$sid_raw" ] && passthru="$passthru\"session_id\":\"$sid_raw\","
[ -n "$cwd_raw" ] && passthru="$passthru\"cwd\":\"$cwd_raw\","
judge_root() {
  root_state=unmade
  root_note=""
  # The path in the form the path guard compares: forward slashes, and on
  # Windows the mixed form (C:/...), which is how the session's root reaches it.
  _t="$(printf '%s' "$1" | tr '\\' '/')"
  if command -v cygpath >/dev/null 2>&1; then
    case "$_t" in
      /*) _m="$(cygpath -m "$_t" 2>/dev/null)"; [ -n "$_m" ] && _t="$_m" ;;
    esac
  fi
  if [ ! -f "$delegate" ]; then
    root_note=" The session-root check did not run: guard-archivist-paths.sh is not beside the gate."
    return 0
  fi
  # The delegate passes a path it cannot place; with no root to place it
  # against, a pass would read as inside, so the check stays unmade.
  if [ -z "${CLAUDE_PROJECT_DIR:-}" ] && [ -z "$cwd_raw" ]; then
    root_note=" The session-root check did not run: the gate knows no session root (neither CLAUDE_PROJECT_DIR nor the input's cwd)."
    return 0
  fi
  # One run of the path guard, as the OpenKnowledge guard runs it. Its ask
  # means the path lies outside the session's root and its grants; silence
  # with exit 0 means inside; a run that fails or answers in another shape
  # leaves the check unmade, and says so.
  _tj="${_t//\\/\\\\}"
  _out="$(printf '%s' "{$passthru\"tool_input\":{\"file_path\":\"$_tj\"}}" | "${BASH:-bash}" "$delegate" main-session 2>/dev/null)"
  _drc=$?
  case "$_out" in
    *'"permissionDecision":"ask"'*) root_state=outside; root_note=" The $2 lies OUTSIDE the session's root." ;;
    *)
      if [ "$_drc" -ne 0 ]; then
        root_note=" The session-root check failed (exit status $_drc) and did not say where the $2 lies."
      elif [ -n "$_out" ]; then
        root_note=" The session-root check answered in a shape the gate does not read."
      else
        root_state=inside
      fi ;;
  esac
  return 0
}

if [ "$sub" = drive-put ]; then
  judge_root "$from" "local file"
  [ "$have_ordered" -eq 1 ] && [ "$root_state" = inside ] && pass
  ask "a Drive upload, a live external write: drive $drive, path $dpath, local file $from.$root_note An unordered upload, or one whose local file lies outside the session's root, asks."
fi
[ "$sub" = publish ] || block "the gate lost its place after an internal error, and an unfinished check never passes"
if [ "$have_slug" -eq 1 ]; then act="an update of the site $slug"; else act="a new site"; fi
judge_root "$target" "target"
if [ "$have_public" -eq 1 ]; then
  ask "a PUBLIC publish: a new site anyone with the link can read, or an update that keeps the site's current access, which the gate cannot see. Target $target, $act.$root_note"
fi
if [ "$have_ordered" -eq 1 ]; then
  [ "$root_state" = inside ] && pass
  ask "an ordered publish passes only when its target lies inside the session's root. Target $target, $act.$root_note"
fi
ask "publish is a live external write, owner-only by default: the kit puts a new site up as a placeholder, locks it to the owner and checks it before the content goes up, and an update goes only to an owner-only site. Without --ordered it asks. Target $target, $act.$root_note"
