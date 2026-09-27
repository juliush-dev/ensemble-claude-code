#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/guard-openknowledge.sh.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It writes nothing outside a temp directory it
# removes on the way out, and it never touches a deployed home. On Windows run
# it from Git Bash: a bare 'bash' typed in PowerShell may start WSL's bash.
#
# Each case feeds the guard one PreToolUse input on stdin, as the harness does,
# and asserts the verdict: pass is no output at all, ask is one ask naming the
# case's reason. Every case also asserts exit code 0 and that no output ever
# carries a deny. The guard delegates each resolved target to the real
# hooks/guard-archivist-paths.sh beside it, so the delegated cases run the one
# path law end to end.
#
# The projects are throwaway OpenKnowledge roots (an .ok/config.yml and nothing
# else) under the temp directory:
#   session/                 the session's own root; content.dir "."
#   session/docs-project/    a nested project with content.dir "docs"
#   session/flow-project/    a config in flow style, which the guard does not read
#   other/                   a project outside the session's root (a foreign root)
#   noroot/                  no .ok/config.yml at or above it
# Hermetic against the delegate's environment reads: CLAUDE_PROJECT_DIR, and
# LOCALAPPDATA, TEMP and TMP are unset and TMPDIR points at a path that does not
# exist, so the scratchpad exemption matches no fixture path; the session id
# names no grant file.
#
# The cases: each tool's path shapes; a batch with one
# escaping path; a .. escape; skill variants; import from the main session and
# from the Operator; the exec tripwire, its commands joined by line breaks and
# its flag split by a backslash included; unknown tool; unknown top-level key;
# unknown nested key; renamed path field; missing cwd; no root, read and write;
# unparseable input; plus a foreign root, the Archivist's silent exit, a
# non-default content.dir, a lint fix over a folder path, escape decoding in
# paths and in exec's command, a
# duplicated target, the batch cap, the harness's backslash cwd form (on
# Windows only), and a large document body for the scanner's speed. Then the
# fail-toward-ask hardening: a crash forced inside the guard (a BASH_ENV file
# makes a variable the guard assigns readonly, so the next read of it is an
# unbound-variable exit), a delegate that crashes, a delegate that is missing;
# and write.asset.source inside and outside the session's root.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../../hooks/guard-openknowledge.sh"
[ -f "$GUARD" ] || { echo "FAIL (setup): guard not found at $GUARD"; exit 1; }

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
DOCS="$SES/docs-project"
FLOW="$SES/flow-project"
OTHER="$B/other"
NOROOT="$B/noroot"
mkdir -p "$TMPBASE/session/.ok" "$TMPBASE/session/docs-project/.ok" "$TMPBASE/session/docs-project/docs" \
         "$TMPBASE/session/flow-project/.ok" "$TMPBASE/other/.ok" "$TMPBASE/noroot/sub" || { echo "FAIL (setup): mkdir"; exit 1; }
printf '# fixture project\ncontent:\n  dir: "."\n' > "$TMPBASE/session/.ok/config.yml"
printf 'content:\n  # the docs folder only\n  dir: docs\n' > "$TMPBASE/session/docs-project/.ok/config.yml"
printf 'content: {dir: docs}\n' > "$TMPBASE/session/flow-project/.ok/config.yml"
printf 'content:\n  dir: "."\n' > "$TMPBASE/other/.ok/config.yml"

# The no-root cases need no .ok/config.yml anywhere above the temp directory.
_d="$B"
while :; do
  if [ -f "$_d/.ok/config.yml" ]; then
    echo "FAIL (setup): $_d/.ok/config.yml exists above the temp directory, so the no-root cases cannot run here."
    exit 1
  fi
  case "$_d" in [A-Za-z]:|'') break ;; esac
  _p="${_d%/*}"; [ "$_p" != "$_d" ] || break; _d="$_p"
done

expand() {
  _s="$1"
  _s="${_s//@SES@/$SES}"; _s="${_s//@DOCS@/$DOCS}"; _s="${_s//@FLOW@/$FLOW}"
  _s="${_s//@OTHER@/$OTHER}"; _s="${_s//@NOROOT@/$NOROOT}"
  printf '%s' "$_s"
}

