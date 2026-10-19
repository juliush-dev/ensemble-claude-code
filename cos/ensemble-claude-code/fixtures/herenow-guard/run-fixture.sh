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
# The cases: the Operator's publish form unflagged (asking with its target,
# new site or slug, inside and outside the session's root), the kit named by
# its expanded path, each excluded flag, metacharacters, a second command, a
# newline, a single-quoted and an unquoted path, a $ in a path, a bad slug, a
# repeated or unquoted title, a direct publish.sh, a PowerShell call, forged
# nested agent_type keys both ways, unparseable input; the main session's and a
# member's publish and key shapes asking, their ordinary commands passing, and
# a Drive read now asking (H13, flipped from pass by the 2026-10-13 build, D2);
# G1 to G32 of that build's spec: the owner-only publish asking, --ordered
# passing inside the root and asking outside it, with no root known, or with
# the delegate crashed or missing, --public asking, the flags combined or
# repeated blocking, the site and Drive reads passing and their bad values
# blocking, case A's drive-put asking unordered and passing ordered inside the
# root, the excluded Drive commands blocking, and the main session's and a
# member's Drive, site-read and Drive-token shapes asking while the kit's
# manifest and a keyless site probe pass; then the fail-toward-decision hardening: a crash forced inside
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
# The belt: the only recursive delete is of this temp base, never of an empty, root or relative path.
case "$TMPBASE" in ""|/|.|[!/]*) echo "FAIL (setup): temp base resolved to '$TMPBASE'"; exit 1 ;; esac
trap 'case "${TMPBASE:-}" in ""|/|.) ;; *) rm -rf -- "$TMPBASE";; esac' EXIT

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
main "main: publish.sh --help"              ask "dispatch to the Operator" "bash \\\"\$HOME/.agents/skills/here-now/scripts/publish.sh\\\" --help"
main "main: the key variable"               ask "dispatch to the Operator" "echo \$HERENOW_API_KEY"
main "main: the key file"                   ask "a key file is never read" "cat ~/.herenow/credentials"
main "main: the kit's publish"              ask "dispatch to the Operator" "$K publish \\\"$SES/site\\\""
main "main: the API by curl"                ask "dispatch to the Operator" "curl -X POST https://here.now/api/v1/publish"
main "main: the kit's check"                pass - "$K check"
main "main: git status"                     pass - "git status"
main "main: a Drive read (H13, flipped from pass to ask, D2)" ask "site and Drive work dispatch to the Operator" "bash \\\"\$HOME/.agents/skills/here-now/scripts/drive.sh\\\" list"
check "main: PowerShell key file, Windows"  ask "a key file is never read" "$(hin PowerShell 'Get-Content $env:USERPROFILE\\.herenow\\credentials')"
check "builder: git status"                 pass - "$(hin Bash "git status" builder)"
check "builder: publish.sh"                 ask "dispatch to the Operator" "$(hin Bash "bash ./scripts/PUBLISH.SH site" builder)"
check "main: empty input"                   ask "no tool input" ""

# --- G1 to G32: owner-only publish, the ordered writes, sites and Drive (the 2026-10-13 build spec) -------
op "G1 publish, no flag, in root"           ask "owner-only by default" "$K publish \\\"$SES/site\\\"" "OUTSIDE"
op "G2 publish --ordered, in root"          pass - "$K publish \\\"$SES/site\\\" --ordered"
op "G3 publish --ordered, outside root"     ask "OUTSIDE the session's root" "$K publish \\\"$OTHER/site\\\" --ordered"
op "G6 publish --public"                    ask "a PUBLIC publish" "$K publish \\\"$SES/site\\\" --public"
op "G7 --public with --ordered"             block "--ordered with --public" "$K publish \\\"$SES/site\\\" --public --ordered"
op "G7 --ordered with --public"             block "--ordered with --public" "$K publish \\\"$SES/site\\\" --ordered --public"
op "G8 --ordered twice"                     block "--ordered given twice" "$K publish \\\"$SES/site\\\" --ordered --ordered"
op "G8 --public twice"                      block "--public given twice" "$K publish \\\"$SES/site\\\" --public --public"
op "G9 update --slug --ordered, in root"    pass - "$K publish \\\"$SES/site\\\" --slug my-site --title \\\"T\\\" --ordered"
op "G10 site-ls"                            pass - "$K site-ls"
op "G11 site-ls with a value"               block "words after site-ls" "$K site-ls \\\"x\\\""
op "G12 site-files quoted slug"             pass - "$K site-files \\\"my-site\\\""
op "G12 site-files bare slug"               pass - "$K site-files my-site"
op "G13 site-files bad slug"                block "slug outside" "$K site-files \\\"Bad_Slug\\\""
op "G14 site-cat"                           pass - "$K site-cat \\\"my-site\\\" \\\"docs/index.html\\\""
op "G15 site-cat with a .. segment"         block ".. segment in the site path" "$K site-cat \\\"my-site\\\" \\\"docs/../../x\\\""
op "G15 site-cat with a leading slash"      block "site path starting with /" "$K site-cat \\\"my-site\\\" \\\"/etc/x\\\""
op "G15 site-cat with a \$"                 block "backtick or backslash in the site path" "$K site-cat \\\"my-site\\\" \\\"\$HOME/x\\\""
op "G15 site-cat with a backslash"          block "backtick or backslash in the site path" "$K site-cat \\\"my-site\\\" \\\"a\\\\\\\\b\\\""
op "G16 drive-ls"                           pass - "$K drive-ls"
op "G17 drive-ls a drive"                   pass - "$K drive-ls \\\"My Drive\\\""
op "G18 drive-ls a drive and a prefix"      pass - "$K drive-ls \\\"My Drive\\\" \\\"notes/\\\""
op "G19 drive-ls three values"              block "more than a drive name and a prefix" "$K drive-ls \\\"My Drive\\\" \\\"notes/\\\" \\\"x\\\""
op "G19 drive-ls a drive starting with -"   block "drive name starting with -" "$K drive-ls \\\"-x\\\""
op "G20 drive-cat"                          pass - "$K drive-cat \\\"My Drive\\\" \\\"rules/check-reality.md\\\""
op "G20 drive-cat with a .. segment"        block ".. segment in the drive path" "$K drive-cat \\\"My Drive\\\" \\\"../x\\\""
op "G21 case A, unordered drive-put"        ask "drive My Drive, path rules/check-reality.md, local file $SES/rules/check-reality.md" \
  "$K drive-put \\\"My Drive\\\" \\\"rules/check-reality.md\\\" --from \\\"$SES/rules/check-reality.md\\\"" "OUTSIDE"
