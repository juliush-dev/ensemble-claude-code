#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - session-level PreToolUse guard on the
# OpenKnowledge MCP tools: matcher mcp__open-knowledge__.* in settings.json,
# for every caller. ASCII-only, LF line endings (the subtree's *.sh eol=lf
# attribute).
#
# What it carries: the containment the member cards cannot - a write outside
# the session's own root, a skill write, a folder delete, a conflict
# resolution, a skill supply, an asset copied in from a host file outside the
# session's root. Whose job a markdown write is (the Archivist's
# notebooks, the Builder's bodies) stays card doctrine, exactly as for
# Edit|Write; this guard assumes no project layout (where .ok/ sits and what
# it covers is each folder owner's call).
#
# How it decides, per tool (the 21 tools OpenKnowledge 0.77.7 lists in its MCP
# tools/list, captured in full):
#
#   READ (exec, search, links, audit, history, skills, palette, config,
#   conflicts, share_link): pass. One tripwire on exec: a command segment (split
#   at | & ; and line breaks) running find with -delete, or sort with -o /
#   --output, asks (the exec allowlist admits both flags; the check stays until
#   they are settled).
#
#   ALWAYS ASK, for every caller: resolve_conflict (git index operations,
#   destructive); import and install (third-party skill supply; the Operator
#   holds them, and even the Operator's call asks); any skill variant of
#   write, edit, delete, move, restore_version; a folder delete.
#
#   DELEGATED (write, edit, delete, move, restore_version, checkpoint, and lint
#   with fix, its document or its path): every path the call names is resolved
#   to an absolute target - the call's own tool_input.cwd walked up to the
#   nearest .ok/config.yml, that
#   project's content.dir (default .), then the content-relative path - and each
#   target is handed to guard-archivist-paths.sh main-session through a
#   synthetic Edit-shaped input. Any ask wins. So the path law is one law: own
#   root passes, a foreign root asks, the session grants, the scratchpad
#   exemption, Rider A and the Archivist's silent exit all carry over unchanged.
#   checkpoint's target is the project's own .ok folder. Templates resolve to
#   <folder>/.ok/templates/<name>.md. write.asset.source, a host file the
#   server reads into the project, goes to the same path guard without the
#   caller's agent_type, so it asks outside the session's root for every
#   caller, the Archivist included; a relative source asks.
#
#   preview_url and lint without fix: pass (neither writes a file).
#
# Tracked, not pinned: the key table below is the enumerated schema of the
# eleven state-changing tools, at the top level and inside every path-carrying
# object. A key it does not name asks, so a field OpenKnowledge adds or renames
# after 0.77.7 asks instead of passing unguarded; a renamed path field also
# leaves the call with zero targets, which asks. An unknown tool name asks.
# Over-asking after an upgrade is the signal to re-enumerate, not friction to
# remove. The re-enumeration duty (launch/wire-mcp.ps1's header) updates this
# table, KEY_TABLE_ENUMERATED and fixtures/openknowledge-guard/ together.
#
# Fail direction: ask, never deny. A deny would strip import and install from
# the Operator too, permission rules being session-wide; every uncertain
# branch below ends in an ask the human may approve. A command hook that
# crashes, exits without a decision, or outruns its timeout does not block:
# the call goes on through the ordinary permission flow and this guard's ask
# never fires (hooks reference, current through Claude Code 2.1.282). So the
# guard reaches a verdict only through ask or pass below; an EXIT trap turns
# every other way out (an unbound variable, a signal, an exit nobody meant)
# into an ask, and a delegate that fails asks too. What no trap can cover: a
# hook that never starts (bash missing), and a run the harness kills at its
# timeout. Asks: unparseable input;
# a duplicated key at a level the guard reads; a write-class call without
# tool_input.cwd (the server needs it for a user-scope registration, and the
# guard will not guess the project); a cwd, path or content.dir carrying a ..
# segment, or a path given absolute (paths in a call are content-relative - a
# .. that stays inside is asked too, the price of keeping canonicalization in
# the one path guard); no .ok/config.yml at or above the cwd for a write-class
# call (read tools pass there: the server refuses them itself); an unreadable
# content.dir; the delegate missing.
#
# The JSON scanner is the live-reads guard's approach (an awk scanner tracking
# nesting and string state, so a key inside a value is never mistaken for a
# field), extended to flatten every value to one line: path, type, raw value.
# Keys holding anything but [A-Za-z0-9_-] are encoded, so they can never pose as
# a known key. String values stay as written, escapes included; a path value is
# decoded only for \\ and \/, and any other escape in it asks.