# The guard a case runs, and one extra NAME=VALUE for its environment; the
# fault cases below change them for a single case and restore them.
RUN_GUARD="$GUARD"
RUN_ENV=""

# check <name> <pass|ask> <reason fragment or -> <raw hook input>
check() {
  local name="$1" expect="$2" frag="$3" json="$4" out rc
  local extra=()
  [ -z "$RUN_ENV" ] || extra=("$RUN_ENV")
  out="$(printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR -u LOCALAPPDATA -u TEMP -u TMP \
         TMPDIR=/nonexistent-openknowledge-fixture "${extra[@]}" "$BASH" "$RUN_GUARD" 2>&1)"
  rc=$?
  local verdict="?"
  if [ -z "$out" ]; then verdict=pass
  elif printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; then verdict=ask
  fi
  if [ "$rc" -ne 0 ]; then
    echo "FAIL ($name): exit code $rc, expected 0."; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES $name"; return
  fi
  if printf '%s' "$out" | grep -qi 'deny'; then
    echo "FAIL ($name): the output carries a deny: $out"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES $name"; return
  fi
  if [ "$verdict" != "$expect" ]; then
    echo "FAIL ($name): expected $expect, got $verdict. Output: ${out:-<none>}"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES $name"; return
  fi
  if [ "$expect" = "ask" ] && [ "$frag" != "-" ] && ! printf '%s' "$out" | grep -qF -- "$frag"; then
    echo "FAIL ($name): the ask does not name '$frag'. Output: $out"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES $name"; return
  fi
  if [ "$expect" = "ask" ]; then
    echo "PASS ($name): ask, naming '$frag'."
  else
    echo "PASS ($name): pass."
  fi
  PASSED=$((PASSED + 1))
}

# tcase <name> <pass|ask> <fragment> <tool> <tool_input JSON with @TOKENS@> [agent_type]
tcase() {
  local agent=""
  [ -n "${6:-}" ] && agent="\"agent_id\":\"a0fixture\",\"agent_type\":\"$6\","
  check "$1" "$2" "$3" "{\"session_id\":\"fixture-session-0\",\"transcript_path\":\"t.jsonl\",\"cwd\":\"$SES\",\"permission_mode\":\"auto\",\"hook_event_name\":\"PreToolUse\",${agent}\"tool_name\":\"mcp__open-knowledge__$4\",\"tool_input\":$(expand "$5")}"
}

# --- read tools and the exec tripwire -------------------------------------------
tcase "read: search, no cwd"                pass - search '{"query":"standup"}'
tcase "read: config, no root above cwd"     pass - config '{"cwd":"@NOROOT@/sub"}'
tcase "read: exec ls"                       pass - exec '{"command":"ls notes","cwd":"@SES@"}'
tcase "read: exec grep -o piped to sort"    pass - exec '{"command":"grep -o foo a.md | sort | uniq","cwd":"@SES@"}'
tcase "exec tripwire: find -delete"         ask "find with -delete" exec '{"command":"find . -name x.md -delete","cwd":"@SES@"}'
tcase "exec tripwire: sort -o"              ask "sort with -o" exec '{"command":"cat a.md | sort -o out.md","cwd":"@SES@"}'
tcase "exec tripwire: sort --output"        ask "sort with --output" exec '{"command":"sort --output=out.md a.md","cwd":"@SES@"}'
tcase "exec tripwire: quoted -delete"       ask "find with -delete" exec '{"command":"find . \"-delete\"","cwd":"@SES@"}'
tcase "exec tripwire: newline-joined find"  ask "find with -delete" exec '{"command":"ls notes\nfind . -name x.md -delete","cwd":"@SES@"}'
tcase "exec tripwire: CR-joined sort -o"    ask "sort with -o" exec '{"command":"ls notes\rsort -o out.md a.md","cwd":"@SES@"}'
tcase "exec tripwire: backslash-split flag" ask "find with -delete" exec '{"command":"find . -name x.md -del\\ete","cwd":"@SES@"}'

