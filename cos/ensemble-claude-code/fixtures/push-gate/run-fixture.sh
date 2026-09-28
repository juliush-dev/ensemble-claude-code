#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/guard-push-gate.sh, the push gate.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It writes nothing outside a temp directory it
# removes on the way out, never touches a deployed home and never runs git:
# the gate only reads command text, so no case pushes anything. On Windows run
# it from Git Bash: a bare 'bash' typed in PowerShell may start WSL's bash.
#
# Each case feeds the gate one PreToolUse input on stdin, as the harness does,
# and asserts the verdict: pass is exit 0 with no output, ask is exit 0 with
# one ask naming the case's reason. The gate never denies or blocks, so any
# deny in the output fails the case. The command text is written as it sits
# inside the JSON string, escapes included: \n is a newline, \\\n a
# backslash-newline continuation, \" a double quote.
#
# The cases: the compound spellings a review found passing unasked (a
# metacharacter, a subshell, a command substitution, a redirection or a
# newline right after "push"); the forms that already asked and must keep
# asking; the neighbors closed in the same change (a newline or a quote before
# "git", a JSON whitespace escape between "git" and "push", a quoted
# subcommand or git path, a backslash-escaped or uppercase "git", an inline
# alias); the over-asks the gate accepts by design; ordinary commands that
# must pass; a description field that names a push; unparseable and empty
# input; a gate that cannot finish its check (a stub grep that errors, a TERM
# mid-check), which must ask; and a 300 KB command for speed.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../../hooks/guard-push-gate.sh"
[ -f "$GUARD" ] || { echo "FAIL (setup): gate not found at $GUARD"; exit 1; }

PASSED=0
FAILED=0
FAILED_NAMES=""
GUARD_PATH_PREFIX=""   # a stub directory put first on the guard's PATH only

TMPBASE="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMPBASE"' EXIT

# check <name> <pass|ask> <fragment or -> <raw hook input>
check() {
  local name="$1" expect="$2" frag="$3" json="$4" out err rc e
  err="$TMPBASE/stderr.txt"
  out="$(printf '%s' "$json" | PATH="${GUARD_PATH_PREFIX:+$GUARD_PATH_PREFIX:}$PATH" "$BASH" "$GUARD" 2>"$err")"
  rc=$?
  e="$(cat "$err")"
  local verdict="?"
  if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ -z "$e" ]; then verdict=pass
  elif [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; then verdict=ask
  fi
  if printf '%s%s' "$out" "$e" | grep -qi '"deny"'; then
    echo "FAIL ($name): the output carries a deny."; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  if [ "$verdict" != "$expect" ]; then
    echo "FAIL ($name): expected $expect, got $verdict (exit $rc). Output: ${out:-<none>} Stderr: ${e:-<none>}"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  if [ "$frag" != "-" ] && ! printf '%s' "$out" | grep -qF -- "$frag"; then
    echo "FAIL ($name): the $expect does not name '$frag'. Output: $out"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  echo "PASS ($name): $expect."
  PASSED=$((PASSED + 1))
}

# hin <tool> <command as JSON string text> [extra tool_input members]
hin() {
  printf '{"session_id":"fixture-session-0","transcript_path":"t.jsonl","cwd":"/fixture","permission_mode":"auto","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s"%s}}' \
    "$1" "$2" "${3:-}"
}
A="looks push-shaped"
ask_() { check "$1" ask "$A" "$(hin Bash "$2")"; }
pass_() { check "$1" pass - "$(hin Bash "$2")"; }

# --- the finding: compound spellings that passed unasked ------------------------------------
ask_ "push, then ;"                      'git push;'
ask_ "push, then ;, no space"            'git push;echo done'
ask_ "push, then &&"                     'git push&&echo done'
ask_ "push, then ||"                     'git push||true'
ask_ "push, then |"                      'git push|cat'
ask_ "push, then & (background)"         'git push&'
ask_ "subshell (git push)"               '(git push)'
ask_ "command substitution \$(git push)" 'echo $(git push)'
ask_ "backticks"                         'echo `git push`'
ask_ "push, then >"                      'git push>log'
ask_ "push, then <"                      'git push<in'
ask_ "backslash-newline continuation"    'git push\\\norigin main'
ask_ "push, then a newline"              'git push\nls'
ask_ "push, then CRLF"                   'git push\r\nls'
ask_ "push, then a JSON tab"             'git push\torigin'

