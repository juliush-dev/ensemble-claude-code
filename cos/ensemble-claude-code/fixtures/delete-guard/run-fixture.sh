#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/guard-delete.sh, the delete guard.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It only classifies text: each case feeds the guard
# one PreToolUse input on stdin, as the harness does, and no case runs the
# command it names, so no delete shape ever executes. It writes a few files in
# a temp folder of its own and removes them one by one on the way out, with no
# recursive delete. It never touches a deployed home and never runs git. On
# Windows run it from Git Bash: a bare 'bash' typed in PowerShell may start
# WSL's bash.
#
# A case asserts the verdict: pass is exit 0 with no output, ask is exit 0 with
# one ask naming the case's fragment. The guard never denies, so any deny in
# the output fails the case. The command text is written as it sits inside the
# JSON string, escapes included: \n is a newline, \\\n a backslash-newline
# continuation, \" a double quote, \\ one backslash.
#
# The cases: the two lived incident commands of 2026-10-13 verbatim, the
# guarded form (which asks, by decision in v1) and a delete in the project
# root; each of the fourteen shapes in its spellings; the traps (empty targets, quoting,
# subshells, heredocs, JSON escapes, case, paths); the two exemptions, judged
# per segment; ordinary commands that must pass; negative controls; a
# description field naming a delete; input the guard cannot read; a guard that
# cannot finish its check; a 300 KB command, timed; and, where a Python runs,
# a check that every ask the guard wrote is valid JSON.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../../hooks/guard-delete.sh"
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

# hin <tool> <command as JSON string text> [extra tool_input members]
hin() {
  printf '{"session_id":"fixture-session-0","transcript_path":"t.jsonl","cwd":"/fixture","permission_mode":"auto","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s"%s}}' \
    "$1" "$2" "${3:-}"
}
A="deletes or resets a tree"
ask_() { check "$1" ask "${3:-$A}" "$(hin Bash "$2")"; }
pass_() { check "$1" pass - "$(hin Bash "$2")"; }
txt() { IFS= read -r -d '' "$1" || true; printf -v "$1" '%s' "${!1%$'\n'}"; }