# --- write ----------------------------------------------------------------------
tcase "write: document, own root"           pass - write '{"document":{"path":"notes/standup","content":"# Standup\n","frontmatter":{"tags":["a"],"odd.key[0]":1}},"cwd":"@SES@"}'
tcase "write: documents batch, own root"    pass - write '{"documents":[{"path":"a/one","content":"x"},{"path":"a/two","content":"y","summary":"s"}],"cwd":"@SES@"}'
tcase "write: batch with one .. path"       ask ".. segment" write '{"documents":[{"path":"a/one","content":"x"},{"path":"../other/steal","content":"y"}],"cwd":"@SES@"}'
tcase "write: cwd in a foreign project"     ask "outside the session's own root" write '{"document":{"path":"x","content":"y"},"cwd":"@OTHER@"}'
tcase "write: foreign root, Archivist"      pass - write '{"document":{"path":"x","content":"y"},"cwd":"@OTHER@"}' archivist
tcase "write: foreign root, Builder"        ask "outside the session's own root" write '{"document":{"path":"x","content":"y"},"cwd":"@OTHER@"}' builder
tcase "write: folder, own root"             pass - write '{"folder":{"path":"ideas","frontmatter":{"title":"Ideas"}},"cwd":"@SES@"}'
tcase "write: template, own root"           pass - write '{"template":{"path":"logs/trip","content":"# {{date}}\n","frontmatter":{"title":"Trip"}},"cwd":"@SES@"}'
tcase "write: asset, own root"              pass - write '{"asset":{"path":"images/d.png","content":"aGk="},"cwd":"@SES@"}'
tcase "write: skill variant"                ask "skill" write '{"skill":{"name":"trip-log","body":"x"},"cwd":"@SES@"}'
tcase "write: absolute path"                ask "is absolute" write '{"document":{"path":"@OTHER@/x","content":"y"},"cwd":"@SES@"}'
tcase "write: non-default content.dir"      pass - write '{"document":{"path":"guide/intro","content":"x"},"cwd":"@DOCS@/docs"}'
tcase "write: content.dir in flow style"    ask "content.dir" write '{"document":{"path":"x","content":"y"},"cwd":"@FLOW@"}'

# --- edit, delete, move ------------------------------------------------------------
tcase "edit: document body, own root"       pass - edit '{"document":{"path":"notes/standup","find":"a","replace":"b"},"cwd":"@SES@"}'
tcase "edit: template, own root"            pass - edit '{"template":{"path":"logs/trip","frontmatter":{"title":"T"}},"cwd":"@SES@"}'
tcase "edit: skill variant, Archivist"      ask "skill" edit '{"skill":{"name":"trip-log","find":"a","replace":"b"},"cwd":"@SES@"}' archivist
tcase "delete: document string"             pass - delete '{"document":"notes/old","cwd":"@SES@"}'
tcase "delete: document array"              pass - delete '{"document":["notes/a","notes/b"],"cwd":"@SES@"}'
tcase "delete: document object, .. escape"  ask ".. segment" delete '{"document":{"path":["notes/a","notes/../../../x"]},"cwd":"@SES@"}'
tcase "delete: folder"                      ask "folder" delete '{"folder":"notes","cwd":"@SES@"}'
tcase "move: from and to, own root"         pass - move '{"from":"notes/a","to":"archive/a","cwd":"@SES@"}'
tcase "move: to escapes by .."              ask ".. segment" move '{"from":"notes/a","to":"../../elsewhere/a","cwd":"@SES@"}'
tcase "move: template, own root"            pass - move '{"template":{"from":"logs/trip","to":"logs/journey"},"cwd":"@SES@"}'
tcase "move: skill variant"                 ask "skill" move '{"skill":{"from":"a","to":"b"},"cwd":"@SES@"}'

