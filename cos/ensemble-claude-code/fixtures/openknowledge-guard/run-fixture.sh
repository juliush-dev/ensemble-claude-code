#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/guard-openknowledge.sh.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It writes nothing outside a temp directory it
# removes on the way out, and it never touches a deployed home. On Windows it
# marks one folder inside that temp directory case-sensitive (fsutil, no
# elevation needed); the mark goes with the folder. On Windows run
# it from Git Bash: a bare 'bash' typed in PowerShell may start WSL's bash.
#
# Each case feeds the guard one PreToolUse input on stdin, as the harness does,
# and asserts the verdict: pass is no output at all, ask is one ask naming the
# case's reason, deny is exactly one deny object naming the correction, under
# 10,000 characters (the cap the hooks reference names for other hook text;
# it names none for a deny reason, so the fixture holds the tighter one). Every case
# also asserts exit code 0, and that no case expecting pass or ask ever sees a
# deny. The guard delegates each resolved target to the real
# hooks/guard-archivist-paths.sh beside it, so the delegated cases run the one
# path law end to end.
#
# The projects are throwaway OpenKnowledge roots (an .ok/config.yml and nothing
# else) under the temp directory:
#   session/                 the session's own root; content.dir "."
#   session/docs-project/    a nested project with content.dir "docs"
#   session/flow-project/    a config in flow style, which the guard does not read
#   other/                   a project outside the session's root (a foreign root)
#   session-lanes/           a sibling worktree, named the session's plus a suffix
#   noroot/                  no .ok/config.yml at or above it
#   rootabove/               a project with content.dir "Inner", whose inner/
#                            folder serves as a session root below the .ok
#   session/absdocs-project/ a nested project whose content.dir is given
#                            absolute, and lowercased in the file, so its
#                            target's case never depends on cwd's
#   cs/proj/, cs/Proj/       two projects whose names differ only in case, in
#                            a case-sensitive folder, where one can be made
# Hermetic against the delegate's environment reads: CLAUDE_PROJECT_DIR, and
# LOCALAPPDATA, TEMP and TMP are unset and TMPDIR points at a path that does not
# exist, so the scratchpad exemption matches no fixture path; the session id
# names no grant file beside the real guard. The grant cases run copies of the
# guard and its delegate from a temp hooks folder whose session-roots/ holds
# the grant files.
#
# The cases: each tool's path shapes; a batch with one
# escaping path; a .. escape; skill variants; import from the main session and
# from the Operator; the exec tripwire, its commands joined by line breaks and
# its flag split by a backslash included; unknown tool; unknown top-level key;
# unknown nested key; renamed path field; no root, read and write;
# unparseable input; plus a foreign root, the Archivist's silent exit, a
# non-default content.dir, a lint fix over a folder path, escape decoding in
# paths and in exec's command, a
# duplicated target, the batch cap, the harness's backslash cwd form (on
# Windows only), and a large document body for the scanner's speed. Then the
# fail-toward-ask hardening: a crash forced inside the guard (a BASH_ENV file
# makes a variable the guard assigns readonly, so the next read of it is an
# unbound-variable exit), a delegate that crashes, a delegate that is missing;
# and write.asset.source inside and outside the session's root. Then the
# denies: a write-class call without cwd, for the main session and members;
# a cwd naming the session's root or a granted root in another letter case or
# the Git Bash /c/ form (on Windows only, where both reach the same folder),
# each denied with the root's spelling to resend, a grant line below the
# floor ahead of the real grant included; and the controls that must
# not move: a sibling worktree, a foreign root however spelled, a grant line
# below the path guard's floor, a project root above the session's root, an
# absolute content.dir, and the Archivist's silent exit. Last, on a
# case-sensitive folder (made with
# fsutil on Windows, native on Linux; skipped, and said so, where none can be
# made, as on a default macOS volume): a cwd naming a folder that differs from
# the session's root, or a granted root, only in case is another folder, and
# keeps its ask.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../../hooks/guard-openknowledge.sh"
[ -f "$GUARD" ] || { echo "FAIL (setup): guard not found at $GUARD"; exit 1; }