# --- the lived commands of 2026-10-13, verbatim from the member transcripts ----------------
# Verbatim but for the host's paths: the user's home and session folders read
# C:/Temp/claude/session/scratchpad and C:/work/repo (and their /c/ forms), so
# the fixture ships with no host path. Every character the guard reads for a
# shape is as it ran.
# The wipe: the clone failed, the && chain skipped the cd, and the ';' let
# find . ... -exec rm -rf run in the project root, where the shell stood.
txt WIPE <<'EOF'
S=\"C:/Temp/claude/session/scratchpad\"; rm -rf \"$S/stage-sim\"; git clone -q \"C:/work/repo/publication/output/worldview\" \"$S/stage-sim\" && cd \"$S/stage-sim\" && git log --oneline -1 && git config core.autocrlf && git config --system core.autocrlf; find . -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} + && cp -r \"C:/work/repo/publication/output/worldview-beat-abc1234/.\" . && git add -A 2>\"$S/add-warnings.txt\"; echo \"add warnings: $(grep -c 'LF will be replaced' \"$S/add-warnings.txt\")\"; echo \"== --summary ==\"; git diff --cached --summary; echo \"== --stat last line ==\"; git diff --cached --stat | tail -1; echo \"== --stat full ==\"; git diff --cached --stat; echo \"== 100755 count ==\"; git ls-files -s | grep -c '^100755 '; echo \"== name-status non-M ==\"; git diff --cached --name-status | grep -v '^M'
EOF
# The near miss: the same shape, the clone succeeded.
txt NEAR <<'EOF'
S=\"/c/Temp/claude/session/scratchpad\"; C=/c/work/repo/publication/output/worldview-beat-abc1234; rm -rf \"$S/stage-sim\" && git -c core.longpaths=true clone -q \"$S/public-clone\" \"$S/stage-sim\" 2>&1 | tail -1; cd \"$S/stage-sim\" && git -c core.longpaths=true reset -q --hard && echo \"sim HEAD $(git rev-parse --short HEAD) tracked=$(git ls-files | wc -l)\"; find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +; cp -r \"$C\"/. .; git -c core.longpaths=true -c core.autocrlf=true add -A 2>\"$S/add-warn.txt\"; echo \"add warnings: $(grep -c 'LF will be replaced' \"$S/add-warn.txt\")\"; echo \"=== --summary\"; git diff --cached --summary; echo \"=== --stat last line\"; git diff --cached --stat | tail -1; echo \"=== 100755 count\"; git ls-files -s | grep -c '^100755 '; echo \"=== name-status\"; git diff --cached --name-status | grep -v '^M'
EOF
# The guarded form: absolute target, cd ... || exit, a $PWD case.
txt GUARDED <<'EOF'
S=\"C:/Temp/claude/session/scratchpad\"; cd \"$S/pub\" || exit 9; case \"$PWD\" in */scratchpad/pub) ;; *) echo \"WRONG DIR $PWD\"; exit 9;; esac; test -d .git || exit 9; find \"$S/pub\" -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} + ; ls -A | tr '\\n' ' '; echo; cp -r \"$S/cand/.\" \"$S/pub/\" || exit 9; git add -A 2>\"$S/add-warnings.txt\"; echo \"add warnings (LF->CRLF): $(grep -c 'LF will be replaced' \"$S/add-warnings.txt\")\"; echo \"== --summary ==\"; git diff --cached --summary; echo \"== --name-status non-M ==\"; git diff --cached --name-status | grep -v '^M'; echo \"== --stat ==\"; git diff --cached --stat; echo \"== 100755 count ==\"; git ls-files -s | grep -c '^100755 '; echo \"== PROVENANCE diff ==\"; git diff --cached -- PROVENANCE.json
EOF
# A delete inside the project tree, outside the session's scratchpad.
txt INROOT <<'EOF'
ls publication/output/ && rm -rf publication/output/worldview-beat-abc1234 2>/dev/null; python publication/publish.py generate --commit abc1234 --profile worldview-edition --out publication/output/worldview-beat-abc1234; echo \"EXIT=$?\"
EOF
ask_ "lived, the wipe"                         "$WIPE"    "(shape: rm -r, find -exec rm)"
ask_ "lived, the near miss"                    "$NEAR"    "(shape: rm -r, find -exec rm, git reset --hard)"
ask_ "lived, the guarded form ASKS in v1"      "$GUARDED" "(shape: rm -r, find -exec rm)"
ask_ "lived, a delete in the project root"     "$INROOT"  "(shape: rm -r)"
ask_ "the message names the command"           "$WIPE"    "rm -rf \\\"\$S/stage-sim\\\""
ask_ "the message says where a failed cd runs" 'rm -rf x' "a failed cd followed by ';' runs the delete where the shell happens to be"
ask_ "the guarded form of the skill"           'cd \"/tmp/claude/s/pub\" || exit 9; case \"$PWD\" in */scratchpad/pub) ;; *) exit 9;; esac; test -d .git || exit 9; find \"/tmp/claude/s/pub\" -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +'
ask_ "lived main: staging wipe in PowerShell"  'Set-Location C:\\x\\publication\\output\\worldview; Get-ChildItem -Force | Where-Object { $_.Name -ne '"'"'.git'"'"' } | Remove-Item -Recurse -Force' "(shape: Remove-Item -Recurse)"
ask_ "lived main: rm -rf of three dirs"        'rm -rf .claude .codex .github'
ask_ "lived main: restore of the tree"         'git restore --source=HEAD --staged --worktree :/' "(shape: git restore of a tree)"
ask_ "lived Builder: rm -r of a skill"         'rm -r skills/skill-frontmatter-discipline'
ask_ "lived Builder: git rm -r"                'git rm -r fixtures/examiner-guard'
ask_ "lived Builder: rm -rf __pycache__"       'rm -rf __pycache__'

# --- shape 1: rm recursive -------------------------------------------------------------------
ask_ "rm -rf"                                  'rm -rf x'
ask_ "rm -fr"                                  'rm -fr x'
ask_ "rm -f -r"                                'rm -f -r x'
ask_ "rm -Rf"                                  'rm -Rf x'
ask_ "rm -rfv"                                 'rm -rfv x'
ask_ "rm --recursive --force"                  'rm --recursive --force x'
ask_ "rm x -r (flag last)"                     'rm x -r'
ask_ "rm -r, flag on a continuation line"      'rm \\\n-rf x'
ask_ "rm -Recurse (PowerShell alias)"          'rm -Recurse x'

# --- shapes 2 to 4: find and xargs -----------------------------------------------------------
ask_ "find -delete"                            'find . -delete' "(shape: find -delete)"
ask_ "find -type f -delete"                    'find /x -type f -name \"*.tmp\" -delete'
ask_ "find -exec, then -delete past an escaped ;" 'find . -exec echo {} \\; -delete'
ask_ "find -exec rm {} \\;"                    'find . -name x -exec rm {} \\;' "(shape: find -exec rm)"
ask_ "find -execdir rm"                        'find . -execdir rm {} +' "(shape: find -exec rm)"
ask_ "find -exec /bin/rm"                      'find . -exec /bin/rm {} +'
ask_ "xargs rm"                                'ls | xargs rm' "(shape: xargs rm)"
ask_ "xargs -0 rm -r"                          'find . -print0 | xargs -0 rm -r' "(shape: rm -r, xargs rm)"