# --- lint, checkpoint, restore_version, preview_url -------------------------------
tcase "lint: no fix, no cwd"                pass - lint '{"path":"notes"}'
tcase "lint: fix, own root"                 pass - lint '{"document":"notes/standup","fix":true,"cwd":"@SES@"}'
tcase "lint: fix, no document or path"      ask "names no path" lint '{"fix":true,"cwd":"@SES@"}'
tcase "lint: fix over a folder path"        pass - lint '{"path":"notes","fix":true,"cwd":"@SES@"}'
tcase "checkpoint: own root"                pass - checkpoint '{"summary":"before sweep","cwd":"@SES@"}'
tcase "checkpoint: foreign root"            ask "outside the session's own root" checkpoint '{"cwd":"@OTHER@"}'
tcase "restore_version: document"           pass - restore_version '{"document":"notes/standup","version":"0123456789012345678901234567890123456789","cwd":"@SES@"}'
tcase "restore_version: skill variant"      ask "skill" restore_version '{"skill":"trip-log","version":"0123456789012345678901234567890123456789","cwd":"@SES@"}'
tcase "preview_url: file outside a project" pass - preview_url '{"file":"@NOROOT@/a.md"}'
tcase "preview_url: unknown key"            ask "attachment" preview_url '{"document":"a","attachment":1,"cwd":"@SES@"}'

# --- the always-asks -----------------------------------------------------------------
tcase "resolve_conflict"                    ask "resolve_conflict" resolve_conflict '{"file":"notes/a.md","strategy":"ours","cwd":"@SES@"}'
tcase "import from the main session"        ask "The Operator holds import and install" import '{"source":"owner/repo","add":["claude"],"cwd":"@SES@"}'
tcase "import from the Operator"            ask "The Operator holds import and install" import '{"source":"owner/repo","add":["claude"],"cwd":"@SES@"}' operator
tcase "install"                             ask "The Operator holds import and install" install '{"name":"trip-log","add":["claude"],"cwd":"@SES@"}'

# --- upgrade shapes and malformed input --------------------------------------------------
tcase "unknown tool"                        ask "not in the tool list" frobnicate '{"cwd":"@SES@"}'
tcase "unknown top-level key"               ask "'attachment'" write '{"document":{"path":"x","content":"y"},"attachment":{"path":"x.bin"},"cwd":"@SES@"}'
tcase "unknown nested key"                  ask "'color'" write '{"document":{"path":"x","content":"y","color":"red"},"cwd":"@SES@"}'
tcase "renamed path field"                  ask "'name'" write '{"document":{"name":"x","content":"y"},"cwd":"@SES@"}'
tcase "zero targets"                        ask "names no path" write '{"summary":"nothing","cwd":"@SES@"}'
tcase "escaped key spelling"                ask "does not name" write '{"docu\u006dent":{"path":"x"},"cwd":"@SES@"}'
tcase "duplicated key"                      ask "twice" write '{"document":{"path":"x"},"cwd":"@SES@","cwd":"@OTHER@"}'
tcase "missing cwd, write"                  ask "no tool_input.cwd" write '{"document":{"path":"x","content":"y"}}'
tcase "no root, write"                      ask "no .ok/config.yml" write '{"document":{"path":"x","content":"y"},"cwd":"@NOROOT@/sub"}'
check "unparseable input"                   ask "well-formed" "{\"cwd\":\"$SES\",\"tool_name\":\"mcp__open-knowledge__write\",\"tool_input\":{\"document\":"
check "tool input not an object"            ask "not an object" "{\"cwd\":\"$SES\",\"tool_name\":\"mcp__open-knowledge__write\",\"tool_input\":[1]}"

