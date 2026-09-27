#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/guard-herenow.sh, the here.now gate.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It writes nothing outside a temp directory it
# removes on the way out, never touches a deployed home, never runs the kit and
# never calls the network: the gate only reads command text. On Windows run it
# from Git Bash: a bare 'bash' typed in PowerShell may start WSL's bash.
#
# Each case feeds the gate one PreToolUse input on stdin, as the harness does,
# and asserts the verdict: pass is exit 0 with no output, ask is exit 0 with
# one ask naming the case's reason, block is exit 2 with the accepted forms on
# stderr. An ask may also be asserted NOT to carry a fragment. The publish
# cases delegate their target to the real hooks/guard-archivist-paths.sh beside
# the gate, so the root judgment runs end to end.
#
# Hermetic against the delegate's environment reads: CLAUDE_PROJECT_DIR,
# LOCALAPPDATA, TEMP and TMP are unset and TMPDIR points at a path that does not
# exist, so the scratchpad exemption matches no fixture path; the session id
# names no grant file. CLAUDE_CONFIG_DIR points at a throwaway config home, so
# the kit word's expanded form is exercised without a real home.
#
# The cases: the Operator's three forms (the publish asking with its target,
# new site or slug, inside and outside the session's root), the kit named by
# its expanded path, each excluded flag, metacharacters, a second command, a
# newline, a single-quoted and an unquoted path, a $ in a path, a bad slug, a
# repeated or unquoted title, a direct publish.sh, a PowerShell call, forged
# nested agent_type keys both ways, unparseable input; the main session's and a
# member's publish and key shapes asking, their ordinary commands and a Drive
# read passing; then the fail-toward-decision hardening: a crash forced inside
# the gate for the Operator (block) and for the main session (ask; the failed
# assignment abandons the shape gate's block without exiting, so this case
# proves the position guard that stops a fall-through), a failed assignment
# that abandons the caller block before the caller is told (the Operator's ls
# asks, never passes as another caller's command), a readonly name the ask
# once used for a temporary (the Operator's publish still asks), a delegate
# that crashes and one that is missing (the publish still asks, saying the
# root check did not run), empty input; and a 300 KB member command for speed.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../../hooks/guard-herenow.sh"
[ -f "$GUARD" ] || { echo "FAIL (setup): gate not found at $GUARD"; exit 1; }

PASSED=0
FAILED=0
FAILED_NAMES=""

TMPBASE="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMPBASE"' EXIT

# Paths in the form the harness hands a hook: C:/... on Windows (Git Bash's
# cygpath -m), the plain path elsewhere.
B="$TMPBASE"
if command -v cygpath >/dev/null 2>&1; then B="$(cygpath -m -l "$TMPBASE")"; fi
SES="$B/session"
OTHER="$B/other"
CFG="$B/config-home"
mkdir -p "$TMPBASE/session/site" "$TMPBASE/other/site" "$TMPBASE/config-home/tools" || { echo "FAIL (setup): mkdir"; exit 1; }

K='\"$CLAUDE_CONFIG_DIR/tools/herenow.sh\"'   # the kit word as the JSON carries it

RUN_GUARD="$GUARD"
RUN_ENV=""