# No globbing anywhere: flattened paths carry [ and ], and nothing here globs.
set -uf

KEY_TABLE_ENUMERATED='0.77.7'

# DECIDED is set only by ask and pass, the guard's two verdicts.
DECIDED=0
ask() {
  DECIDED=1
  _r="$(printf '%s' "$1" | tr '\\"' "/'" | tr -d '\000-\037')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"OpenKnowledge guard: %s Not auto-accepted; the human may still approve explicitly."}}\n' "$_r"
  exit 0
}
pass() { DECIDED=1; exit 0; }
on_exit() {
  [ "$DECIDED" = 1 ] && exit 0
  ask "the guard stopped before reaching a verdict (exit status $1), and an unfinished check never passes."
}
trap 'on_exit $?' EXIT
trap 'exit 143' HUP INT TERM

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || ask "no tool input reached the guard."

# --- The scanner ------------------------------------------------------------
# Line 1: ok | bad. Then one line per value: <path> TAB <type> TAB <raw>.
# Types: o object, a array, s string (raw JSON text between the quotes, escapes
# as written; longer than 4096 bytes becomes the marker \002long), n literal.
# Paths: top-level keys bare (tool_name, tool_input), members joined with ".",
# array elements as [i].
parsed="$(printf '%s' "$input" | LC_ALL=C awk '
function enc(k) { if (k == "") return "%"; gsub(/[^A-Za-z0-9_-]/, "%", k); return k }
function vpath(   p) {
  if (ct[d] == "[") { p = cp[d] "[" cc[d] "]"; cc[d]++; return p }
  return (cp[d] == "" ? ck[d] : cp[d] "." ck[d])
}
function emit(p, t, v) { if (length(v) > 4096) v = "\002long"; out[++no] = p "\t" t "\t" v }
BEGIN {
  RS = "\001"
  for (x = 1; x < 32; x++) ctl = ctl sprintf("%c", x)
}
{ s = s $0 }
END {
  bad = (NR > 1)
  n = length(s); d = 0; started = 0; ended = 0
  instr = 0; inlit = 0; no = 0
  for (i = 1; i <= n && !bad; i++) {
    c = substr(s, i, 1)
    if (instr) {
      if (c == "\\") {
        e = substr(s, i + 1, 1)
        if (e ~ /["\\\/bfnrt]/) { i++; continue }
        if (e == "u" && substr(s, i + 2, 4) ~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) { i += 5; continue }
        bad = 1; break
      }
      if (index(ctl, c)) { bad = 1; break }
      if (c != "\"") continue
      instr = 0
      tok = substr(s, sstart, i - sstart)
      if (role == "key") { ck[d] = enc(tok); cx[d] = "c" }
      else { emit(spath, "s", tok); cx[d] = "n" }
      continue
    }
    if (inlit) {
      if (c ~ /[A-Za-z0-9.+-]/) continue
      inlit = 0
      lit = substr(s, lstart, i - lstart)
      if (lit !~ /^(true|false|null)$/ && lit !~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$/) { bad = 1; break }
      emit(lpath, "n", lit); cx[d] = "n"
    }
    if (c == " " || c == "\t" || c == "\r" || c == "\n") continue
    if (ended) { bad = 1; break }
    if (!started) {
      if (c != "{") { bad = 1; break }
      started = 1; d = 1; ct[1] = "{"; cp[1] = ""; cx[1] = "k0"; cc[1] = 0
      continue
    }
    x = cx[d]
    if (c == "\"") {
      if (ct[d] == "{" && (x == "k0" || x == "k")) { role = "key"; instr = 1; sstart = i + 1; continue }
      if (x == "v" || x == "v0") { role = "val"; spath = vpath(); instr = 1; sstart = i + 1; continue }
      bad = 1; break
    }
    if (c == ":") { if (ct[d] == "{" && x == "c") { cx[d] = "v"; continue } bad = 1; break }
    if (c == ",") { if (x == "n") { cx[d] = (ct[d] == "{") ? "k" : "v"; continue } bad = 1; break }
    if (c == "}" || c == "]") {
      if (c == "}" && !(ct[d] == "{" && (x == "k0" || x == "n"))) { bad = 1; break }
      if (c == "]" && !(ct[d] == "[" && (x == "v0" || x == "n"))) { bad = 1; break }
      d--
      if (d == 0) ended = 1; else cx[d] = "n"
      continue
    }
    if (c == "{" || c == "[") {
      if (x != "v" && x != "v0") { bad = 1; break }
      p = vpath(); emit(p, (c == "{") ? "o" : "a", "")
      d++; ct[d] = c; cp[d] = p; cc[d] = 0; cx[d] = (c == "{") ? "k0" : "v0"
      continue
    }
    if (c ~ /[-0-9tfn]/) {
      if (x != "v" && x != "v0") { bad = 1; break }
      lpath = vpath(); inlit = 1; lstart = i
      continue
    }
    bad = 1; break
  }
  if (instr || inlit || !started || !ended || d != 0) bad = 1
  print (bad ? "bad" : "ok")
  if (!bad) for (j = 1; j <= no; j++) print out[j]
}' 2>/dev/null)" || ask "the tool input could not be scanned."

NL='
'
TAB="$(printf '\t')"
SOH="$(printf '\001')"

[ "${parsed%%"$NL"*}" = "ok" ] || ask "the tool input is not one well-formed JSON object."
case "$parsed" in *"$NL"*) entries="${parsed#*"$NL"}" ;; *) entries="" ;; esac
# Every line, fenced by newlines on both sides, for the lookups below.
E="$NL$entries$NL"