# --- forms that already asked and must keep asking ------------------------------------------
ask_ "plain push"                        'git push'
ask_ "push origin main"                  'git push origin main'
ask_ "git -C path push"                  'git -C /x push'
ask_ "x;git push"                        'x;git push'
ask_ "git --git-dir push"                'git --git-dir=.git push'
ask_ "push --dry-run"                    'git push --dry-run'
ask_ "git.exe push"                      'git.exe push'
ask_ "cd && git push"                    'cd /x && git push'
ask_ "push 2>&1"                         'git push 2>&1'
ask_ "real tab between"                  "git	push"
check "PowerShell tool"                  ask "$A" "$(hin PowerShell 'git push; Write-Host done')"

# --- neighbors closed in the same change ----------------------------------------------------
ask_ "a newline before git"              'ls\ngit push'
ask_ "a JSON tab between git and push"   'git\tpush'
ask_ "a JSON tab after flags"            'git -C /x\tpush'
ask_ "continuation between git and push" 'git \\\npush'
ask_ "bash -c, double quotes"            'bash -c \"git push\"'
ask_ "sh -c, single quotes"              "sh -c 'git push'"
ask_ "quoted subcommand"                 'git \"push\" origin'
ask_ "single-quoted subcommand"          "git 'push'"
ask_ "quoted git.exe path"               '\"C:/Program Files/Git/cmd/git.exe\" push'
ask_ "git by path"                       '/mingw64/bin/git push'
ask_ "backslash-escaped git"             '\\git push'
ask_ "uppercase GIT"                     'GIT push'
ask_ "mixed-case Git.EXE"                'Git.EXE push'
ask_ "inline alias"                      'git -c alias.p=push p'
ask_ "brace group"                       '{ git push;}'

# --- over-asks the gate accepts by design ---------------------------------------------------
ask_ "over-ask: git stash push"          'git stash push'
ask_ "over-ask: grep=push"               'git log --grep=push'
ask_ "over-ask: push in a message"       'git commit -m \"push gate fix\"'
ask_ "over-ask: uppercase PUSH"          'git PUSH'

# --- ordinary commands that must pass -------------------------------------------------------
pass_ "git status"                       'git status'
pass_ "git pull"                         'git pull'
pass_ "echo push"                        'echo push'
pass_ "pushd"                            'pushd /x'
pass_ "not the subcommand: pusher"       'git pusher'
pass_ "not the subcommand: push-x"       'git push-x'
pass_ "a word ending in git"             'legit push'
pass_ "push after a pipe"                'git log --oneline | grep push'
pass_ "push after a ;"                   'git fetch; echo pushed'
pass_ "push after &&"                    'git status && echo push'
pass_ "a newline, no push"               'ls\nls'
check "description names a push"         pass - "$(hin Bash 'git status' ',"description":"then git push origin main"')"

# --- input the gate cannot read -------------------------------------------------------------
check "no command field"                 ask "could not be isolated" '{"tool_name":"Bash","tool_input":{}}'
check "not JSON"                         ask "could not be isolated" 'garbage'
check "empty input"                      ask "no tool input" ''

# --- a gate that cannot finish its check: fail-closed ---------------------------------------
# A stub grep first on the guard's PATH (never the fixture's own): exit 2 must
# not read as "no match", and a TERM mid-check must reach the EXIT trap's ask.
STUB="$TMPBASE/stub-grep-2"; mkdir -p "$STUB"
printf '#!/bin/sh\nexit 2\n' > "$STUB/grep"; chmod +x "$STUB/grep"
GUARD_PATH_PREFIX="$STUB"
check "grep fails, a push"               ask "grep exit status 2" "$(hin Bash 'git push')"
check "grep fails, an ordinary command"  ask "grep exit status 2" "$(hin Bash 'git status')"
STUB="$TMPBASE/stub-grep-term"; mkdir -p "$STUB"
printf '#!/bin/sh\nkill -TERM "$PPID"\nexit 1\n' > "$STUB/grep"; chmod +x "$STUB/grep"
GUARD_PATH_PREFIX="$STUB"
check "TERM mid-check, an ordinary command" ask "before reaching a verdict" "$(hin Bash 'git status')"
GUARD_PATH_PREFIX=""

# --- a large command: the scanner must stay fast --------------------------------------------
BIG="$(head -c 300000 /dev/zero | tr '\0' 'a')"
START=$(date +%s)
pass_ "300 KB command"                   "echo $BIG"
ask_ "300 KB command, then a push"       "echo $BIG; git push"
ELAPSED=$(( $(date +%s) - START ))
if [ "$ELAPSED" -gt 10 ]; then
  echo "FAIL (large command timing): ${ELAPSED}s for two 300 KB commands."; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|timing"
else
  echo "PASS (large command timing): ${ELAPSED}s for two 300 KB commands."; PASSED=$((PASSED + 1))
fi

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "FAIL: $FAILED failed, $PASSED passed (${FAILED_NAMES#|})."
  exit 1
fi
echo "PASS: all $PASSED cases."
exit 0