op "G22 case A, ordered drive-put in root"  pass - "$K drive-put \\\"My Drive\\\" \\\"rules/check-reality.md\\\" --from \\\"$SES/rules/check-reality.md\\\" --ordered"
op "G22 --ordered before --from"            pass - "$K drive-put \\\"My Drive\\\" \\\"rules/check-reality.md\\\" --ordered --from \\\"$SES/rules/check-reality.md\\\""
op "G23 case A ordered, file outside root"  ask "local file lies OUTSIDE the session's root" \
  "$K drive-put \\\"My Drive\\\" \\\"rules/check-reality.md\\\" --from \\\"$OTHER/check-reality.md\\\" --ordered"
op "G24 drive-put without --from"           block "without --from" "$K drive-put \\\"My Drive\\\" \\\"a.md\\\""
op "G24 drive-put --from twice"             block "--from given twice" "$K drive-put \\\"My Drive\\\" \\\"a.md\\\" --from \\\"$SES/a.md\\\" --from \\\"$SES/b.md\\\""
op "G24 drive-put --token"                  block "an option drive-put does not take (--token)" "$K drive-put \\\"My Drive\\\" \\\"a.md\\\" --from \\\"$SES/a.md\\\" --token t"
op "G24 drive-put --ordered twice"          block "--ordered given twice" "$K drive-put \\\"My Drive\\\" \\\"a.md\\\" --from \\\"$SES/a.md\\\" --ordered --ordered"
op "G25 drive-share"                        block "no subcommand" "$K drive-share \\\"My Drive\\\""
op "G25 drive-rm"                           block "no subcommand" "$K drive-rm \\\"My Drive\\\" \\\"a.md\\\""
op "G26 drive.sh directly"                  block "not the here.now kit" "bash \\\"\$HOME/.agents/skills/here-now/scripts/drive.sh\\\" ls"
main "G27 main: drive.sh ls"                ask "site and Drive work dispatch to the Operator" "bash \\\"\$HOME/.agents/skills/here-now/scripts/drive.sh\\\" ls"
main "G28 main: drive.sh share"             ask "dispatch to the Operator" "bash \\\"\$HOME/.agents/skills/here-now/scripts/drive.sh\\\" share \\\"My Drive\\\" --perms write"
main "G29 main: the kit's site-ls"          ask "dispatch to the Operator" "$K site-ls"
main "G29 main: the kit's drive-cat"        ask "dispatch to the Operator" "$K drive-cat \\\"My Drive\\\" \\\"a.md\\\""
main "G29 main: the kit's drive-put"        ask "dispatch to the Operator" "$K drive-put \\\"My Drive\\\" \\\"a.md\\\" --from \\\"$SES/a.md\\\" --ordered"
main "G29 main: the kit's manifest"         pass - "$K manifest \\\"$SES/site\\\""
main "G30 main: the Drive token"            ask "dispatch to the Operator" "echo \$HERENOW_DRIVE_TOKEN"
main "G31 main: the Drive API by curl"      ask "dispatch to the Operator" "curl https://here.now/api/v1/drives"
main "G32 main: a keyless site probe"       pass - "curl -s https://x-1.here.now/"
check "G32 builder: drive.sh"               ask "dispatch to the Operator" "$(hin Bash "bash ./scripts/drive.sh ls" builder)"
# No session root the gate can know: the delegate would pass, so --ordered asks.
NOROOT="{\"session_id\":\"fixture-session-0\",\"hook_event_name\":\"PreToolUse\",\"agent_id\":\"a0fixture\",\"agent_type\":\"operator\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$K publish \\\"$SES/site\\\" --ordered\"}}"
check "G2b --ordered, no session root known" ask "knows no session root" "$NOROOT"

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
op "G4 publish --ordered, delegate crashes"  ask "check failed (exit status 3)" "$K publish \\\"$SES/site\\\" --ordered"
op "G4 drive-put --ordered, delegate crashes" ask "check failed (exit status 3)" "$K drive-put \\\"My Drive\\\" \\\"a.md\\\" --from \\\"$SES/a.md\\\" --ordered"
RUN_GUARD="$TMPBASE/hooks-alone/guard-herenow.sh"
op "operator: publish, delegate missing"    ask "is not beside the gate" "$K publish \\\"$OTHER/site\\\""
op "G5 publish --ordered, delegate missing" ask "is not beside the gate" "$K publish \\\"$SES/site\\\" --ordered"
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