# --- Queries over the flattened lines --------------------------------------------
# Pure bash on purpose: a hook runs on every OpenKnowledge call, and a process
# start costs tens of milliseconds under Git Bash. The lines stay small, since
# the scanner caps every string value at 4096 bytes.

# count <path>: sets N to how many values sit at exactly this path.
count() {
  N=0; _r="$E"
  while :; do
    case "$_r" in
      *"$NL$1$TAB"*) N=$((N + 1)); _r="${_r#*"$NL$1$TAB"}" ;;
      *) break ;;
    esac
  done
}
# first <path>: sets T (type) and V (raw value) of the first value at this
# path; both empty when there is none.
first() {
  T=""; V=""
  case "$E" in *"$NL$1$TAB"*) ;; *) return 0 ;; esac
  _x="${E#*"$NL$1$TAB"}"; _x="${_x%%"$NL"*}"
  T="${_x%%"$TAB"*}"; V="${_x#*"$TAB"}"
}
# kids <object path>: sets K to the object's own keys, each as <key>,
# duplicates kept.
kids() {
  K=""
  _kifs="$IFS"; IFS="$NL"
  for _ln in $entries; do
    _pp="${_ln%%"$TAB"*}"
    case "$_pp" in
      "$1."*) _r="${_pp#"$1."}"; case "$_r" in *.*|*'['*) ;; *) K="$K<$_r>" ;; esac ;;
    esac
  done
  IFS="$_kifs"
}
# elems <array path>: sets L to the array's element paths, one per line.
elems() {
  L=""
  _eifs="$IFS"; IFS="$NL"
  for _ln in $entries; do
    _pp="${_ln%%"$TAB"*}"
    case "$_pp" in
      "$1["*"]") _r="${_pp#"$1["}"; _r="${_r%]}"; case "$_r" in ''|*[!0-9]*) ;; *) L="$L$_pp$NL" ;; esac ;;
    esac
  done
  IFS="$_eifs"
}