# --- escapes, duplicates and the batch cap ------------------------------------------------
tcase "path with escaped backslashes"       pass - write '{"document":{"path":"notes\\sub\\a","content":"x"},"cwd":"@SES@"}'
tcase "path with another escape"            ask "escape" write '{"document":{"path":"notes\nx","content":"x"},"cwd":"@SES@"}'
# The escape is assembled at run time, so no editor can decode it in this file.
BS='\'
tcase "exec with a u-escape"                ask "tripwire cannot read" exec "{\"command\":\"find . -del${BS}u0065te\",\"cwd\":\"@SES@\"}"
tcase "lint: fix false is a read"           pass - lint '{"document":"notes/a","fix":false}'
tcase "same path twice"                     pass - write '{"documents":[{"path":"a/one","content":"x"},{"path":"a/one","content":"y"}],"cwd":"@SES@"}'
_many=""
for _i in $(seq 1 101); do _many="$_many{\"path\":\"batch/doc-$_i\"},"; done
tcase "batch over the cap"                  ask "split the batch" write "{\"documents\":[${_many%,}],\"cwd\":\"@SES@\"}"
if command -v cygpath >/dev/null 2>&1; then
  # The harness hands a Windows hook its cwd with backslashes, JSON-escaped.
  _w="$(cygpath -w -l "$TMPBASE/session")"; _w="${_w//\\/\\\\}"
  check "Windows cwd form, backslashes"     pass - "{\"session_id\":\"fixture-session-0\",\"cwd\":\"$_w\",\"tool_name\":\"mcp__open-knowledge__write\",\"tool_input\":{\"document\":{\"path\":\"notes/a\",\"content\":\"x\"},\"cwd\":\"$_w\"}}"
fi

# --- write.asset.source: asks outside the session's root, for every caller ------------------
tcase "asset.source inside the root"        pass - write '{"asset":{"path":"images/in.png","source":"@SES@/assets/in.png"},"cwd":"@SES@"}'
tcase "asset.source outside the root"       ask "outside the session's own root" write '{"asset":{"path":"images/o.png","source":"@OTHER@/secret.png"},"cwd":"@SES@"}'
tcase "asset.source outside, Archivist"     ask "outside the session's own root" write '{"asset":{"path":"images/o.png","source":"@OTHER@/secret.png"},"cwd":"@SES@"}' archivist
tcase "asset.source relative"               ask "not an absolute path" write '{"asset":{"path":"images/r.png","source":"secret.png"},"cwd":"@SES@"}'
tcase "asset.source with a .. segment"      ask ".. segment" write '{"asset":{"path":"images/e.png","source":"@SES@/../other/secret.png"},"cwd":"@SES@"}'

# --- fail toward ask: every internal failure ends in an ask, never a silent exit ---------------
WR='{"document":{"path":"notes/a","content":"x"},"cwd":"@SES@"}'
printf 'readonly E\n' > "$TMPBASE/force-crash.sh"
RUN_ENV="BASH_ENV=$TMPBASE/force-crash.sh"
tcase "forced crash inside the guard"       ask "stopped before reaching a verdict" write "$WR"
RUN_ENV=""
mkdir -p "$TMPBASE/hooks-crash" "$TMPBASE/hooks-alone"
cp "$GUARD" "$TMPBASE/hooks-crash/guard-openknowledge.sh"
cp "$GUARD" "$TMPBASE/hooks-alone/guard-openknowledge.sh"
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMPBASE/hooks-crash/guard-archivist-paths.sh"
RUN_GUARD="$TMPBASE/hooks-crash/guard-openknowledge.sh"
tcase "delegate crashes without output"     ask "failed (exit status 3)" write "$WR"
RUN_GUARD="$TMPBASE/hooks-alone/guard-openknowledge.sh"
tcase "delegate missing"                    ask "is not beside it" write "$WR"
RUN_GUARD="$GUARD"

# --- a large body: the scanner must stay linear -------------------------------------------
BIG="$(head -c 300000 /dev/zero | tr '\0' 'a')"
START=$(date +%s)
tcase "write: 300 KB body, own root"        pass - write "{\"document\":{\"path\":\"big\",\"content\":\"$BIG\"},\"cwd\":\"@SES@\"}"
ELAPSED=$(( $(date +%s) - START ))
if [ "$ELAPSED" -gt 20 ]; then
  echo "FAIL (large body timing): ${ELAPSED}s for a 300 KB body."; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES timing"
else
  echo "PASS (large body timing): ${ELAPSED}s for a 300 KB body."; PASSED=$((PASSED + 1))
fi

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "FAIL: $FAILED failed, $PASSED passed (${FAILED_NAMES# })."
  exit 1
fi
echo "PASS: all $PASSED cases."
exit 0