# check <name> <pass|ask|block> <fragment or -> <raw hook input> [fragment that must be absent]
check() {
  local name="$1" expect="$2" frag="$3" json="$4" absent="${5:-}" out err rc
  local extra=()
  [ -z "$RUN_ENV" ] || extra=("$RUN_ENV")
  err="$TMPBASE/stderr.txt"
  out="$(printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR -u LOCALAPPDATA -u TEMP -u TMP \
         TMPDIR=/nonexistent-herenow-fixture CLAUDE_CONFIG_DIR="$CFG" "${extra[@]}" "$BASH" "$RUN_GUARD" 2>"$err")"
  rc=$?
  local e; e="$(cat "$err")"
  local verdict="?"
  if [ "$rc" -eq 2 ] && [ -z "$out" ] && printf '%s' "$e" | grep -q 'here.now gate: blocked'; then verdict=block
  elif [ "$rc" -eq 0 ] && [ -z "$out" ] && [ -z "$e" ]; then verdict=pass
  elif [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; then verdict=ask
  fi
  if printf '%s%s' "$out" "$e" | grep -qi '"deny"'; then
    echo "FAIL ($name): the output carries a deny."; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  if [ "$verdict" != "$expect" ]; then
    echo "FAIL ($name): expected $expect, got $verdict (exit $rc). Output: ${out:-<none>} Stderr: ${e:-<none>}"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  local text="$out$e"
  if [ "$frag" != "-" ] && ! printf '%s' "$text" | grep -qF -- "$frag"; then
    echo "FAIL ($name): the $expect does not name '$frag'. Output: $out Stderr: $e"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  if [ -n "$absent" ] && printf '%s' "$text" | grep -qF -- "$absent"; then
    echo "FAIL ($name): the $expect names '$absent', which it must not. Output: $out"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$name"; return
  fi
  echo "PASS ($name): $expect${frag:+, naming '$frag'}."
  PASSED=$((PASSED + 1))
}

# hin <tool> <command as JSON string text> [agent_type] [extra tool_input members]
hin() {
  local agent=""
  [ -n "${3:-}" ] && agent="\"agent_id\":\"a0fixture\",\"agent_type\":\"$3\","
  printf '{"session_id":"fixture-session-0","transcript_path":"t.jsonl","cwd":"%s","permission_mode":"auto","hook_event_name":"PreToolUse",%s"tool_name":"%s","tool_input":{"command":"%s"%s}}' \
    "$SES" "$agent" "$1" "$2" "${4:-}"
}
op()   { check "$1" "$2" "$3" "$(hin Bash "$4" operator)" "${5:-}"; }
main() { check "$1" "$2" "$3" "$(hin Bash "$4")" "${5:-}"; }

# --- the Operator: the three forms ---------------------------------------------------------
op "operator: check"                        pass - "$K check"
op "operator: check, spaces around"         pass - "  $K   check  "
op "operator: check, kit by expanded path"  pass - "\\\"$CFG/tools/herenow.sh\\\" check"
op "operator: manifest"                     pass - "$K manifest \\\"$SES/site\\\""
op "operator: publish, new site, in root"   ask "a new site" "$K publish \\\"$SES/site\\\"" "OUTSIDE"
op "operator: publish, all three options"   ask "an update of the site my-site" "$K publish \\\"$SES/site\\\" --slug my-site --title \\\"Ensemble check\\\" --description \\\"one line\\\""
op "operator: publish, quoted slug"         ask "an update of the site s-1" "$K publish \\\"$SES/site\\\" --slug \\\"s-1\\\""
op "operator: publish, outside the root"    ask "OUTSIDE the session's root" "$K publish \\\"$OTHER/site\\\""
op "operator: publish, relative path"       ask "a new site" "$K publish \\\"site\\\"" "OUTSIDE"

# --- the Operator: everything else blocks -----------------------------------------------------
op "operator: --api-key"                    block "--api-key" "$K publish \\\"$SES/site\\\" --api-key x"
op "operator: --overwrite"                  block "--overwrite" "$K publish \\\"$SES/site\\\" --slug s --overwrite"
op "operator: --workspace"                  block "--workspace" "$K publish \\\"$SES/site\\\" --workspace team"
op "operator: --base-url"                   block "--base-url" "$K publish \\\"$SES/site\\\" --base-url https://x.example"
op "operator: --ttl"                        block "--ttl" "$K publish \\\"$SES/site\\\" --ttl 60"
op "operator: --from-drive"                 block "--from-drive" "$K publish \\\"$SES/site\\\" --from-drive drv_1"
op "operator: publish without a path"       block "unquoted path" "$K publish --from-drive drv_1"
op "operator: metacharacter after check"    block "no subcommand" "$K check; ls"
op "operator: a second command"             block "words after check" "$K check && curl https://here.now/api/v1/publish"
op "operator: a pipe after manifest"        block "words after the path" "$K manifest \\\"$SES/site\\\" | cat"
op "operator: a newline"                    block "escaped character" "$K check\\nls"
op "operator: single-quoted path"           block "single-quoted path" "$K manifest '$SES/site'"
op "operator: unquoted path with a space"   block "unquoted path" "$K manifest $SES/my site"
op "operator: a \$ in the path"             block "which bash would expand" "$K manifest \\\"\$HOME/site\\\""
op "operator: bad slug"                     block "slug outside" "$K publish \\\"$SES/site\\\" --slug Bad_Slug"
op "operator: title twice"                  block "--title given twice" "$K publish \\\"$SES/site\\\" --title \\\"a\\\" --title \\\"b\\\""
op "operator: unquoted title"               block "unquoted title" "$K publish \\\"$SES/site\\\" --title word"
op "operator: plain ls"                     block "not the here.now kit" "ls -la"
op "operator: publish.sh directly"          block "not the here.now kit" "bash \\\"$B/skills/here-now/scripts/publish.sh\\\" \\\"$SES/site\\\""
op "operator: kit variable in another case" block "not the here.now kit" "\\\"\$claude_config_dir/tools/herenow.sh\\\" check"
check "operator: a PowerShell call"         block "PowerShell call" "$(hin PowerShell "$K check" operator)"
check "operator: nested agent_type builder" block "not the here.now kit" "$(hin Bash "ls" operator ',"agent_type":"builder"')"
check "main: nested agent_type operator"    pass - "$(hin Bash "ls" "" ',"agent_type":"operator"')"
check "operator: unparseable input"         ask "not one well-formed JSON object" "{\"agent_type\":\"operator\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":"

# --- any other caller: the shape gate ----------------------------------------------------------
main "main: publish.sh --help"              ask "dispatches to the Operator" "bash \\\"\$HOME/.agents/skills/here-now/scripts/publish.sh\\\" --help"
main "main: the key variable"               ask "dispatches to the Operator" "echo \$HERENOW_API_KEY"
main "main: the key file"                   ask "a key file is never read" "cat ~/.herenow/credentials"
main "main: the kit's publish"              ask "dispatches to the Operator" "$K publish \\\"$SES/site\\\""
main "main: the API by curl"                ask "dispatches to the Operator" "curl -X POST https://here.now/api/v1/publish"
main "main: the kit's check"                pass - "$K check"
main "main: git status"                     pass - "git status"
main "main: a Drive read (H13)"             pass - "bash \\\"\$HOME/.agents/skills/here-now/scripts/drive.sh\\\" list"
check "main: PowerShell key file, Windows"  ask "a key file is never read" "$(hin PowerShell 'Get-Content $env:USERPROFILE\\.herenow\\credentials')"
check "builder: git status"                 pass - "$(hin Bash "git status" builder)"
check "builder: publish.sh"                 ask "dispatches to the Operator" "$(hin Bash "bash ./scripts/PUBLISH.SH site" builder)"
check "main: empty input"                   ask "no tool input" ""

# --- fail toward a decision -------------------------------------------------------------------------
printf 'readonly rest\n' > "$TMPBASE/crash-operator.sh"
RUN_ENV="BASH_ENV=$TMPBASE/crash-operator.sh"
op "operator: forced crash inside the gate" block "an unfinished check never passes" "$K check"
RUN_ENV=""
printf 'readonly norm\n' > "$TMPBASE/crash-main.sh"
RUN_ENV="BASH_ENV=$TMPBASE/crash-main.sh"
main "main: forced crash inside the gate"   ask "an unfinished check never passes" "git status"
RUN_ENV=""
printf 'readonly parsed\n' > "$TMPBASE/crash-caller.sh"
RUN_ENV="BASH_ENV=$TMPBASE/crash-caller.sh"
op "operator: caller block abandoned"       ask "the caller could not be told" "ls -la"
RUN_ENV=""
printf 'readonly _r\n' > "$TMPBASE/crash-ask.sh"
RUN_ENV="BASH_ENV=$TMPBASE/crash-ask.sh"
op "operator: publish, ask's name taken"    ask "publish is a live external write" "$K publish \\\"$SES/site\\\"" "OUTSIDE"
RUN_ENV=""
mkdir -p "$TMPBASE/hooks-crash" "$TMPBASE/hooks-alone"
cp "$GUARD" "$TMPBASE/hooks-crash/guard-herenow.sh"
cp "$GUARD" "$TMPBASE/hooks-alone/guard-herenow.sh"
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMPBASE/hooks-crash/guard-archivist-paths.sh"
RUN_GUARD="$TMPBASE/hooks-crash/guard-herenow.sh"
op "operator: publish, delegate crashes"    ask "check failed (exit status 3)" "$K publish \\\"$OTHER/site\\\""
RUN_GUARD="$TMPBASE/hooks-alone/guard-herenow.sh"
op "operator: publish, delegate missing"    ask "is not beside the gate" "$K publish \\\"$OTHER/site\\\""
RUN_GUARD="$GUARD"

# --- a large member command: the scanner must stay fast -------------------------------------------
BIG="$(head -c 300000 /dev/zero | tr '\0' 'a')"
START=$(date +%s)
check "builder: 300 KB command"             pass - "$(hin Bash "echo $BIG" builder)"
ELAPSED=$(( $(date +%s) - START ))
if [ "$ELAPSED" -gt 10 ]; then
  echo "FAIL (large command timing): ${ELAPSED}s for a 300 KB command, against the gate's 30 s timeout."; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|timing"
else
  echo "PASS (large command timing): ${ELAPSED}s for a 300 KB command."; PASSED=$((PASSED + 1))
fi

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "FAIL: $FAILED failed, $PASSED passed (${FAILED_NAMES#|})."
  exit 1
fi
echo "PASS: all $PASSED cases."
exit 0