# strict <object path> <label> <allowed keys, space-separated>: asks on a key
# the table does not name, and on a duplicated key.
strict() {
  kids "$1"
  _rest="$K"
  while [ -n "$_rest" ]; do
    _k="${_rest%%>*}"; _k="${_k#<}"; _rest="${_rest#*>}"
    case "$_rest" in *"<$_k>"*) ask "$2 carries the key '$_k' twice." ;; esac
    case " $3 " in
      *" $_k "*) : ;;
      *) ask "$2 carries the key '$_k', which the key table enumerated at OpenKnowledge $KEY_TABLE_ENUMERATED does not name for this tool. A field added or renamed upstream asks until the tool list is re-enumerated." ;;
    esac
  done
}

# decode_path <raw JSON string text>: sets D to the path with \\ and \/
# decoded; returns 1 on any other escape.
decode_path() {
  D="$1"
  case "$D" in *'\'*) ;; *) return 0 ;; esac
  D="${D//'\\'/$SOH}"
  D="${D//'\/'//}"
  case "$D" in *'\'*) return 1 ;; esac
  D="${D//$SOH/\\}"
}

# --- Top-level shape ----------------------------------------------------------
for _f in tool_name tool_input session_id agent_id agent_type cwd; do
  count "$_f"; [ "$N" -le 1 ] || ask "the hook input carries $_f more than once."
done
count tool_name; first tool_name
[ "$N" -eq 1 ] && [ "$T" = "s" ] || ask "the tool name is missing or not a string."
tool_full="$V"
count tool_input; first tool_input
[ "$N" -eq 1 ] && [ "$T" = "o" ] || ask "the tool input is missing or not an object."
case "$tool_full" in
  mcp__open-knowledge__*) tool="${tool_full#mcp__open-knowledge__}" ;;
  *) ask "this tool is not an OpenKnowledge tool the guard knows." ;;
esac

# The harness's own fields, carried into the synthetic input as written.
# passthru_src leaves agent_type out, so the Archivist's silent exit in the
# path guard never waves through an asset.source outside the session's root.
passthru=""; passthru_src=""
for _f in session_id agent_id agent_type cwd; do
  first "$_f"
  if [ "$T" = "s" ]; then
    case "$V" in *'\"'*) ask "the hook input's $_f carries an escaped quote." ;; esac
    passthru="$passthru\"$_f\":\"$V\","
    [ "$_f" = agent_type ] || passthru_src="$passthru_src\"$_f\":\"$V\","
  fi
done

TI=tool_input

# --- READ tools -----------------------------------------------------------------
case "$tool" in
  search|links|audit|history|skills|palette|config|conflicts|share_link)
    pass ;;
  exec)
    first "$TI.command"
    [ "$T" = "s" ] || pass
    _cmd="$V"
    case "$_cmd" in *'\u'*) ask "exec's command carries a \\u escape the tripwire cannot read." ;; esac
    # Decode the escapes a command can carry (an escaped backslash first, so it
    # is never read as the start of another escape); a newline or carriage
    # return ends a command the way | & ; do. Then drop quotes and backslashes,
    # as a shell would (-del\ete runs as -delete), and read each segment's
    # program and its arguments.
    _cmd="${_cmd//'\\'/$SOH}"
    _cmd="${_cmd//'\n'/$NL}"; _cmd="${_cmd//'\r'/$NL}"; _cmd="${_cmd//'\t'/ }"
    _cmd="${_cmd//'\"'/\"}"; _cmd="${_cmd//'\/'//}"
    _cmd="${_cmd//$SOH/\\}"
    _cmd="${_cmd//[|&;]/$NL}"
    _cmd="${_cmd//[\"\']/}"
    _cmd="${_cmd//\\/}"
    _hit=""
    _xifs="$IFS"; IFS="$NL"
    for _seg in $_cmd; do
      IFS=" $TAB"
      # shellcheck disable=SC2086
      set -- $_seg
      IFS="$NL"
      [ "$#" -gt 0 ] || continue
      _prog="${1##*/}"
      shift
      case "$_prog" in
        find)
          for _t in "$@"; do [ "$_t" = "-delete" ] && _hit="find with -delete"; done ;;
        sort)
          for _t in "$@"; do
            case "$_t" in
              --o*) _hit="sort with --output" ;;
              --*) : ;;
              -*o*) _hit="sort with -o" ;;
            esac
          done ;;
      esac
    done
    IFS="$_xifs"
    [ -z "$_hit" ] || ask "exec is a read shell, and this command runs $_hit, which writes a file inside the project (the exec allowlist admits the flag)."
    pass ;;
