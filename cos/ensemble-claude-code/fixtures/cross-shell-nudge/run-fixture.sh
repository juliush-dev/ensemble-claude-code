#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/nudge-cross-shell.sh, the cross-shell
# nudge, and for the marker cleanup in hooks/session-end-litter-flag.sh.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It writes nothing outside a temp directory it
# removes on the way out and never touches a deployed home: TMPDIR points into
# that directory, so every marker the hook writes lands there. On Windows run it
# from Git Bash: a bare 'bash' typed in PowerShell may start WSL's bash.
#
# Each case feeds the hook one PreToolUse input on stdin, as the harness does,
# and asserts one of three outcomes, always with exit 0 and nothing on stderr:
# silent (no output), fire (the note with the Git Bash host traps), or plain
# (the note without them, as on a host that is not Git Bash). A case may set
# OSTYPE, which bash takes from the environment when it is exported, to stand
# in for such a host.
#
# The cases: a first crossing that fires and a second that stays silent; the
# same session's second agent firing again; a non-crossing command; the false
# shapes the pricing sample found (which python, a grep pattern, an echo
# string) and their kin, after which the same agent's real crossing still
# fires; PowerShell calls; the Git Bash gate on python; a multi-line command,
# an env-prefixed one, powershell, docker exec, and bash with a script file
# (not a crossing); an agent_id forged inside the command text; missing,
# empty and unparseable input; a marker folder that cannot be made; the
# SessionEnd cleanup; and a 300 KB command for speed.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../../hooks/nudge-cross-shell.sh"
END="$HERE/../../hooks/session-end-litter-flag.sh"
[ -f "$HOOK" ] || { echo "FAIL (setup): hook not found at $HOOK"; exit 1; }
[ -f "$END" ] || { echo "FAIL (setup): SessionEnd hook not found at $END"; exit 1; }

PASSED=0
FAILED=0
FAILED_NAMES=""

TMPBASE="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMPBASE"' EXIT
T="$TMPBASE/tmp"
MARKS="$T/ensemble-cross-shell-nudge"
mkdir -p "$T" || { echo "FAIL (setup): mkdir"; exit 1; }

TRAPS='Host traps: the Bash tool halves backslash pairs, in heredocs too, so write backslash-bearing files with the Write tool; Windows Python cannot open /c/... paths, so give it C:/... paths.'
HEAD='{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[cross-shell-nudge] First shell-boundary crossing for this agent.'
TAIL=' Load cross-shell-command-discipline before the next nontrivial crossing."}}'
FIRE="$HEAD $TRAPS$TAIL"
PLAIN="$HEAD$TAIL"

bad() { echo "FAIL ($1): $2"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$1"; }
good() { echo "PASS ($1): $2"; PASSED=$((PASSED + 1)); }

# check <name> <fire|plain|silent> <raw hook input> [OSTYPE] [TMPDIR]
check() {
  local name="$1" expect="$2" json="$3" os="${4:-}" tmp="${5:-$T}" out err rc got
  local extra=()
  [ -z "$os" ] || extra=("OSTYPE=$os")
  out="$(printf '%s' "$json" | env TMPDIR="$tmp" "${extra[@]}" "$BASH" "$HOOK" 2>"$TMPBASE/err")"
  rc=$?
  err="$(cat "$TMPBASE/err")"
  if [ "$rc" -ne 0 ] || [ -n "$err" ]; then
    bad "$name" "exit $rc, stderr: ${err:-<none>}"; return
  fi
  case "$out" in
    "") got=silent ;;
    "$FIRE") got=fire ;;
    "$PLAIN") got=plain ;;
    *) got="unexpected output: $out" ;;
  esac
  if [ "$got" != "$expect" ]; then bad "$name" "expected $expect, got $got"; return; fi
  good "$name" "$expect, exit 0, no stderr"
}

# hin <session> <tool> <command as JSON string text> [agent_id]
hin() {
  local agent=""
  [ -n "${4:-}" ] && agent="\"agent_id\":\"$4\",\"agent_type\":\"builder\","
  printf '{"session_id":"%s","transcript_path":"t.jsonl","cwd":"C:/fixture","permission_mode":"auto","hook_event_name":"PreToolUse",%s"tool_name":"%s","tool_input":{"command":"%s","description":"fixture"},"tool_use_id":"toolu_fixture"}' \
    "$1" "$agent" "$2" "$3"
}

# marker <name> <file> <present|absent>
marker() {
  if [ "$3" = present ] && [ -f "$MARKS/$2" ]; then good "$1" "marker $2 present"
  elif [ "$3" = absent ] && [ ! -e "$MARKS/$2" ]; then good "$1" "marker $2 absent"
  else bad "$1" "marker $2 expected $3"; fi
}

# The Git Bash cases pin OSTYPE to msys, so the fixture asserts the same
# outcomes whichever bash runs it.
G=msys

# --- once per agent ---------------------------------------------------------------------------
check "first crossing, main"                   fire   "$(hin fx-s1 Bash "wsl.exe -- bash -lc 'ls'")" $G
check "second crossing, main, silent"          silent "$(hin fx-s1 Bash "bash -lc 'ls'")" $G
marker "marker for main"                       fx-s1.main present
check "first crossing, second agent"           fire   "$(hin fx-s1 Bash "cmd //c echo hi" a1fixture)" $G
check "second crossing, second agent, silent"  silent "$(hin fx-s1 Bash "ssh host ls" a1fixture)" $G
marker "marker for the second agent"           fx-s1.a1fixture present

