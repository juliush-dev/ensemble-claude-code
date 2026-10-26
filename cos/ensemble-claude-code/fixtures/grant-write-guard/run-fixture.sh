#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/guard-grant-writes.sh, the grant-write
# guard.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It only classifies text: each case feeds the guard
# one PreToolUse input on stdin, as the harness does, and no case runs the
# command it names, so no grant file is ever written. It writes a few files in
# a temp folder of its own and removes them one by one on the way out, with no
# recursive delete. It never touches a deployed home and never runs git. On
# Windows run it from Git Bash: a bare 'bash' typed in PowerShell may start
# WSL's bash.
#
# A case asserts the verdict: pass is exit 0 with no output, ask is exit 0 with
# one ask naming the case's fragment. The guard never denies, so any deny in
# the output fails the case. The command text is written as it sits inside the
# JSON string, escapes included: \" is a double quote, \\ one backslash, \n a
# newline.
#
# The cases: a grant file rebuilt with printf through a variable, and grant
# reads chained with other commands, on placeholder paths; the grant reads the
# Lead makes, in Bash and in PowerShell, which must pass; each write
# shape in both tools and both slash directions; the redirections that write no
# file; a delete, which passes; a cwd inside the folder; commands that never
# name the folder; a description naming it; input the guard cannot read; a
# guard that cannot finish its check; a 300 KB command, timed; and, where a
# Python runs, a check that every ask the guard wrote is valid JSON.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../../hooks/guard-grant-writes.sh"
[ -f "$GUARD" ] || { echo "FAIL (setup): guard not found at $GUARD"; exit 1; }

PASSED=0
FAILED=0
FAILED_NAMES=""
GUARD_PATH_PREFIX=""   # a stub directory put first on the guard's PATH only

TMPBASE="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
case "$TMPBASE" in ""|/|.|[!/]*) echo "FAIL (setup): temp base resolved to '$TMPBASE'"; exit 1 ;; esac
STUB1="$TMPBASE/stub-grep-2"
STUB2="$TMPBASE/stub-grep-term"
ASKS="$TMPBASE/asks.jsonl"
cleanup() {
  rm -f -- "$TMPBASE/stderr.txt" "$ASKS" "$STUB1/grep" "$STUB2/grep"
  rmdir -- "$STUB1" "$STUB2" 2>/dev/null
  rmdir -- "$TMPBASE"
}
trap cleanup EXIT
: > "$ASKS"

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
    printf '%s\n' "$out" >> "$ASKS"
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

# hin <tool> <command as JSON string text> [extra tool_input members] [cwd]
hin() {
  printf '{"session_id":"fixture-session-0","transcript_path":"t.jsonl","cwd":"%s","permission_mode":"auto","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s"%s}}' \
    "${4:-/fixture}" "$1" "$2" "${3:-}"
}
A="looks like a write there"
ask_()  { check "$1" ask "${3:-$A}" "$(hin Bash "$2")"; }
pass_() { check "$1" pass - "$(hin Bash "$2")"; }
pask_()  { check "$1" ask "${3:-$A}" "$(hin PowerShell "$2")"; }
ppass_() { check "$1" pass - "$(hin PowerShell "$2")"; }
txt() { IFS= read -r -d '' "$1" || true; printf -v "$1" '%s' "${!1%$'\n'}"; }

G='C:/cfg/ensemble-claude-code/hooks/session-roots'       # the grant folder, forward slashes
GB='C:\\cfg\\ensemble-claude-code\\hooks\\session-roots'  # the same, backslashes as JSON carries them
GF="$G/\$CLAUDE_CODE_SESSION_ID.txt"

