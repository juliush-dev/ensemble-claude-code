#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/guard-scout-bash.sh, the Scout's
# allowlist Bash guard.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It writes nothing, never touches a deployed home,
# never runs the kit and never calls the network: the guard only reads command
# text, and every path below is a string the guard compares, never a file. On
# Windows run it from Git Bash: a bare 'bash' typed in PowerShell may start
# WSL's bash.
#
# Each case feeds the guard one PreToolUse input on stdin, as the harness does,
# and asserts the verdict: pass is exit 0 with no output, block is exit 2 with
# "Scout guard: blocked (<reason>)" and the accepted form on stderr. The guard
# never asks, so any ask or deny fails the case.
#
# Hermetic against the guard's environment reads. POSIX mode unsets
# LOCALAPPDATA, TEMP and TMP and sets TMPDIR=/fixture-tmp, so the scratchpad
# root is /fixture-tmp/claude (and /fixture-tmp/claude-<digits>) and paths
# compare case-sensitively. Windows mode, run only where cygpath is present,
# sets LOCALAPPDATA to C:\FixtureLocal and unsets the rest, so the root is
# C:/FixtureLocal/Temp/claude in its mixed and drive forms and paths compare
# case-insensitively. CLAUDE_CONFIG_DIR names a config home that does not
# exist; the kit word's expanded form is built from it.
#
# The cases, from the guard's header: the accepted form with the kit named by
# its variable (quoted or not) and by its expanded path, each flag, repeated
# spaces, a quoted and an unquoted path, the session anchor (scratchpad_dir)
# present and absent; then every block the header designs: a command that is
# not the kit, a differently cased variable, an environment assignment in
# front, an unknown or second flag, a URL single-quoted, unquoted, unterminated
# or glued, a URL outside https or its character set, each host class the URL
# check refuses, a metacharacter, a second argument or a quote outside the
# quoted arguments, a path outside the root, at the root, ending in a slash or
# with a bad segment, another session's scratchpad or the session's tasks
# folder, a scratchpad_dir outside the root set or carrying an unread escape,
# a JSON newline or tab, a control character, a non-ASCII byte, and input the
# guard cannot read.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../../hooks/guard-scout-bash.sh"
[ -f "$GUARD" ] || { echo "FAIL (setup): guard not found at $GUARD"; exit 1; }

PASSED=0
FAILED=0
FAILED_NAMES=""
MODE=posix

TMPBASE="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMPBASE"' EXIT

# check <name> <pass|block> <fragment or -> <raw hook input>
check() {
  local name="$1" expect="$2" frag="$3" json="$4" out err rc e
  err="$TMPBASE/stderr.txt"
  if [ "$MODE" = posix ]; then
    out="$(printf '%s' "$json" | env -u LOCALAPPDATA -u TEMP -u TMP TMPDIR=/fixture-tmp \
           CLAUDE_CONFIG_DIR=/fixture-config "$BASH" "$GUARD" 2>"$err")"
  else
    out="$(printf '%s' "$json" | env -u TEMP -u TMP -u TMPDIR 'LOCALAPPDATA=C:\FixtureLocal' \
           CLAUDE_CONFIG_DIR=C:/FixtureConfig "$BASH" "$GUARD" 2>"$err")"
  fi
  rc=$?
  e="$(cat "$err")"
  local verdict="?"
  if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ -z "$e" ]; then verdict=pass
  elif [ "$rc" -eq 2 ] && [ -z "$out" ] && printf '%s' "$e" | grep -q '^Scout guard: blocked (' \
       && printf '%s' "$e" | grep -qF 'scout-fetch.sh" [--render|--check]'; then verdict=block
  fi
  if printf '%s%s' "$out" "$e" | grep -qi '"ask"\|"deny"'; then
    echo "FAIL ($MODE: $name): the output carries an ask or a deny."; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$MODE: $name"; return
  fi
  if [ "$verdict" != "$expect" ]; then
    echo "FAIL ($MODE: $name): expected $expect, got $verdict (exit $rc). Output: ${out:-<none>} Stderr: ${e:-<none>}"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$MODE: $name"; return
  fi
  if [ "$frag" != "-" ] && ! printf '%s' "$e" | head -n 1 | grep -qF -- "$frag"; then
    echo "FAIL ($MODE: $name): the block does not name '$frag'. Stderr: $e"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES|$MODE: $name"; return
  fi
  echo "PASS ($MODE: $name): $expect."
  PASSED=$((PASSED + 1))
}