# --- shapes 5 to 8 and 14: git ---------------------------------------------------------------
ask_ "git clean -fd"                           'git clean -fd' "(shape: git clean)"
ask_ "git clean -fdx"                          'git clean -fdx'
ask_ "git -C \"a b\" clean -fd"                'git -C \"a b\" clean -fd'
ask_ "git stash && git clean && git reset"     'git stash && git clean -fdx && git reset --hard' "(shape: git clean, git reset --hard)"
ask_ "git reset --hard"                        'git reset --hard' "(shape: git reset --hard)"
ask_ "git reset --hard HEAD~1"                 'git reset --hard HEAD~1'
ask_ "git reset -q --hard"                     'git -c core.longpaths=true reset -q --hard'
ask_ "git reset --hard, then a JSON newline"   'git reset --hard\nls'
ask_ "git checkout ."                          'git checkout .' "(shape: git checkout of a tree)"
ask_ "git checkout -- ."                       'git checkout -- .'
ask_ "git checkout -- dir/"                    'git checkout -- src/'
ask_ "git checkout :/"                         'git checkout :/'
ask_ "git checkout -f"                         'git checkout -f main'
ask_ "git checkout --force"                    'git checkout --force main'
ask_ "git restore ."                           'git restore .' "(shape: git restore of a tree)"
ask_ "git restore dir/"                        'git restore src/'
ask_ "git restore *"                           'git restore *'
ask_ "git restore --staged --worktree ."       'git restore --staged --worktree .'
ask_ "git restore -SW ."                       'git restore -SW .'
ask_ "git restore -s HEAD . (-s is --source)"  'git restore -s HEAD .'
ask_ "git worktree remove"                     'git worktree remove ../wt' "(shape: git worktree remove)"
ask_ "git worktree remove --force"             'git worktree remove --force ../wt'

# --- the exemptions, judged per segment ------------------------------------------------------
pass_ "git clean -n"                           'git clean -n'
pass_ "git clean -nd"                          'git clean -nd'
pass_ "git clean -dn"                          'git clean -dn'
pass_ "git clean --dry-run -d"                 'git clean --dry-run -d'
pass_ "git clean -fd -n"                       'git clean -fd -n'
pass_ "git clean -fd, -n on a continuation"    'git clean -fd \\\n-n'
pass_ "git restore --staged ."                 'git restore --staged .'
pass_ "git restore -S ."                       'git restore -S .'
pass_ "git restore --staged src/"              'git restore --staged src/'
pass_ "git restore --staged ., then git clean -n" 'git restore --staged . && git clean -n'
ask_ "git clean -n; git clean -fd"             'git clean -n; git clean -fd'
ask_ "git clean -n, a newline, git clean -fd"  'git clean -n\ngit clean -fd'
ask_ "60 dry-run cleans: past 40 segments, ask"  "$(printf 'git clean -n; %.0s' $(seq 60))"
ask_ "git clean -N is not a dry run"           'git clean -N'
ask_ "git restore --staged .; git restore ."   'git restore --staged .; git restore .'
ask_ "git restore --staged ., newline, restore ." 'git restore --staged .\ngit restore .'

# --- shapes 9 and 10: PowerShell and cmd -----------------------------------------------------
ask_ "Remove-Item -Recurse"                    'Remove-Item -Recurse -Force x' "(shape: Remove-Item -Recurse)"
ask_ "Remove-Item -Rec"                        'Remove-Item -Rec x'
ask_ "Remove-Item -r"                          'Remove-Item -LiteralPath x -r'
ask_ "Remove-Item -Recurse:\$true"             'Remove-Item x -Recurse:$true'
ask_ "ri -r"                                   'ri -r x'
ask_ "rd -Recurse"                             'rd -Recurse x'
ask_ "powershell -Command Remove-Item"         'powershell -Command \"Remove-Item -Recurse x\"'
ask_ "cmd /c rmdir /s /q"                      'cmd /c rmdir /s /q x' "(shape: rmdir /s)"
ask_ "rd /s/q"                                 'rd /s/q x'
ask_ "rd /q/s"                                 'rd /q/s x'
ask_ "del /s"                                  'del /s *.tmp'
ask_ "erase /S"                                'erase /S x'
check "PowerShell tool, Remove-Item -Recurse"  ask "(shape: Remove-Item -Recurse)" "$(hin PowerShell 'Remove-Item -Recurse -Force C:\\x')"
check "PowerShell tool, rm -r"                 ask "$A" "$(hin PowerShell 'rm -r x; Write-Host done')"

