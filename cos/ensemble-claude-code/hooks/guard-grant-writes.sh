#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - session-level PreToolUse guard on Bash|PowerShell.
# The grant-write guard. A session grant, one root per line in
# hooks/session-roots/<session_id>.txt, lets the session and its members write
# under that root without the path guard's foreign-root ask. The Lead
# writes a grant with the Write or Edit tool, so the path guard
# (guard-archivist-paths.sh, wired on Edit|Write only) asks once and the human
# sees each widening. A shell write never reaches that guard: a grant rebuilt
# with printf ... > "$f" through the Bash tool can pass in auto mode, and the
# human never sees the widening. This guard asks, never denies, on a shell
# command that looks like a write into the grant folder, for every caller, the
# main session and every member alike.
# Since 2.1.211 a PreToolUse ask on Bash floors at a prompt in auto mode
# (HARNESS.md). An ask's reason is shown to the human, not to the agent, so the
# message is written for him.
#
# A command is judged only when it names session-roots, without regard to
# case, in its own text or in the hook input's cwd (the Bash tool keeps its
# working folder between calls, so a cd into the folder and a later bare
# printf > id.txt is caught by the second call's cwd). Either slash direction
# matches, since the name is matched alone. It then asks when the text, matched
# without regard to case, carries a write shape anywhere:
#   redirection    > or >> to anything but /dev/null, $null, NUL or a file
#                  descriptor (2>/dev/null, 2>&1, >&2, *>$null and | Out-Null
#                  pass); >| and &> to a file ask; > counts as >
#   tee            tee, Tee-Object
#   copy           cp, copy, Copy-Item, cpi, xcopy, robocopy, rsync
#   move           mv, move, Move-Item, mi, Rename-Item, ren, rni
#   install, ln, dd, truncate, touch
#   mkdir          mkdir, md, New-Item, ni
#   sed -i         sed with -i, -i.bak, -Ei, --in-place
#   perl -i        perl with -i or -pi
#   Set-Content    Set-Content, Add-Content, Out-File, sc, ac
#   [IO.File]      ]::Write..., Append..., Create..., Copy..., Move...,
#                  Replace...(, and a StreamWriter
#   script write   Python write_text( / write_bytes(, shutil.copy/move, an
#                  open( with a w, a, x or + mode; Node writeFile(Sync)(,
#                  appendFile, copyFile, createWriteStream
# A delete passes: rm, Remove-Item, del and unlink of a grant file narrow
# access, never widen it, and a recursive delete asks in guard-delete.sh.
#
# It is a string heuristic against habit, not a barrier against a hand that
# means to hide; such writes come from habit. It over-asks: any write shape
# anywhere in a command that names the folder asks, a redirect to a log file
# beside a grant read, a commit message naming the folder and the word touch,
# a > inside a quoted string. It misses a write whose text names neither the
# folder nor a write shape it knows: the path assembled at run time (a
# variable from a file, eval, base64, ses''sion-roots, a glob such as
# session-r*), an 8.3 short name (SESSIO~1), a script file the command only
# runs (bash x.sh, python x.py), a program writing through its own option
# (curl -o, tar -x, Invoke-WebRequest -OutFile), PowerShell splatting, and a
# write by any tool other than Bash and PowerShell. A hook that cannot start
# fails open, and so does one the 10-second timeout kills. The source tree's
# fixtures/grant-write-guard/run-fixture.sh holds the cases.

set -u
LC_ALL=C; export LC_ALL   # byte semantics: ASCII classes and case, every host alike
shopt -s nocasematch

# Fail-closed: every verdict goes through ask or pass, and an exit that reaches
# neither (a crash, a signal) asks from the EXIT trap. Empty input asks too.
ask() {
  DECIDED=1
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$1"}}
JSON
  exit 0
}
pass() { DECIDED=1; exit 0; }
grep_failed() { ask "Grant-write guard: the pattern check failed (grep exit status $1), so the guard cannot tell whether this command writes a session grant. Check the command before approving."; }
on_exit() {
  [ "${DECIDED:-0}" = 1 ] && exit 0
  ask "Grant-write guard: the guard stopped before reaching a verdict (exit status $1), and an unfinished check never passes. Check the command before approving."
}
DECIDED=0
trap 'on_exit $?' EXIT
trap 'exit 143' HUP INT TERM

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || ask "Grant-write guard: no tool input reached the guard, so it cannot tell whether the command writes a session grant. Check the command before approving."

# Fast path, builtins only: input that never names the folder passes.
case "$input" in *session-roots*) ;; *) pass ;; esac