PASSED=0
FAILED=0
FAILED_NAMES=""
SKIP_NOTES=""

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
LANES="$B/session-lanes"
NOROOT="$B/noroot"
ABSDOCS="$SES/absdocs-project"
mkdir -p "$TMPBASE/session/.ok" "$TMPBASE/session/docs-project/.ok" "$TMPBASE/session/docs-project/docs" \
         "$TMPBASE/session/flow-project/.ok" "$TMPBASE/other/.ok" "$TMPBASE/session-lanes/.ok" \
         "$TMPBASE/noroot/sub" "$TMPBASE/rootabove/.ok" "$TMPBASE/rootabove/inner" \
         "$TMPBASE/session/absdocs-project/.ok" || { echo "FAIL (setup): mkdir"; exit 1; }
printf '# fixture project\ncontent:\n  dir: "."\n' > "$TMPBASE/session/.ok/config.yml"
printf 'content:\n  # the docs folder only\n  dir: docs\n' > "$TMPBASE/session/docs-project/.ok/config.yml"
printf 'content: {dir: docs}\n' > "$TMPBASE/session/flow-project/.ok/config.yml"
printf 'content:\n  dir: "."\n' > "$TMPBASE/other/.ok/config.yml"
printf 'content:\n  dir: "."\n' > "$TMPBASE/session-lanes/.ok/config.yml"
printf 'content:\n  dir: Inner\n' > "$TMPBASE/rootabove/.ok/config.yml"
# content.dir absolute, and lowercased in the file: correcting a lowercased cwd
# would not move the target (content is content.dir as written, cwd-independent),
# so the guard's :718 branch must never turn this ask into a deny.
printf 'content:\n  dir: "%s"\n' "${ABSDOCS,,}" > "$TMPBASE/session/absdocs-project/.ok/config.yml"

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
  _s="${_s//@OTHER@/$OTHER}"; _s="${_s//@LANES@/$LANES}"; _s="${_s//@NOROOT@/$NOROOT}"
  printf '%s' "$_s"
}

# The guard a case runs, one extra NAME=VALUE for its environment, and the
# session id and session cwd the input carries; the fault, grant and
# case-sensitive cases below change them for their cases and restore them.
RUN_GUARD="$GUARD"
RUN_ENV=""
SESSION_ID="fixture-session-0"
SESSION_CWD="$SES"

# check <name> <pass|ask|deny> <reason fragment or -> <raw hook input>
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
  elif [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s' "$out" | grep -q '^{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"OpenKnowledge guard: [^"]*"}}$'; then verdict=deny
  fi
  if [ "$rc" -ne 0 ]; then
    echo "FAIL ($name): exit code $rc, expected 0."; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES $name"; return
  fi
  if [ "$expect" != "deny" ] && printf '%s' "$out" | grep -qi 'deny'; then
    echo "FAIL ($name): the output carries a deny: $out"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES $name"; return
  fi
  if [ "$verdict" != "$expect" ]; then
    echo "FAIL ($name): expected $expect, got $verdict. Output: ${out:-<none>}"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES $name"; return
  fi
  if [ "$expect" != "pass" ] && [ "$frag" != "-" ] && ! printf '%s' "$out" | grep -qF -- "$frag"; then
    echo "FAIL ($name): the $expect does not name '$frag'. Output: $out"; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES $name"; return
  fi
  if [ "$expect" = "deny" ] && [ "${#out}" -ge 10000 ]; then
    echo "FAIL ($name): the deny runs ${#out} characters, over the 10,000 cap."; FAILED=$((FAILED + 1)); FAILED_NAMES="$FAILED_NAMES $name"; return
  fi
  if [ "$expect" = "pass" ]; then
    echo "PASS ($name): pass."
  else
    echo "PASS ($name): $expect, naming '$frag'."
  fi
  PASSED=$((PASSED + 1))
}