# hin <command as JSON string text> [scratchpad_dir as JSON string text]
hin() {
  local sp=""
  [ -n "${2:-}" ] && sp="\"scratchpad_dir\":\"$2\","
  printf '{"session_id":"fixture-session-0","transcript_path":"t.jsonl","cwd":"/fixture","permission_mode":"auto","hook_event_name":"PreToolUse",%s"agent_id":"a0fixture","agent_type":"scout","tool_name":"Bash","tool_input":{"command":"%s","description":"fixture"}}' \
    "$sp" "$1"
}
ok()  { check "$1" pass - "$(hin "$2" "${3:-}")"; }
no()  { check "$1" block "$2" "$(hin "$3" "${4:-}")"; }

K='\"$CLAUDE_CONFIG_DIR/tools/scout-fetch.sh\"'   # the kit word as the JSON carries it
KU='$CLAUDE_CONFIG_DIR/tools/scout-fetch.sh'
U='\"https://example.com/docs/page\"'

# ================================ POSIX mode ================================
MODE=posix
R=/fixture-tmp/claude
SP="$R/proj/sess-1/scratchpad"
P="$SP/src.md"

# --- the accepted form ------------------------------------------------------------------------
ok "kit quoted, path quoted, anchored"          "$K $U \\\"$P\\\""                      "$SP"
ok "kit unquoted"                               "$KU $U \\\"$P\\\""                     "$SP"
ok "--render"                                   "$K --render $U \\\"$P\\\""             "$SP"
ok "--check"                                    "$K --check $U \\\"$P\\\""              "$SP"
ok "repeated spaces"                            "$K   --render   $U   \\\"$P\\\""       "$SP"
ok "ends trimmed"                               "  $K $U $P  "                          "$SP"
ok "path unquoted"                              "$K $U $P"                              "$SP"
ok "nested path below the scratchpad"           "$K $U $SP/a/b-c/d_e.f.md"              "$SP"
ok "kit by expanded path, quoted"               "\\\"/fixture-config/tools/scout-fetch.sh\\\" $U $P" "$SP"
ok "kit by expanded path, unquoted"             "/fixture-config/tools/scout-fetch.sh $U $P" "$SP"
ok "no scratchpad_dir: the root set alone"      "$K $U $R/other/sess-9/scratchpad/x.md"
ok "per-uid root claude-<digits>"               "$K $U /fixture-tmp/claude-1000/proj/s/scratchpad/x.md"
ok "public dotted quad"                         "$K \\\"https://93.184.215.14/x\\\" $P" "$SP"
ok "port, query and fragment"                   "$K \\\"https://example.com:8443/a?b=1&c=2#f\\\" $P" "$SP"
ok "URL character set in full"                  "$K \\\"https://ex-a.example.org/a_b.c~d%20/e?f=g+h:i,j!k*l'(m)\\\" $P" "$SP"

# --- not the kit ------------------------------------------------------------------------------
no "not the kit"                                "not the retrieval kit"       'ls -la'
no "differently cased variable"                 "not the retrieval kit"       "\\\"\$claude_config_dir/tools/scout-fetch.sh\\\" $U $P" "$SP"
no "expanded path in another case (POSIX)"      "not the retrieval kit"       "/FIXTURE-CONFIG/tools/scout-fetch.sh $U $P" "$SP"
no "environment assignment in front"            "not the retrieval kit"       "BROWSER=x $K $U $P" "$SP"
no "text glued to the kit word"                 "not the retrieval kit"       "${K}x $U $P" "$SP"
no "a second command before the kit"            "not the retrieval kit"       "ls; $K $U $P" "$SP"

# --- flags ------------------------------------------------------------------------------------
no "unknown option"                             "an option the kit does not take" "$K --output $U $P" "$SP"
no "second flag"                                "a second flag"               "$K --render --check $U $P" "$SP"

# --- the URL's quoting and shape -----------------------------------------------------------
no "single-quoted URL"                          "a single-quoted URL"         "$K 'https://example.com/' $P" "$SP"
no "unquoted URL"                               "an unquoted URL"             "$K https://example.com/ $P" "$SP"
no "unterminated URL quote"                     "an unterminated quote"       "$K \\\"https://example.com/ $P" "$SP"
no "no path"                                    "no path after the URL"       "$K $U" "$SP"
no "text glued to the URL"                      "text glued to the URL"       "$K ${U}x $P" "$SP"
no "http"                                       "is not https"                "$K \\\"http://example.com/\\\" $P" "$SP"
no "userinfo @"                                 "character outside"           "$K \\\"https://u@host/x\\\" $P" "$SP"
no "a \$ in the URL"                            "character outside"           "$K \\\"https://example.com/\$HOME\\\" $P" "$SP"
no "a backtick in the URL"                      "character outside"           "$K \\\"https://example.com/\`id\`\\\" $P" "$SP"
no "a space in the URL"                         "character outside"           "$K \\\"https://example.com/a b\\\" $P" "$SP"