# --- a grant rebuilt through a variable, and grant reads chained with other commands ---------
# The paths are placeholders: C:/cfg is the config home and C:/work holds the
# projects, so the fixture names no host path. Every character the guard reads
# for a shape is kept as such a command carries it.
# The write: the grant file rebuilt with printf through the Bash tool. The
# folder is named only in the variable assignment, the write goes to "$f".
txt REBUILD_WRITE <<'EOF'
f=\"/c/cfg/ensemble-claude-code/hooks/session-roots/$CLAUDE_CODE_SESSION_ID.txt\"; printf '%s\\n' 'C:\\work\\project-a' 'C:\\work\\project-a-notebook' 'C:\\work\\project-a-inbox' 'C:\\work\\project-a-lanes' 'C:\\work\\project-b' > \"$f\" && cat \"$f\"
EOF
# Grant reads chained with other commands, which must pass.
txt CHAIN_READ1 <<'EOF'
echo \"SID=$CLAUDE_CODE_SESSION_ID\"; H=\"C:/cfg/ensemble-claude-code/hooks/session-roots\"; ls \"$H\" 2>/dev/null | tail -5; cat \"$H/$CLAUDE_CODE_SESSION_ID.txt\" 2>/dev/null; echo ---; cd \"C:/work/project-a-inbox/outbox\" && ls -la send-1; grep -n -i \"keyword\" send-1/* | head -40
EOF
txt CHAIN_READ2 <<'EOF'
H=\"C:/cfg/ensemble-claude-code/hooks/session-roots\"; for f in $(ls -t \"$H\" | head -2); do echo \"== $f\"; cat \"$H/$f\"; done; sed -n 51,60p \"C:/work/project-a-inbox/outbox/send-1/questions-1.md\" | cut -c1-400
EOF
txt CHAIN_READ3 <<'EOF'
echo \"SID=$CLAUDE_CODE_SESSION_ID\"; cat \"C:/cfg/ensemble-claude-code/hooks/session-roots/$CLAUDE_CODE_SESSION_ID.txt\" 2>&1 | head -3; cd \"C:/work/project-a-notebook\" && git status --short && grep -n \"Owner's note\" notes.md | cut -c1-80
EOF
txt CHAIN_READ4 <<'EOF'
cd /c/work/project-a-inbox && ls -la outbox/send-1/ && git status --short | head -20 && git log --oneline -3 && cat \"/c/cfg/ensemble-claude-code/hooks/session-roots/$CLAUDE_CODE_SESSION_ID.txt\"; echo \"id=$CLAUDE_CODE_SESSION_ID\"
EOF
ask_  "the printf rebuild through a variable"  "$REBUILD_WRITE" "(shape: redirection)"
ask_  "the message names the command"          "$REBUILD_WRITE" "printf '%s"
ask_  "the message says the path guard is bypassed" "$REBUILD_WRITE" "a shell write goes around that guard"
pass_ "chained read, ls and cat with 2>/dev/null" "$CHAIN_READ1"
pass_ "chained read, a for loop over ls -t"    "$CHAIN_READ2"
pass_ "chained read, cat with 2>&1 | head"     "$CHAIN_READ3"
pass_ "chained read, cat in an && chain"       "$CHAIN_READ4"

# --- the Lead's grant reads must pass ------------------------------------------------------
pass_ "cat the grant file"                     "cat \\\"$GF\\\""
pass_ "cat 2>/dev/null || echo none"           "cat \\\"$GF\\\" 2>/dev/null || echo none"
pass_ "ls the folder"                          "ls \\\"$G\\\""
pass_ "ls -la the folder, trailing slash"      "ls -la \\\"$G/\\\""
pass_ "test -f"                                "test -f \\\"$GF\\\" && echo yes || echo no"
pass_ "[ -f ] && cat"                          "[ -f \\\"$GF\\\" ] && cat \\\"$GF\\\""
pass_ "grep -c the grant file"                 "grep -c . \\\"$GF\\\""
pass_ "cat > /dev/null 2>&1"                   "cat \\\"$GF\\\" > /dev/null 2>&1 && echo present"
pass_ "&>/dev/null"                            "test -s \\\"$GF\\\" &>/dev/null; echo \$?"
pass_ "2>\\\"/dev/null\\\", quoted"            "cat \\\"$GF\\\" 2>\\\"/dev/null\\\""
pass_ "1>&2"                                   "cat \\\"$GF\\\" 1>&2"
pass_ "backslash path, cat"                    "cat \\\"$GB\\\\x.txt\\\""
pass_ "wc -l"                                  "wc -l \\\"$GF\\\""
ppass_ "PowerShell Get-Content"                "Get-Content \\\"$GB\\\\x.txt\\\""
ppass_ "PowerShell Get-Content 2>\$null"       "Get-Content \\\"$GB\\\\x.txt\\\" 2>\$null"
ppass_ "PowerShell Test-Path"                  "Test-Path -LiteralPath \\\"$GB\\\\x.txt\\\""
ppass_ "PowerShell Get-ChildItem"              "Get-ChildItem \\\"$GB\\\""
ppass_ "PowerShell | Out-Null"                 "Get-Content \\\"$GB\\\\x.txt\\\" | Out-Null"
ppass_ "PowerShell *>\$null"                   "Get-Content \\\"$GB\\\\x.txt\\\" *>\$null"
ppass_ "cmd type >NUL"                         "cmd /c type \\\"$GB\\\\x.txt\\\" >NUL"