# --- shapes 11 to 13: libraries and rsync ----------------------------------------------------
ask_ "shutil.rmtree"                           'python -c \"import shutil; shutil.rmtree('"'"'x'"'"')\"' "(shape: rmtree)"
ask_ "rmtree("                                 'python -c \"from shutil import rmtree; rmtree(p)\"'
ask_ "os.removedirs"                           'python -c \"import os; os.removedirs(p)\"'
ask_ "[IO.Directory]::Delete("                 '[System.IO.Directory]::Delete($p, $true)'
ask_ "rmSync recursive: true"                  'node -e \"fs.rmSync('"'"'x'"'"', {recursive: true, force: true})\"' "(shape: rimraf or recursive: true)"
ask_ "recursive:true, JSON-quoted key"         'node -e \"fs.rmSync(p, {\\\"recursive\\\":true})\"'
ask_ "npx rimraf"                              'npx rimraf dist'
ask_ "rsync --delete"                          'rsync -a --delete a/ b/' "(shape: rsync --delete)"
ask_ "rsync --delete-after"                    'rsync -a --delete-after a/ b/'
ask_ "rsync --del, the alias of --delete-during" 'rsync -a --del a/ b/'

# --- traps -----------------------------------------------------------------------------------
ask_ "rm -rf \"\$X\" (X may be empty)"         'rm -rf \"$X\"'
ask_ "rm -rf \"\""                             'rm -rf \"\"'
ask_ "bare rm -rf"                             'rm -rf'
ask_ "rm -rf -- \"\$D\""                       'rm -rf -- \"$D\"'
ask_ "rm with extra spaces"                    'rm   -rf   x'
ask_ "RM -RF, uppercase"                       'RM -RF x'
ask_ "rm.exe"                                  'rm.exe -rf x'
ask_ "/bin/rm"                                 '/bin/rm -rf x'
ask_ "a Windows path to rm.exe"                'C:\\tools\\rm.exe -rf x'
ask_ "backslash rm"                              '\\rm -rf x'
ask_ "sudo rm -rf /"                           'sudo rm -rf /'
ask_ "(rm -rf x)"                              '(rm -rf x)'
ask_ "{ rm -rf x; }"                           '{ rm -rf x; }'
ask_ "\$(rm -rf x)"                            'echo $(rm -rf x)'
ask_ "backticks"                               'echo `rm -rf x`'
ask_ "bash -c \"rm -rf x\""                    'bash -c \"rm -rf x\"'
ask_ "sh -c 'rm -rf x'"                        "sh -c 'rm -rf x'"
ask_ "bash <<EOF with the delete in the body"  'bash <<EOF\nrm -rf x\nEOF'
ask_ "cat > x.sh <<EOF, the delete only written (asks, by design)" 'cat > x.sh <<'"'"'EOF'"'"'\nrm -rf x\nEOF'
ask_ "a JSON \\\"rm -rf x\\\" in a quoted string" 'echo \"rm -rf x\"'
ask_ "a JSON newline before rm"                'ls\nrm -rf x'
ask_ "a JSON tab before rm"                    'ls\trm -rf x'
ask_ "cd x || rm -rf y"                        'cd x || rm -rf y'
ask_ "a cd, ';' and the delete (the incident's shape)" 'cd /x; find . -mindepth 1 -exec rm -rf {} +'