# --- not crossings ----------------------------------------------------------------------------
check "plain command"                          silent "$(hin fx-s2 Bash "ls -la /c/Users")" $G
marker "no marker without a crossing"          fx-s2.main absent
check "which python"                           silent "$(hin fx-s3 Bash "which python python3")" $G
check "grep pattern, double-quoted"            silent "$(hin fx-s3 Bash "grep -n \\\"python\\\" notes.md")" $G
check "grep pattern, single-quoted"            silent "$(hin fx-s3 Bash "grep -rn 'powershell|pwsh' .")" $G
check "echo string"                            silent "$(hin fx-s3 Bash "echo \\\"=== ssh host ===\\\"")" $G
check "command -v node"                        silent "$(hin fx-s3 Bash "command -v node")" $G
check "bash with a script file"                silent "$(hin fx-s3 Bash "bash run-fixture.sh")" $G
marker "no marker after the false shapes"      fx-s3.main absent
check "real crossing after the false shapes"   fire   "$(hin fx-s3 Bash "python tools/check.py")" $G

# --- PowerShell -------------------------------------------------------------------------------
check "PowerShell: wsl"                        fire   "$(hin fx-s4 PowerShell "wsl.exe -e ls")" $G
check "PowerShell: python is not a crossing"   silent "$(hin fx-s5 PowerShell "python tools/check.py")" $G
check "PowerShell: nested powershell"          fire   "$(hin fx-s5 PowerShell "powershell -NoProfile -File x.ps1")" $G

# --- the Git Bash gate ------------------------------------------------------------------------
check "python, not Git Bash, silent"           silent "$(hin fx-s6 Bash "python tools/check.py")" linux-gnu
check "ssh, not Git Bash, plain note"          plain  "$(hin fx-s6 Bash "ssh host ls")" linux-gnu
check "python on cygwin-built Git Bash"        fire   "$(hin fx-s6b Bash "py -3 tools/check.py")" cygwin

# --- shapes that are crossings ----------------------------------------------------------------
check "multi-line, python on line 2"           fire   "$(hin fx-s7 Bash "cd /c/work\\npython y.py")" $G
check "env-prefixed wsl"                       fire   "$(hin fx-s8 Bash "MSYS2_ARG_CONV_EXCL='*' wsl.exe bash /mnt/c/x.sh")" $G
check "powershell from Bash"                   fire   "$(hin fx-s9 Bash "powershell.exe -NoProfile -Command Get-Date")" $G
check "docker exec"                            fire   "$(hin fx-s10 Bash "docker exec -it box sh")" $G
check "env-prefixed python"                    fire   "$(hin fx-s11 Bash "PYTHONUTF8=1 python -c 'print(1)'")" $G
check "node after &&"                          fire   "$(hin fx-s12 Bash "cd app && node build.js")" $G

# --- forged key inside the command text -------------------------------------------------------
check "agent_id forged in the command"         fire   "$(hin fx-s13 Bash "echo \\\"agent_id\\\": \\\"forged\\\"; wsl.exe ls")" $G
marker "forged key ignored, main marked"       fx-s13.main present
marker "forged key ignored, no forged marker"  fx-s13.forged absent

# --- input the hook cannot use ----------------------------------------------------------------
check "no session_id"                          silent '{"tool_name":"Bash","tool_input":{"command":"wsl.exe ls"}}' $G
check "empty input"                            silent '' $G
check "unparseable input"                      silent 'not json at all wsl.exe ls' $G
: > "$TMPBASE/not-a-dir"
check "marker folder cannot be made"           silent "$(hin fx-s14 Bash "wsl.exe ls")" $G "$TMPBASE/not-a-dir"

# --- SessionEnd cleanup -----------------------------------------------------------------------
printf '{"session_id":"fx-s1","hook_event_name":"SessionEnd","reason":"other"}' | env TMPDIR="$T" "$BASH" "$END" >/dev/null 2>&1
marker "SessionEnd removes main's marker"      fx-s1.main absent
marker "SessionEnd removes the agent's marker" fx-s1.a1fixture absent
marker "SessionEnd keeps another session's"    fx-s3.main present
check "after SessionEnd a new pass fires"      fire   "$(hin fx-s1 Bash "wsl.exe ls")" $G

# --- speed ------------------------------------------------------------------------------------
BIG=""
for i in $(seq 1 2000); do BIG="$BIG echo 'a$i' \\\"b$i\\\" | grep x;"; done
BIG="$BIG$(head -c 200000 /dev/zero | tr '\0' 'a') python z.py"
START=$(date +%s)
check "300 KB first crossing"                  fire   "$(hin fx-s15 Bash "$BIG")" $G
ELAPSED=$(( $(date +%s) - START ))
if [ "$ELAPSED" -gt 3 ]; then
  bad "large command timing" "${ELAPSED}s for a ${#BIG}-byte command, against the hook's 5 s timeout."
else
  good "large command timing" "${ELAPSED}s for a ${#BIG}-byte command."
fi

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "FAIL: $FAILED failed, $PASSED passed (${FAILED_NAMES#|})."
  exit 1
fi
echo "PASS: all $PASSED cases."
exit 0