# --- redirection writes ----------------------------------------------------------------------
ask_ "echo >"                                  "echo 'C:/work/p' > \\\"$GF\\\"" "(shape: redirection)"
ask_ "echo >>"                                 "echo 'C:/work/p' >> \\\"$GF\\\""
ask_ "printf >|"                               "printf 'x\\\\n' >| \\\"$GF\\\""
ask_ "&> to the grant file"                    "echo x &> \\\"$GF\\\""
ask_ ">& to a file"                            "echo x >& \\\"$GF\\\""
ask_ "cat > <<EOF heredoc"                     "cat > \\\"$GF\\\" <<'EOF'\\nC:/work/p\\nEOF"
ask_ "backslash path, >>"                      "echo x >> \\\"$GB\\\\x.txt\\\""
ask_ "SESSION-ROOTS, upper case"               "echo x > \\\"C:/cfg/hooks/SESSION-ROOTS/x.txt\\\""
ask_ "Session-Roots, mixed case"               "echo x > C:/cfg/hooks/Session-Roots/x.txt"
ask_ "cd into the folder, then a bare write"   "cd \\\"$G\\\" && printf 'x' > id.txt"
ask_ "a \\u003e escape counts as >"            "echo x \\u003e \\\"$GF\\\""
ask_ "bash -c with the write inside"           "bash -c 'echo x >> \\\"$GF\\\"'"
pask_ "PowerShell 'x' >"                       "'C:\\\\work\\\\p' > \\\"$GB\\\\x.txt\\\"" "(shape: redirection)"
pask_ "PowerShell >>"                          "'x' >> \\\"$GB\\\\x.txt\\\""

# --- verb writes, Bash -----------------------------------------------------------------------
ask_ "tee"                                     "printf 'x' | tee \\\"$GF\\\"" "(shape: tee)"
ask_ "tee -a, quiet"                           "printf 'x' | tee -a \\\"$GF\\\" >/dev/null" "(shape: tee)"
ask_ "cp"                                      "cp /tmp/g.txt \\\"$GF\\\"" "(shape: copy)"
ask_ "rsync"                                   "rsync /tmp/g.txt \\\"$G/\\\"" "(shape: copy)"
ask_ "mv"                                      "mv /tmp/g.txt \\\"$GF\\\"" "(shape: move)"
ask_ "install"                                 "install -m 644 /tmp/g.txt \\\"$GF\\\"" "(shape: install)"
ask_ "ln -s"                                   "ln -s /tmp/g.txt \\\"$GF\\\"" "(shape: ln)"
ask_ "dd of="                                  "dd if=/tmp/g.txt of=\\\"$GF\\\"" "(shape: dd)"
ask_ "truncate"                                "truncate -s 0 \\\"$GF\\\"" "(shape: truncate)"
ask_ "touch"                                   "touch \\\"$GF\\\"" "(shape: touch)"
ask_ "mkdir -p"                                "mkdir -p \\\"$G\\\"" "(shape: mkdir)"
ask_ "sed -i"                                  "sed -i 's/a/b/' \\\"$GF\\\"" "(shape: sed -i)"
ask_ "sed -i.bak"                              "sed -i.bak '\$a C:/work/p' \\\"$GF\\\"" "(shape: sed -i)"
ask_ "sed -Ei"                                 "sed -Ei 's/a/b/' \\\"$GF\\\"" "(shape: sed -i)"
ask_ "sed --in-place"                          "sed --in-place 's/a/b/' \\\"$GF\\\"" "(shape: sed -i)"
ask_ "perl -pi -e"                             "perl -pi -e 's/a/b/' \\\"$GF\\\"" "(shape: perl -i)"
ask_ "/usr/bin/tee"                            "printf x | /usr/bin/tee \\\"$GF\\\"" "(shape: tee)"
ask_ "cp.exe"                                  "cp.exe a \\\"$GF\\\"" "(shape: copy)"