esac

# --- The always-asks --------------------------------------------------------
case "$tool" in
  resolve_conflict)
    ask "resolve_conflict runs git checkout, add or rm on the project's real index, and its delete strategy removes a file; it asks for every caller." ;;
  import|install)
    ask "$tool supplies or places a third-party skill. The Operator holds import and install, and even the Operator's call asks: only the human's word in the current exchange makes it lawful, with the source, skill, scope and every destination drafted first. From any other hand, route it to the Operator." ;;
esac

# --- The key table (enumerated at KEY_TABLE_ENUMERATED) ----------------------
case "$tool" in
  write)           strict "$TI" "write" "document folder template skill asset documents summary cwd" ;;
  edit)            strict "$TI" "edit" "document folder template skill summary cwd" ;;
  delete)          strict "$TI" "delete" "document folder template skill asset cwd" ;;
  move)            strict "$TI" "move" "from to template skill summary cwd" ;;
  lint)            strict "$TI" "lint" "document path fix cwd" ;;
  checkpoint)      strict "$TI" "checkpoint" "summary cwd" ;;
  restore_version) strict "$TI" "restore_version" "document skill version summary cwd" ;;
  preview_url)     strict "$TI" "preview_url" "document folder skill file cwd"
                   first "$TI.skill"
                   [ "$T" != "o" ] || strict "$TI.skill" "preview_url.skill" "name scope"
                   pass ;;
  *) ask "the tool '$tool' is not in the tool list enumerated at OpenKnowledge $KEY_TABLE_ENUMERATED. A tool added upstream asks until the tool list is re-enumerated." ;;
esac

# lint without fix is a read.
if [ "$tool" = "lint" ]; then
  count "$TI.fix"; first "$TI.fix"
  if [ "$N" -eq 0 ] || { [ "$T" = "n" ] && [ "$V" = "false" ]; }; then
    pass
  fi
fi

# Skill variants and folder deletes ask for every caller.
case "$tool" in
  write|edit|delete|move|restore_version)
    count "$TI.skill"
    [ "$N" -eq 0 ] || ask "$tool with skill writes into a skill folder that sessions load; a skill write asks for every caller." ;;
esac
if [ "$tool" = "delete" ]; then
  count "$TI.folder"
  [ "$N" -eq 0 ] || ask "delete with folder removes a whole folder, recursively; it asks for every caller."
fi

# --- Target extraction ----------------------------------------------------------
# Each target is recorded as "<kind> <raw path>"; kind doc = content-relative
# path, tpl = template <folder>/<name>, root = the project's own .ok folder.
targets=""
asset_src=""; has_src=0
add() { targets="$targets$1 $2$NL"; }
# need_str <path> <label> <kind>: the value at <path> must be a string.
need_str() {
  first "$1"
  [ "$T" = "s" ] || ask "$2 is not a string, which the enumerated schema does not allow."
  add "$3" "$V"
}
# obj <path> <label> <allowed keys> <kind> <path key>: a path-carrying object.
obj() {
  count "$1"; [ "$N" -eq 1 ] || return 0
  first "$1"; [ "$T" = "o" ] || ask "$2 is not an object, which the enumerated schema does not allow."
  strict "$1" "$2" "$3"
  count "$1.$5"; [ "$N" -eq 0 ] || need_str "$1.$5" "$2.$5" "$4"
}
# strings <array path> <label> <kind>: every element must be a string path.
strings() {
  elems "$1"; _slist="$L"
  _sifs="$IFS"; IFS="$NL"
  for _se in $_slist; do IFS="$_sifs"; need_str "$_se" "$2" "$3"; IFS="$NL"; done
  IFS="$_sifs"
}