# --- ordinary commands that must pass --------------------------------------------------------
pass_ "ls -la"                                 'ls -la'
pass_ "cat"                                    'cat README.md'
pass_ "grep -rn"                               'grep -rn x .'
pass_ "git status"                             'git status'
pass_ "git diff"                               'git diff'
pass_ "git log"                                'git log --oneline -5'
pass_ "git commit -m \"clean up\""             'git commit -m \"clean up\"'
pass_ "git reset --soft HEAD~1"                'git reset --soft HEAD~1'
pass_ "git reset HEAD file"                    'git reset HEAD file.txt'
pass_ "git checkout -b x"                      'git checkout -b x'
pass_ "git checkout main"                      'git checkout main'
pass_ "git checkout -- file"                   'git checkout -- README.md'
pass_ "git restore file"                       'git restore README.md'
pass_ "git restore -s HEAD file"               'git restore -s HEAD file.txt'
pass_ "git rm --cached"                        'git rm --cached x'
pass_ "git branch -D"                          'git branch -D x'
pass_ "git stash drop"                         'git stash drop'
pass_ "git worktree list"                      'git worktree list'
pass_ "rm file.txt"                            'rm file.txt'
pass_ "rm -f x"                                'rm -f x'
pass_ "rm -i x"                                'rm -i x'
pass_ "rm --force --preserve-root x"           'rm --force --preserve-root x'
pass_ "cp -r a b"                              'cp -r a b'
pass_ "ls -R"                                  'ls -R'
pass_ "diff -r a b"                            'diff -r a b'
pass_ "find -name | head"                      'find . -name \"*.md\" | head'
pass_ "find -exec grep"                        'find . -exec grep -l x {} +'
pass_ "rm -f, then ls -r after ;"              'rm -f x; ls -r'
pass_ "rm -f, then grep -r after &&"           'rm -f x && grep -r y .'
pass_ "Remove-Item x"                          'Remove-Item x'
pass_ "Remove-Item -Force"                     'Remove-Item -Force x'
pass_ "Get-ChildItem -Recurse"                 'Get-ChildItem -Recurse'
pass_ "del x.txt"                              'del x.txt'
pass_ "rd x"                                   'rd x'
pass_ "rsync -a"                               'rsync -a a/ b/'
pass_ "mkdir -p"                               'mkdir -p a/b'
pass_ "bash run-fixture.sh"                    'bash run-fixture.sh'
pass_ "python -I x.py"                         'python -I x.py'
pass_ "the Scout kit call"                     '\"$CLAUDE_CONFIG_DIR/tools/scout-fetch.sh\" \"https://example.com/docs/page\" \"/x/scratchpad/src.md\"'
pass_ "the here.now kit check"                 '\"$CLAUDE_CONFIG_DIR/tools/herenow.sh\" check'
check "description names a delete"            pass - "$(hin Bash 'git status' ',"description":"rm -rf the cache"')"

# --- negative controls -----------------------------------------------------------------------
pass_ "form -r"                                'form -r'
pass_ "perform -r"                             'perform -r'
pass_ "rm-recursive"                           'rm-recursive x'
pass_ "git log --grep=clean"                   'git log --grep=clean'
pass_ "echo \"please clean\""                  'echo \"please clean\"'
pass_ "find -name \"*.delete\""                'find . -name \"*.delete\"'
pass_ "a word ending in rm"                    'confirm -rf'
pass_ "git checkout of a file under ./"        'git checkout ./README.md'

# --- input the guard cannot read -------------------------------------------------------------
check "no command field"                       ask "could not be read" '{"tool_name":"Bash","tool_input":{}}'
check "not JSON"                               ask "could not be read" 'garbage'
check "empty input"                            ask "no tool input" ''

# --- the message stays valid JSON ------------------------------------------------------------
BIGA="$(head -c 292 /dev/zero | tr '\0' 'a')"
ask_ "a cut \\\" at character 300"             "rm -rf $BIGA\\\"x\\\" and more"
BIGB="$(head -c 290 /dev/zero | tr '\0' 'a')"
ask_ "a cut \\u escape at character 300"       "rm -rf $BIGB\\u00e9 and more"
ask_ "a raw tab and a non-ASCII byte"          "rm -rf	x $(printf '\303\251')"

# --- a guard that cannot finish its check: fail-closed ---------------------------------------
# A stub grep first on the guard's PATH (never the fixture's own): exit 2 must
# not read as "no match", and a TERM mid-check must reach the EXIT trap's ask.
mkdir -p "$STUB1" "$STUB2"
printf '#!/bin/sh\nexit 2\n' > "$STUB1/grep"; chmod +x "$STUB1/grep"
GUARD_PATH_PREFIX="$STUB1"
check "grep fails, a delete"                   ask "grep exit status 2" "$(hin Bash 'rm -rf x')"
check "grep fails, an ordinary command"        ask "grep exit status 2" "$(hin Bash 'git status')"
printf '#!/bin/sh\nkill -TERM "$PPID"\nexit 1\n' > "$STUB2/grep"; chmod +x "$STUB2/grep"
GUARD_PATH_PREFIX="$STUB2"
check "TERM mid-check, an ordinary command"    ask "before reaching a verdict" "$(hin Bash 'git status')"
GUARD_PATH_PREFIX=""

# --- a large command: the scanner must stay well inside the 10-second timeout -----------------
BIG="$(head -c 300000 /dev/zero | tr '\0' 'a')"
for c in pass ask; do
  T0=$EPOCHREALTIME
  if [ "$c" = pass ]; then pass_ "300 KB command" "echo $BIG"
  else ask_ "300 KB command, then a delete" "echo $BIG; rm -rf x" "aaa ..."; fi
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