# --- verb writes, PowerShell -----------------------------------------------------------------
pask_ "Set-Content"                            "Set-Content -Path \\\"$GB\\\\x.txt\\\" -Value 'C:\\\\work\\\\p'" "(shape: Set-Content)"
pask_ "Add-Content"                            "Add-Content \\\"$GB\\\\x.txt\\\" 'C:\\\\work\\\\p'" "(shape: Set-Content)"
pask_ "Out-File"                               "'x' | Out-File -Append \\\"$GB\\\\x.txt\\\"" "(shape: Set-Content)"
pask_ "sc alias"                               "sc \\\"$GB\\\\x.txt\\\" 'x'" "(shape: Set-Content)"
pask_ "ac alias"                               "ac \\\"$GB\\\\x.txt\\\" 'x'" "(shape: Set-Content)"
pask_ "New-Item -ItemType File"                "New-Item -ItemType File -Path \\\"$GB\\\\x.txt\\\" -Value 'x'" "(shape: mkdir)"
pask_ "ni alias"                               "ni \\\"$GB\\\\x.txt\\\"" "(shape: mkdir)"
pask_ "Copy-Item"                              "Copy-Item C:\\\\tmp\\\\g.txt \\\"$GB\\\\x.txt\\\"" "(shape: copy)"
pask_ "Move-Item"                              "Move-Item C:\\\\tmp\\\\g.txt \\\"$GB\\\\x.txt\\\"" "(shape: move)"
pask_ "Rename-Item"                            "Rename-Item \\\"$GB\\\\a.txt\\\" x.txt" "(shape: move)"
pask_ "Tee-Object"                             "'x' | Tee-Object -FilePath \\\"$GB\\\\x.txt\\\"" "(shape: tee)"
pask_ "[IO.File]::WriteAllText"                "[IO.File]::WriteAllText(\\\"$GB\\\\x.txt\\\", 'x')" "(shape: [IO.File])"
pask_ "[System.IO.File]::AppendAllLines"       "[System.IO.File]::AppendAllLines(\\\"$GB\\\\x.txt\\\", @('x'))" "(shape: [IO.File])"
pask_ "StreamWriter"                           "\$w = New-Object System.IO.StreamWriter(\\\"$GB\\\\x.txt\\\")" "StreamWriter"
pask_ "powershell -Command from Bash"          "powershell -Command \\\"Set-Content '$GB\\\\x.txt' 'x'\\\"" "(shape: Set-Content)"

# --- script writes ---------------------------------------------------------------------------
ask_ "python open w"                           "python -c \\\"open(r'$GB\\\\x.txt', 'w').write('x')\\\"" "(shape: script write)"
ask_ "python open a"                           "python -c \\\"open('$GF', 'a').write('x')\\\"" "(shape: script write)"
ask_ "python write_text"                       "python -c \\\"import pathlib; pathlib.Path('$GF').write_text('x')\\\"" "(shape: script write)"
ask_ "node writeFileSync"                      "node -e \\\"require('fs').writeFileSync('$GF', 'x')\\\"" "(shape: script write)"
pass_ "python open r (a read)"                 "python -c \\\"print(open('$GF', 'r').read())\\\""
pass_ "python open, no mode (a read)"          "python -c \\\"print(open('$GF').read())\\\""

# --- a delete passes: it narrows access ------------------------------------------------------
pass_ "rm -f a grant file"                     "rm -f \\\"$GF\\\""
pass_ "unlink"                                 "unlink \\\"$GF\\\""
ppass_ "Remove-Item a grant file"              "Remove-Item -LiteralPath \\\"$GB\\\\x.txt\\\""
ppass_ "del a grant file"                      "del \\\"$GB\\\\x.txt\\\""

# --- a cwd inside the folder -----------------------------------------------------------------
check "cwd in the folder, bare printf >"       ask "runs inside the session-grant folder" "$(hin Bash "printf 'x' > id.txt" '' "$G")"
check "cwd in the folder, backslash form"      ask "runs inside the session-grant folder" "$(hin Bash "echo x >> id.txt" '' "$GB")"
check "cwd in the folder, a read"              pass - "$(hin Bash 'cat id.txt' '' "$G")"

# --- commands that never name the folder -----------------------------------------------------
pass_ "git status"                             'git status'
pass_ "printf > a file elsewhere"              "printf 'x' > out.txt"
pass_ "cp a b"                                 'cp a b'
pass_ "sed -i elsewhere"                       "sed -i 's/a/b/' x.txt"
pass_ "a grant-like file outside the folder"   "echo x > \\\"C:/cfg/hooks/session-root/x.txt\\\""
pass_ "session_roots, underscore"              "echo x > session_roots/x.txt"
ppass_ "PowerShell Set-Content elsewhere"      "Set-Content x.txt 'y'"
check "description names the folder"          pass - "$(hin Bash "printf 'x' > out.txt" ',"description":"write the session-roots grant"')"

# --- over-asks, by design --------------------------------------------------------------------
ask_ "a grant read with stderr to a log"       "cat \\\"$GF\\\" 2>err.txt" "(shape: redirection)"
ask_ "a commit message naming the folder and touch" "git commit -m \\\"session-roots: touch nothing\\\"" "(shape: touch)"