case "$tool" in
  write)
    obj "$TI.document" "write.document" "path content extension template frontmatter position" doc path
    obj "$TI.folder"   "write.folder"   "path frontmatter" doc path
    obj "$TI.template" "write.template" "path content frontmatter" tpl path
    obj "$TI.asset"    "write.asset"    "path content source" doc path
    # asset.source is a host file the server reads into the project; it is
    # judged below, by the same path guard, against the session's root.
    count "$TI.asset.source"
    if [ "$N" -ne 0 ]; then
      first "$TI.asset.source"
      [ "$T" = "s" ] || ask "write.asset.source is not a string, which the enumerated schema does not allow."
      asset_src="$V"; has_src=1
    fi
    count "$TI.documents"
    if [ "$N" -eq 1 ]; then
      first "$TI.documents"; [ "$T" = "a" ] || ask "write.documents is not an array."
      elems "$TI.documents"; _dlist="$L"
      _difs="$IFS"; IFS="$NL"
      for _de in $_dlist; do
        IFS="$_difs"
        first "$_de"; [ "$T" = "o" ] || ask "an entry of write.documents is not an object."
        strict "$_de" "write.documents[]" "path content extension template frontmatter position summary"
        count "$_de.path"; [ "$N" -eq 0 ] || need_str "$_de.path" "write.documents[].path" doc
        IFS="$NL"
      done
      IFS="$_difs"
    fi ;;
  edit)
    obj "$TI.document" "edit.document" "path find replace occurrence frontmatter" doc path
    obj "$TI.folder"   "edit.folder"   "path frontmatter" doc path
    obj "$TI.template" "edit.template" "path find replace occurrence frontmatter" tpl path ;;
  delete)
    obj "$TI.template" "delete.template" "path" tpl path
    obj "$TI.asset"    "delete.asset"    "path" doc path
    count "$TI.document"
    if [ "$N" -eq 1 ]; then
      first "$TI.document"
      case "$T" in
        s) add doc "$V" ;;
        a) strings "$TI.document" "an entry of delete.document" doc ;;
        o) strict "$TI.document" "delete.document" "path"
           first "$TI.document.path"
           case "$T" in
             s) add doc "$V" ;;
             a) strings "$TI.document.path" "an entry of delete.document.path" doc ;;
             '') : ;;
             *) ask "delete.document.path is neither a string nor an array." ;;
           esac ;;
        *) ask "delete.document is neither a string, an array nor an object." ;;
      esac
    fi ;;
  move)
    for _k in from to; do
      count "$TI.$_k"; [ "$N" -eq 0 ] || need_str "$TI.$_k" "move.$_k" doc
    done
    count "$TI.template"
    if [ "$N" -eq 1 ]; then
      first "$TI.template"; [ "$T" = "o" ] || ask "move.template is not an object."
      strict "$TI.template" "move.template" "from to"
      for _k in from to; do
        count "$TI.template.$_k"; [ "$N" -eq 0 ] || need_str "$TI.template.$_k" "move.template.$_k" tpl
      done
    fi ;;
  lint)
    # The enumerated schema says path is ignored when document is given, and
    # that fix requires document. Both are judged anyway, so a fix over a folder
    # delegates rather than asking for want of a path.
    count "$TI.document"; [ "$N" -eq 0 ] || need_str "$TI.document" "lint.document" doc
    count "$TI.path";     [ "$N" -eq 0 ] || need_str "$TI.path" "lint.path" doc ;;
  restore_version)
    count "$TI.document"; [ "$N" -eq 0 ] || need_str "$TI.document" "restore_version.document" doc ;;
  checkpoint)
    add root "." ;;
esac

[ -n "$targets" ] || ask "$tool names no path the guard can find (a path field renamed upstream reads this way), and a write-class call with zero targets never passes."