# Key-scoped, non-greedy capture of the command and cwd values (the push
# gate's): a description or any other field cannot bleed into them.
cmd="$(printf '%s' "$input" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1)"
[ -n "$cmd" ] || ask "Grant-write guard: the command could not be read from the tool input, so the guard cannot tell whether it writes a session grant. Check the command before approving."
cwd="$(printf '%s' "$input" | sed -nE 's/.*"cwd"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1)"

where=""
case "$cmd" in *session-roots*) where="cmd" ;; esac
[ -z "$where" ] && case "$cwd" in *session-roots*) where="cwd" ;; esac
[ -n "$where" ] || pass

# The text the shapes are matched on: lower case, > read as >, and the
# redirections that write no file blanked out.
q="'"
t="$(printf '%s' "$cmd" | tr 'A-Z' 'a-z' | sed -E \
  -e 's/\\u003e/>/g' \
  -e 's/[0-9&*]?>>?[[:space:]]*&([0-9]+|-)/ /g' \
  -e 's/[0-9&*]?>>?[[:space:]]*(\\?["'"$q"'])?\/dev\/null(\\?["'"$q"'])?/ /g' \
  -e 's/[0-9*]?>>?[[:space:]]*\$null/ /g' \
  -e 's/[0-9]?>>?[[:space:]]*nul([^a-z0-9_.]|$)/ \1/g')" || grep_failed "$?"

found=""
case "$t" in *'>'*) found="redirection" ;; esac

B='(^|[[:space:];&|(){}!`"/'"$q"']|\\[ntr]?)'  # before a verb
A='([[:space:];&|()<>`"'"$q"']|\\|$)'           # after a verb
W='([[:space:]]|\\[ntr])'                        # a gap between words
Q='(\\?["'"$q"'])?'                              # an optional quote
O='([^;&|]*'"$W"')?'                             # more words, same segment

names=(); pats=()
add() { names+=("$1"); pats+=("$2"); }
add 'tee'          "$B"'(tee|tee-object)(\.exe)?'"$Q$A"
add 'copy'         "$B"'(cp|copy|copy-item|cpi|xcopy|robocopy|rsync)(\.exe)?'"$Q$A"
add 'move'         "$B"'(mv|move|move-item|mi|rename-item|ren|rni)(\.exe)?'"$Q$A"
add 'install'      "$B"'install(\.exe)?'"$Q$A"
add 'ln'           "$B"'ln(\.exe)?'"$Q$A"
add 'dd'           "$B"'dd(\.exe)?'"$Q$A"
add 'truncate'     "$B"'truncate(\.exe)?'"$Q$A"
add 'touch'        "$B"'touch(\.exe)?'"$Q$A"
add 'mkdir'        "$B"'(mkdir|md|new-item|ni)(\.exe)?'"$Q$A"
add 'sed -i'       "$B"'sed(\.exe)?'"$Q$W$O"'(-[a-z]*i|--in-place)'
add 'perl -i'      "$B"'perl(\.exe)?'"$Q$W$O"'-[a-z]*i'
add 'Set-Content'  "$B"'(set-content|add-content|out-file|sc|ac)(\.exe)?'"$Q$A"
add '[IO.File]'    '\]::(write|append|create|copy|move|replace)[a-z]*[[:space:]]*\(|streamwriter'
add 'script write' 'write_(text|bytes)[[:space:]]*\(|shutil\.(copy|move)|(write|append|copy)file(sync)?[[:space:]]*\(|createwritestream|open[[:space:]]*\([^)]*\\?["'"$q"'][a-z+]*[wax+][a-z+]*\\?["'"$q"']'

for i in "${!pats[@]}"; do
  printf '%s' "$t" | grep -Eq -e "${pats[$i]}"
  rc=$?
  [ "$rc" -eq 1 ] && continue
  [ "$rc" -eq 0 ] || grep_failed "$rc"
  found="${found:+$found, }${names[$i]}"
done
[ -n "$found" ] || pass

# The command for the message: printable ASCII only (a raw control or a cut
# multibyte character would break the JSON), its first 300 characters, a cut
# escape at the end dropped.
snip="$(printf '%s' "$cmd" | tr -cd ' -~' | head -c 300 | sed -E 's/(^|[^\\])((\\\\)*)\\(u[0-9A-Fa-f]{0,3})?$/\1\2/')"
[ "${#cmd}" -gt 300 ] && snip="$snip ..."
via="names the session-grant folder (hooks/session-roots)"
[ "$where" = cwd ] && via="runs inside the session-grant folder (hooks/session-roots)"
ask "Grant-write guard: this command $via and looks like a write there (shape: $found): $snip. A write into that folder widens where this session and its members may write without being asked. The Lead writes grants with the Write or Edit tool, where the path guard asks you; a shell write goes around that guard, so this prompt stands in for it. Approve only if you want this grant."