# --- what it does not catch, pinned so a change is seen --------------------------------------
pass_ "MISS: an 8.3 short name"                "echo x > C:/cfg/hooks/SESSIO~1/x.txt"
pass_ "MISS: the name split by quotes"         "echo x > C:/cfg/hooks/ses''sion-roots/x.txt"
pass_ "MISS: a glob"                           "echo x > C:/cfg/hooks/session-r*/x.txt"
pass_ "MISS: a script file the command runs"   'bash /tmp/write-grant.sh'

# --- input the guard cannot read -------------------------------------------------------------
check "no command field, folder named"         ask "could not be read" '{"tool_name":"Bash","tool_input":{"path":"session-roots"}}'
check "not JSON, folder not named"             pass - 'garbage'
check "empty input"                            ask "no tool input" ''

# --- the message stays valid JSON ------------------------------------------------------------
BIGA="$(head -c 260 /dev/zero | tr '\0' 'a')"
ask_ "a cut \\\" at character 300"             "echo $BIGA > session-roots/\\\"x\\\" and more"
BIGB="$(head -c 258 /dev/zero | tr '\0' 'a')"
ask_ "a cut \\u escape at character 300"       "echo $BIGB > session-roots/\\u00e9 and more"
ask_ "a raw tab and a non-ASCII byte"          "echo	x > session-roots/$(printf '\303\251')"

# --- a guard that cannot finish its check: fail-closed ---------------------------------------
# A stub grep first on the guard's PATH (never the fixture's own): exit 2 must
# not read as "no match", and a TERM mid-check must reach the EXIT trap's ask.
mkdir -p "$STUB1" "$STUB2"
printf '#!/bin/sh\nexit 2\n' > "$STUB1/grep"; chmod +x "$STUB1/grep"
GUARD_PATH_PREFIX="$STUB1"
check "grep fails, a grant read"               ask "grep exit status 2" "$(hin Bash "cat \\\"$GF\\\"")"
check "grep fails, the folder not named"       pass - "$(hin Bash 'git status')"
printf '#!/bin/sh\nkill -TERM "$PPID"\nexit 1\n' > "$STUB2/grep"; chmod +x "$STUB2/grep"
GUARD_PATH_PREFIX="$STUB2"
check "TERM mid-check, a grant read"           ask "before reaching a verdict" "$(hin Bash "cat \\\"$GF\\\"")"
GUARD_PATH_PREFIX=""

# --- a large command: the scanner must stay well inside the 10-second timeout -----------------
BIG="$(head -c 300000 /dev/zero | tr '\0' 'a')"
for c in pass read ask; do
  T0=$EPOCHREALTIME
  case "$c" in
    pass) pass_ "300 KB command" "echo $BIG" ;;
    read) pass_ "300 KB command, then a grant read" "echo $BIG; cat \\\"$GF\\\"" ;;
    ask)  ask_ "300 KB command, then a grant write" "echo $BIG; echo x >> \\\"$GF\\\"" "aaa ..." ;;
  esac
  T1=$EPOCHREALTIME
  MS=$(( (${T1%.*} - ${T0%.*}) * 1000 + (10#${T1#*.} - 10#${T0#*.}) / 1000 ))
  if [ "$MS" -gt 5000 ]; then
    echo "FAIL (300 KB timing, $c): ${MS} ms, over half the 10-second timeout."; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|timing $c"
  else
    echo "PASS (300 KB timing, $c): ${MS} ms."; PASSED=$((PASSED + 1))
  fi
done

# --- every ask the guard wrote parses as JSON ------------------------------------------------
PY=""
for p in python3 python; do
  if "$p" -c 'import json' >/dev/null 2>&1; then PY="$p"; break; fi
done
if [ -n "$PY" ]; then
  if R="$("$PY" -c 'import json,sys
n=0
for line in sys.stdin:
    if line.strip():
        json.loads(line); n+=1
print(n)' < "$ASKS" 2>&1)"; then
    echo "PASS (JSON validity): all $R asks parse."; PASSED=$((PASSED + 1))
  else
    echo "FAIL (JSON validity): $R"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|json"
  fi
else
  echo "SKIP (JSON validity): no working Python on PATH; not counted."
fi

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "FAIL: $FAILED failed, $PASSED passed (${FAILED_NAMES#|})."
  exit 1
fi
echo "PASS: all $PASSED cases."
exit 0