# --- The project: cwd, the .ok root, content.dir ------------------------------------
count "$TI.cwd"
[ "$N" -eq 1 ] || ask "$tool carries no tool_input.cwd, so the guard cannot tell which OpenKnowledge project it writes; pass cwd, an absolute path inside the project."
first "$TI.cwd"
[ "$T" = "s" ] || ask "tool_input.cwd is not a string."
decode_path "$V" || ask "tool_input.cwd carries an escape the guard does not read."
okcwd="${D//\\//}"
while :; do case "$okcwd" in */) okcwd="${okcwd%/}" ;; *) break ;; esac; done
case "$okcwd" in
  [A-Za-z]:|[A-Za-z]:/*|/*) : ;;
  *) ask "tool_input.cwd is not an absolute path." ;;
esac
case "/$okcwd/" in */../*) ask "tool_input.cwd carries a .. segment." ;; esac

okroot=""
_d="$okcwd"
while :; do
  if [ -f "$_d/.ok/config.yml" ]; then okroot="$_d"; break; fi
  case "$_d" in [A-Za-z]:|'') break ;; esac
  _p="${_d%/*}"
  [ "$_p" != "$_d" ] || break
  _d="$_p"
done
[ -n "$okroot" ] || ask "no .ok/config.yml at or above tool_input.cwd, so this write has no OpenKnowledge project to land in."

if [ "$tool" = "checkpoint" ]; then
  content="$okroot"
else
  # content.dir: block style under a top-level content: key (what ok init
  # writes); absent means the default ".". Flow style, a duplicated key or an
  # escape other than \\ reads as unreadable.
  content_dir="$(LC_ALL=C awk '
    { sub(/\r$/, "") }
    /^content:/ {
      seen++
      rest = $0; sub(/^content:[ \t]*/, "", rest)
      if (rest != "" && rest !~ /^#/) { bad = 1 }
      incontent = 1; next
    }
    /^[^ \t#]/ { incontent = 0 }
    incontent && /^[ \t]+[^ \t#]/ {
      match($0, /^[ \t]+/)
      if (ind == 0) ind = RLENGTH
      if (RLENGTH == ind && $0 ~ /^[ \t]+dir:/) { v = $0; sub(/^[ \t]+dir:[ \t]*/, "", v); dirs++; val = v }
    }
    END {
      if (bad || seen > 1 || dirs > 1) { print "\001"; exit }
      if (dirs == 0) { print "."; exit }
      v = val
      if (v ~ /^"/) {
        if (v !~ /^"([^"\\]|\\\\)*"[ \t]*(#.*)?$/) { print "\001"; exit }
        sub(/"[ \t]*(#.*)?$/, "", v); v = substr(v, 2); gsub(/\\\\/, "\\", v)
      } else if (v ~ /^\047/) {
        if (v !~ /^\047([^\047]|\047\047)*\047[ \t]*(#.*)?$/) { print "\001"; exit }
        sub(/\047[ \t]*(#.*)?$/, "", v); v = substr(v, 2); gsub(/\047\047/, "\047", v)
      } else {
        sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
      }
      if (v == "") v = "."
      print v
    }' "$okroot/.ok/config.yml" 2>/dev/null)" || content_dir="$SOH"
  [ "$content_dir" != "$SOH" ] && [ -n "$content_dir" ] || ask "the project's .ok/config.yml gives no content.dir the guard can read."
  content_dir="${content_dir//\\//}"
  case "/$content_dir/" in */../*) ask "the project's content.dir carries a .. segment." ;; esac
  case "$content_dir" in
    [A-Za-z]:/*|/*) content="$content_dir" ;;
    *) content="$okroot/$content_dir" ;;
  esac
  content="${content%/}"
fi

# --- Resolve every target first, then delegate each distinct one -----------------
# MAX_TARGETS bounds the delegation: each target costs one run of the path guard,
# and a hook that outruns its timeout must not become the way a large batch goes
# unguarded. Measured under Git Bash on the host this was built on, a
# 100-target write took 106 s with the scratchpad variables unset and 142 s with
# LOCALAPPDATA, TEMP and TMP set as a live session has them (about 1.4 s a
# target). The explicit 600-second timeout on this hook's settings.json entry is
# about four times that. A larger batch asks; split it to pass.
MAX_TARGETS=100
resolved="$NL"
ndistinct=0
_rifs="$IFS"; IFS="$NL"
for _line in $targets; do
  IFS="$_rifs"
  _kind="${_line%% *}"
  _raw="${_line#* }"
  if [ "$_kind" = "root" ]; then
    _t="$content/.ok"
  else
    case "$_raw" in *"$(printf '\002')"*) ask "a path in the call is longer than the guard reads." ;; esac
    decode_path "$_raw" || ask "a path in the call carries an escape the guard does not read."
    _rel="${D//\\//}"
    case "$_rel" in
      '') ask "a path in the call is empty." ;;
      [A-Za-z]:*|/*) ask "the path '$_rel' is absolute; paths in an OpenKnowledge call are relative to the project's content folder." ;;
    esac
    case "/$_rel/" in */../*) ask "the path '$_rel' carries a .. segment, so it may leave the project's content folder." ;; esac
    if [ "$_kind" = "tpl" ]; then
      case "$_rel" in
        */*) _rel="${_rel%/*}/.ok/templates/${_rel##*/}.md" ;;
        *)   _rel=".ok/templates/$_rel.md" ;;
      esac
    fi
    _t="$content/$_rel"
  fi
  case "$resolved" in
    *"$NL$_t$NL"*) : ;;
    *) resolved="$resolved$_t$NL"; ndistinct=$((ndistinct + 1)) ;;
  esac
  IFS="$NL"
done
IFS="$_rifs"
[ "$ndistinct" -le "$MAX_TARGETS" ] || ask "$tool names $ndistinct distinct targets, more than the $MAX_TARGETS this guard checks in one call; split the batch."

case "$0" in */*) _hooks="${0%/*}" ;; *) _hooks=. ;; esac
delegate="$_hooks/guard-archivist-paths.sh"
[ -f "$delegate" ] || ask "the path guard it delegates to, guard-archivist-paths.sh, is not beside it."

# judge <absolute path> <harness fields> <what the call does with it>: one run
# of the path guard. Its ask wins; a run that fails, or answers in any other
# shape, asks too, since a crashed delegate prints nothing, which reads as a
# pass.
judge() {
  _out="$(printf '%s' "{$2\"tool_input\":{\"file_path\":\"$1\"}}" | "${BASH:-bash}" "$delegate" main-session 2>/dev/null)"
  _drc=$?
  case "$_out" in
    *'"permissionDecision":"ask"'*)
      _why="$(printf '%s' "$_out" | sed -n 's/.*"permissionDecisionReason":"\(.*\)"}}.*/\1/p')"
      ask "$3 $1, and the path guard asks: $_why" ;;
  esac
  [ "$_drc" -eq 0 ] || ask "$3 $1, and the path guard it delegates to failed (exit status $_drc) without a verdict."
  [ -z "$_out" ] || ask "$3 $1, and the path guard answered in a shape this guard does not read."
}