# --- hosts the URL check refuses ------------------------------------------------------------
no "bracketed IPv6"                             "bracketed IPv6"              "$K \\\"https://[::1]/\\\" $P" "$SP"
no "percent-encoded host"                       "percent-encoding"            "$K \\\"https://%6c%6fcalhost/\\\" $P" "$SP"
no "localhost"                                  "the host is local"           "$K \\\"https://localhost/\\\" $P" "$SP"
no "a .localhost name"                          "the host is local"           "$K \\\"https://app.localhost/\\\" $P" "$SP"
no "a .local name"                              "the host is local"           "$K \\\"https://printer.local/\\\" $P" "$SP"
no "a .internal name"                           "the host is local"           "$K \\\"https://db.internal/\\\" $P" "$SP"
no "a .localdomain name"                        "the host is local"           "$K \\\"https://box.localdomain/\\\" $P" "$SP"
no "home.arpa"                                  "the host is local"           "$K \\\"https://nas.home.arpa/\\\" $P" "$SP"
no "uppercase LOCALHOST"                        "the host is local"           "$K \\\"https://LOCALHOST./\\\" $P" "$SP"
no "single-label host"                          "single label"                "$K \\\"https://intranet/\\\" $P" "$SP"
no "empty label"                                "empty label"                 "$K \\\"https://a..example.com/\\\" $P" "$SP"
no "port not a number"                          "port is not a number"        "$K \\\"https://example.com:x/\\\" $P" "$SP"
no "hex host"                                   "numeric form"                "$K \\\"https://0x7f.1/\\\" $P" "$SP"
no "shorthand numeric"                          "shorthand numeric"           "$K \\\"https://127.1/\\\" $P" "$SP"
no "zero-padded octet"                          "zero-padded octet"           "$K \\\"https://010.1.2.3/\\\" $P" "$SP"
no "octet over 255"                             "not an address"              "$K \\\"https://1.2.3.256/\\\" $P" "$SP"
no "loopback"                                   "local or private"            "$K \\\"https://127.0.0.1/\\\" $P" "$SP"
no "0.x"                                        "local or private"            "$K \\\"https://0.1.2.3/\\\" $P" "$SP"
no "10.x"                                       "local or private"            "$K \\\"https://10.0.0.1/\\\" $P" "$SP"
no "192.168.x"                                  "private address"             "$K \\\"https://192.168.1.1/\\\" $P" "$SP"
no "172.16.x"                                   "private address"             "$K \\\"https://172.16.0.1/\\\" $P" "$SP"
no "172.31.x"                                   "private address"             "$K \\\"https://172.31.255.1/\\\" $P" "$SP"
ok "172.32.x is public"                         "$K \\\"https://172.32.0.1/\\\" $P" "$SP"
no "link-local"                                 "link-local"                  "$K \\\"https://169.254.169.254/\\\" $P" "$SP"
no "shared (carrier) range"                     "shared (carrier)"            "$K \\\"https://100.64.0.1/\\\" $P" "$SP"
no "multicast"                                  "multicast or reserved"       "$K \\\"https://224.0.0.1/\\\" $P" "$SP"

# --- after the URL ----------------------------------------------------------------------------
no "metacharacter after the quoted path"        "metacharacter outside the quoted" "$K $U \\\"$P\\\"; ls" "$SP"
no "pipe after the quoted path"                 "metacharacter outside the quoted" "$K $U \\\"$P\\\" | cat" "$SP"
no "words after the quoted path"                "words after the path"        "$K $U \\\"$P\\\" extra" "$SP"
no "second URL"                                 "words after the path"        "$K $U \\\"https://b.example.com/\\\" $P" "$SP"
no "metacharacter in an unquoted path"          "metacharacter outside the quoted" "$K $U $SP/a\$(id)" "$SP"
no "redirection after an unquoted path"         "metacharacter outside the quoted" "$K $U $P>x" "$SP"
no "words after an unquoted path"               "words after the path"        "$K $U $P extra" "$SP"
no "quote inside an unquoted path"              "a quote inside an unquoted path" "$K $U $SP/a'b" "$SP"
no "backslash in an unquoted path"              "a backslash in an unquoted path" "$K $U $SP\\\\a.md" "$SP"
no "metacharacter in a quoted path"             "a shell metacharacter in the path" "$K $U \\\"$SP/a;b\\\"" "$SP"
no "unterminated path quote"                    "an unterminated quote"       "$K $U \\\"$P" "$SP"