# tcase <name> <pass|ask|deny> <fragment> <tool> <tool_input JSON with @TOKENS@> [agent_type]
tcase() {
  local agent=""
  [ -n "${6:-}" ] && agent="\"agent_id\":\"a0fixture\",\"agent_type\":\"$6\","
  check "$1" "$2" "$3" "{\"session_id\":\"$SESSION_ID\",\"transcript_path\":\"t.jsonl\",\"cwd\":\"$SESSION_CWD\",\"permission_mode\":\"auto\",\"hook_event_name\":\"PreToolUse\",${agent}\"tool_name\":\"mcp__open-knowledge__$4\",\"tool_input\":$(expand "$5")}"
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

# --- the denies: a cwd the caller can correct ----------------------------------------------
# No cwd on a write-class call: denied for every caller, the Archivist included.
NOCWD="Resend the same call with cwd set to an absolute path inside the OpenKnowledge project you mean to write"
tcase "missing cwd, write"                  deny "$NOCWD" write '{"document":{"path":"x","content":"y"}}'
tcase "missing cwd, edit, Builder"          deny "$NOCWD" edit '{"document":{"path":"x","find":"a","replace":"b"}}' builder
tcase "missing cwd, checkpoint"             deny "$NOCWD" checkpoint '{"summary":"s"}'
tcase "missing cwd, Archivist"              deny "$NOCWD" write '{"document":{"path":"x","content":"y"}}' archivist
# Controls that do not move.
tcase "sibling worktree"                    ask "outside the session's own root" write '{"document":{"path":"x","content":"y"},"cwd":"@LANES@"}'
tcase "sibling worktree, Builder"           ask "outside the session's own root" edit '{"document":{"path":"x","find":"a","replace":"b"},"cwd":"@LANES@"}' builder

# A cwd in another spelling reaches the same folder only where the file system
# folds case and Git Bash reads /c/, so these run on Windows only.
if command -v cygpath >/dev/null 2>&1; then
  _gb="$(cygpath -u "$SES")"
  _ws="$(cygpath -w "$SES")"; _ws="${_ws,,}"; _ws="${_ws//\\/\\\\}"
  WD='{"document":{"path":"notes/a","content":"x"},"cwd":"'
  RESEND="Resend the same call with cwd '$SES'."
  tcase "cwd drive letter lowercase"        deny "$RESEND" write "$WD${SES,}\"}"
  tcase "cwd all lowercase"                 deny "$RESEND" write "$WD${SES,,}\"}"
  tcase "cwd lowercase names the own root"  deny "names the session's own root" write "$WD${SES,,}\"}"
  tcase "cwd lowercase, tail kept"          deny "Resend the same call with cwd '$SES/Notes'." write "$WD${SES,,}/Notes\"}"
  tcase "cwd Git Bash form"                 deny "$RESEND" write "$WD$_gb\"}"
  tcase "cwd backslashes, lowercase"        deny "$RESEND" write "$WD$_ws\"}"
  tcase "cwd lowercase, nested content.dir" deny "Resend the same call with cwd '$DOCS/docs'." write "{\"document\":{\"path\":\"guide/intro\",\"content\":\"x\"},\"cwd\":\"${DOCS,,}/docs\"}"
  # The control's opposite: content.dir absolute, so correcting cwd would not
  # move the target (content is content.dir as written, not built on cwd) -
  # the deny would teach nothing, so this stays an ask.
  tcase "cwd lowercase, absolute content.dir" ask "outside the session's own root" write "{\"document\":{\"path\":\"guide/intro\",\"content\":\"x\"},\"cwd\":\"${ABSDOCS,,}\"}"
  tcase "cwd lowercase, Builder"            deny "$RESEND" edit "{\"document\":{\"path\":\"notes/a\",\"find\":\"a\",\"replace\":\"b\"},\"cwd\":\"${SES,,}\"}" builder
  tcase "cwd Git Bash form, checkpoint"     deny "$RESEND" checkpoint "{\"cwd\":\"$_gb\"}"
  tcase "cwd lowercase, lint fix"           deny "$RESEND" lint "{\"document\":\"notes/a\",\"fix\":true,\"cwd\":\"${SES,,}\"}"
  # Controls: nothing here passed before or asks less now.
  tcase "cwd lowercase, Archivist"          pass - write "$WD${SES,,}\"}" archivist
  tcase "sibling worktree, lowercase"       ask "outside the session's own root" write "$WD${LANES,,}\"}"
  tcase "foreign root, lowercase"           ask "outside the session's own root" write "$WD${OTHER,,}\"}"
  tcase "foreign root, Git Bash form"       ask "outside the session's own root" write "$WD$(cygpath -u "$OTHER")\"}"
  tcase "lowercase cwd, .. path"            ask ".. segment" write "{\"document\":{\"path\":\"../x\",\"content\":\"y\"},\"cwd\":\"${SES,,}\"}"
  # The session's root is rootabove/inner and the project's .ok sits above it,
  # so the target is built on rootabove/ and its content.dir "Inner", and a
  # resent cwd would not move it: no deny that teaches nothing.
  SESSION_CWD="$B/rootabove/inner"
  tcase "project root above the session's"  ask "outside the session's own root" write "{\"document\":{\"path\":\"notes/a\",\"content\":\"x\"},\"cwd\":\"$B/rootabove/INNER\"}"
  SESSION_CWD="$SES"
fi

# --- grants: a root in this session's grant file ---------------------------------------------
# Copies of the guard and its delegate, so the grant files live in a temp
# hooks folder and never beside the real guard.
mkdir -p "$TMPBASE/hooks-grant/session-roots"
cp "$GUARD" "$TMPBASE/hooks-grant/guard-openknowledge.sh"
cp "$HERE/../../hooks/guard-archivist-paths.sh" "$TMPBASE/hooks-grant/guard-archivist-paths.sh"
printf '# granted for the fixture\r\n  %s/  \r\n' "$OTHER" > "$TMPBASE/hooks-grant/session-roots/fixture-session-g.txt"
# Two segments from the anchor (C:/Users on Windows): under the floor.
_floor="$(printf '%s\n' "$B" | cut -d/ -f1-2)"
printf '%s\n' "$_floor" > "$TMPBASE/hooks-grant/session-roots/fixture-session-s.txt"
# The line under the floor first, then the real grant.
printf '%s\n%s\n' "$_floor" "$OTHER" > "$TMPBASE/hooks-grant/session-roots/fixture-session-f.txt"
RUN_GUARD="$TMPBASE/hooks-grant/guard-openknowledge.sh"
SESSION_ID="fixture-session-g"
tcase "granted root, exact spelling"        pass - write '{"document":{"path":"notes/a","content":"x"},"cwd":"@OTHER@"}'
tcase "granted root, Builder"               pass - edit '{"document":{"path":"notes/a","find":"a","replace":"b"},"cwd":"@OTHER@"}' builder
if command -v cygpath >/dev/null 2>&1; then
  tcase "granted root, lowercase"           deny "Resend the same call with cwd '$OTHER'." write "$WD${OTHER,,}\"}"
  tcase "granted root named as granted"     deny "names a root granted to this session" write "$WD${OTHER,,}\"}"
  tcase "granted root, Git Bash form"       deny "Resend the same call with cwd '$OTHER'." write "$WD$(cygpath -u "$OTHER")\"}"
  tcase "own root lowercase, grant present" deny "$RESEND" write "$WD${SES,,}\"}"
  tcase "sibling worktree, grant present"   ask "outside the session's own root" write "$WD${LANES,,}\"}"
  # A grant line below the path guard's three-segment floor never counts, so
  # a cwd under it keeps its ask however it is spelled.
  SESSION_ID="fixture-session-s"
  tcase "grant below the floor, lowercase"  ask "outside the session's own root" write "$WD${OTHER,,}\"}"
  # A cwd that spells the line under the floor exactly and the rest in lower
  # case: that line is passed over, and the real grant below it settles it.
  _tail="${OTHER#"$_floor"}"
  if [ "${_tail,,}" != "$_tail" ]; then
    SESSION_ID="fixture-session-f"
    tcase "floor line spelled exactly first"  deny "Resend the same call with cwd '$OTHER'." write "$WD$_floor${_tail,,}\"}"
  else
    SKIP_NOTES="$SKIP_NOTES [floor line spelled exactly first: the temp path below $_floor has no upper case to fold]"
  fi
fi
SESSION_ID="fixture-session-0"
RUN_GUARD="$GUARD"

# --- case-sensitive: a case variant that is another folder keeps its ask ---------------------
# The fold that finds a misspelled root is only a nomination; the guard denies
# only where both spellings reach one folder ([ A -ef B ]). Here cs/proj and
# cs/Proj are two projects. Windows marks the folder case-sensitive before
# anything is made in it; Linux needs nothing; where the two names still reach
# one folder, the block is skipped and the summary says so.
mkdir -p "$TMPBASE/cs" || { echo "FAIL (setup): mkdir cs"; exit 1; }
if command -v cygpath >/dev/null 2>&1 && command -v fsutil.exe >/dev/null 2>&1; then
  fsutil.exe file setCaseSensitiveInfo "$(cygpath -w "$TMPBASE/cs")" enable >/dev/null 2>&1
fi
mkdir -p "$TMPBASE/cs/proj/.ok" "$TMPBASE/cs/Proj/.ok" || { echo "FAIL (setup): mkdir cs/proj, cs/Proj"; exit 1; }
if ! [ "$TMPBASE/cs/proj" -ef "$TMPBASE/cs/Proj" ]; then
  CS="$B/cs"
  printf 'content:\n  dir: "."\n' > "$TMPBASE/cs/proj/.ok/config.yml"
  printf 'content:\n  dir: "."\n' > "$TMPBASE/cs/Proj/.ok/config.yml"
  CW='{"document":{"path":"notes/a","content":"x"},"cwd":"'
  SESSION_CWD="$CS/proj"
  tcase "case-sensitive: the session's own folder" pass - write "$CW$CS/proj\"}"
  tcase "case-sensitive: case-variant folder"      ask "outside the session's own root" write "$CW$CS/Proj\"}"
  tcase "case-sensitive: case variant, Builder"    ask "outside the session's own root" write "$CW$CS/Proj\"}" builder
  if command -v cygpath >/dev/null 2>&1; then
    tcase "case-sensitive: Git Bash form, own"     deny "Resend the same call with cwd '$CS/proj'." write "$CW$(cygpath -u "$CS/proj")\"}"
    tcase "case-sensitive: Git Bash form, variant" ask "outside the session's own root" write "$CW$(cygpath -u "$CS/Proj")\"}"
  fi
  SESSION_CWD="$SES"
  printf '%s\n' "$CS/proj" > "$TMPBASE/hooks-grant/session-roots/fixture-session-c.txt"
  RUN_GUARD="$TMPBASE/hooks-grant/guard-openknowledge.sh"
  SESSION_ID="fixture-session-c"
  tcase "case-sensitive: granted, variant folder"  ask "outside the session's own root" write "$CW$CS/Proj\"}"
  SESSION_ID="fixture-session-0"
  RUN_GUARD="$GUARD"
else
  SKIP_NOTES="$SKIP_NOTES [case-sensitive block: no case-sensitive folder could be made here, so a case variant that is another folder went untested]"
fi

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
[ -z "$SKIP_NOTES" ] || echo "SKIPPED:$SKIP_NOTES"
if [ "$FAILED" -gt 0 ]; then
  echo "FAIL: $FAILED failed, $PASSED passed (${FAILED_NAMES# })."
  exit 1
fi
echo "PASS: all $PASSED cases."
exit 0