_gifs="$IFS"; IFS="$NL"
for _t in $resolved; do
  IFS="$_gifs"
  [ -n "$_t" ] || { IFS="$NL"; continue; }
  judge "$_t" "$passthru" "$tool targets"
  IFS="$NL"
done
IFS="$_gifs"

# write.asset.source asks when it lies outside the session's root. The same
# path guard judges it, without agent_type, so the
# session's own root, its grants and the scratchpad count as inside and nothing
# else does, for every caller. A relative source asks: the server resolves it
# against its own working folder, which the guard cannot see.
if [ "$has_src" -eq 1 ]; then
  first cwd
  [ "$T" = "s" ] || [ -n "${CLAUDE_PROJECT_DIR:-}" ] || ask "write.asset.source is judged against the session's root, and the hook input names none."
  case "$asset_src" in *"$(printf '\002')"*) ask "write.asset.source is longer than the guard reads." ;; esac
  decode_path "$asset_src" || ask "write.asset.source carries an escape the guard does not read."
  _src="${D//\\//}"
  case "$_src" in
    [A-Za-z]:/*|/*) : ;;
    *) ask "write.asset.source '$_src' is not an absolute path; the server reads a relative one from its own working folder, which the guard cannot see." ;;
  esac
  case "/$_src/" in */../*) ask "write.asset.source '$_src' carries a .. segment." ;; esac
  judge "$_src" "$passthru_src" "write reads its asset.source from"
fi

pass