# --- where the path lands ---------------------------------------------------------------------
no "outside the scratchpad"                     "not under the session scratchpad" "$K $U /fixture-tmp/other/x.md" "$SP"
no "a lookalike root"                           "not under the session scratchpad" "$K $U /fixture-tmp/claudex/proj/x.md" "$SP"
no "the root itself"                            "names the scratchpad root"   "$K $U $R/" "$SP"
no "ends in a slash"                            "ends in a slash"             "$K $U $SP/dir/" "$SP"
no "a .. segment"                               "a path segment"              "$K $U $SP/../../sess-2/scratchpad/x.md" "$SP"
no "a dotfile"                                  "a path segment"              "$K $U $SP/.env" "$SP"
no "an empty segment"                           "a path segment"              "$K $U $SP//x.md" "$SP"
no "another session's scratchpad"               "not under this session's own scratchpad" "$K $U $R/proj/sess-2/scratchpad/x.md" "$SP"
no "the session's tasks folder"                 "not under this session's own scratchpad" "$K $U $R/proj/sess-1/tasks/x.md" "$SP"
no "the scratchpad_dir itself"                  "not under this session's own scratchpad" "$K $U $SP" "$SP"
no "another uid's root"                         "not under this session's own scratchpad" "$K $U /fixture-tmp/claude-1001/proj/s/scratchpad/x.md" "/fixture-tmp/claude-1000/proj/s/scratchpad"
no "scratchpad_dir outside the root set"        "not under the scratchpad root set" "$K $U $P" "/elsewhere/scratchpad"
no "scratchpad_dir with an unread escape"       "an escape this guard does not read" "$K $U $P" "$SP\\u0041"

# --- escapes, bytes, unreadable input ---------------------------------------------------------
no "a JSON newline"                             "a newline, tab or other escaped character" "$K $U $P\\nls" "$SP"
no "a JSON tab"                                 "a newline, tab or other escaped character" "$K\\t$U $P" "$SP"
no "a JSON unicode escape"                      "a newline, tab or other escaped character" "$K $U $SP/\\u0041.md" "$SP"
no "a control character"                        "a control character"         "$K $U $P$(printf '\001')" "$SP"
no "a non-ASCII byte in the URL"                "character outside"           "$K \\\"https://exampl$(printf '\303\251').com/\\\" $P" "$SP"
check "no command field"                        block "no command could be read" '{"tool_name":"Bash","tool_input":{}}'
check "empty input"                             block "no command could be read" ''

# =============================== Windows mode ===============================
if command -v cygpath >/dev/null 2>&1; then
  MODE=windows
  WR=C:/FixtureLocal/Temp/claude
  WSP="$WR/proj/sess-1/scratchpad"
  ok "mixed-form path"                          "$K $U \\\"$WSP/x.md\\\""                 "$WSP"
  ok "drive-form path"                          "$K $U /c/FixtureLocal/Temp/claude/proj/sess-1/scratchpad/x.md" "$WSP"
  ok "path in another case"                     "$K $U \\\"c:/fixturelocal/temp/CLAUDE/proj/SESS-1/scratchpad/x.md\\\"" "$WSP"
  ok "backslash path, quoted"                   "$K $U \\\"C:\\\\FixtureLocal\\\\Temp\\\\claude\\\\proj\\\\sess-1\\\\scratchpad\\\\x.md\\\"" "C:\\\\FixtureLocal\\\\Temp\\\\claude\\\\proj\\\\sess-1\\\\scratchpad"
  ok "kit by expanded path in another case"     "c:/fixtureconfig/tools/scout-fetch.sh $U \\\"$WSP/x.md\\\"" "$WSP"
  ok "kit by drive-form path"                   "/c/FixtureConfig/tools/scout-fetch.sh $U \\\"$WSP/x.md\\\"" "$WSP"
  no "outside the root"                         "not under the session scratchpad" "$K $U \\\"C:/FixtureLocal/Temp/other/x.md\\\"" "$WSP"
  no "another session's scratchpad"             "not under this session's own scratchpad" "$K $U \\\"$WR/proj/sess-2/scratchpad/x.md\\\"" "$WSP"
  no "unquoted backslash path"                  "a backslash in an unquoted path" "$K $U C:\\\\FixtureLocal\\\\Temp\\\\claude\\\\proj\\\\sess-1\\\\scratchpad\\\\x.md" "$WSP"
  no "POSIX root is not a root here"            "not under the session scratchpad" "$K $U /fixture-tmp/claude/proj/sess-1/scratchpad/x.md"
else
  echo "SKIP (windows mode): cygpath is not present; the Windows-mode cases did not run."
fi

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "FAIL: $FAILED failed, $PASSED passed (${FAILED_NAMES#|})."
  exit 1
fi
echo "PASS: all $PASSED cases."
exit 0
