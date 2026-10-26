#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/session-start-mod-check.sh, the
# SessionStart check that says when a plugin carrying a hooks module (a mod)
# is present in the COS home.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. Every case stages its own throwaway home (hooks/
# plus whatever plugin records the case needs) in a temp directory removed on
# the way out; it never installs, enables or disables a plugin and never writes
# into a real config home. On Windows run it from Git Bash: a bare 'bash' typed
# in PowerShell may start WSL's bash.
#
# THE CASES. Silence: a clean home, a home with no installed_plugins.json, an
# install path missing on disk, a hooks.json with settings hooks only, the
# word modules inside a description string, an agent_id input. One line each:
# an installed mod with its id and scope, a project-scope mod with its project
# path, a @skills-dir mod, a modules folder in the home's skills/ without a
# plugin.json (it does not load as a plugin), a @synced mod, an installed mod
# set false in enabledPlugins (reported as disabled), two mods in one home
# (module mentions both events, and neither), a module that cannot be read, a
# Windows installPath written with escaped backslashes (only where cygpath is
# present), CLAUDE_CODE_PLUGIN_DIRS with two entries one of them a mod, and the
# same variable set under env in settings.json. The same output on source
# compact and on empty input. The session's project, read from the input's
# cwd: a mod with a plugin.json (it may load), a modules folder without one
# (it does not load as a plugin), a mod set false in enabledPlugins, plain
# skills only (silence), a cwd with spaces in Windows form (where cygpath is
# present), a cwd with non-ASCII letters, no cwd with the hook run from inside
# the project, an empty cwd, a cwd naming a file (all three silent), a cwd
# equal to the home, and a cwd whose .claude is the home, spelled another way
# (the home's own mod named once). The second root, CLAUDE_PROJECT_DIR, unset
# in every other case: naming another project than the cwd (both read), and
# naming the cwd's project under another spelling (read once). The
# cannot-tell line: records that do not parse, records without a "plugins"
# object, records that cannot be read (a folder in the file's place), an entry
# without an installPath, a scan out of time (SECONDS forced past its 3-second
# limit), a project hooks.json that cannot be read, and four failures forced
# before the verdict, one of them in
# the project scan (a BASH_ENV file makes a variable the hook assigns
# readonly; the failed assignment drops the stage it sits in, and the stage
# check or the variable's next read must reach the EXIT trap and its
# cannot-tell line).
# Length: 20 and 40 mods, every mod printed in full or counted in a last line,
# the first line exact, each field at most 10,000 characters, the harness's
# cap per field. Every case must exit 0 with nothing on stderr. Where python3
# or python answers, every output is also parsed as JSON and its
# additionalContext checked against its systemMessage.
#
# THE MOTIVATING CASE. The catalog copy of code-modernization, a plugin whose
# hooks.json carries "modules", is copied into a throwaway home's plugin cache
# with an install record and an enabledPlugins entry, and the hook must name
# it. The copy is looked for at MODCHECK_CATALOG, then in the default config
# home's marketplace folder (~/.claude/plugins/marketplaces/
# claude-plugins-official/plugins/code-modernization), then in
# CLAUDE_CONFIG_DIR's; it is read, never changed. Where claude resolves, claude
# plugin validate --json runs on that copy and on the fixture's own mod, under
# a throwaway CLAUDE_CONFIG_DIR, and the events it lists must agree with what
# the hook says. Without the catalog copy or without claude, those cases print
# SKIP and count neither way.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$HERE/../../hooks/session-start-mod-check.sh"
[ -f "$HOOK_SRC" ] || { echo "FAIL (setup): hook not found at $HOOK_SRC"; exit 1; }

PASSED=0
FAILED=0
SKIPPED=0

TMPBASE="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMPBASE"' EXIT

bad() { echo "FAIL ($1): $2"; FAILED=$((FAILED + 1)); }
good() { echo "PASS ($1): $2"; PASSED=$((PASSED + 1)); }
skip() { echo "SKIP ($1): $2"; SKIPPED=$((SKIPPED + 1)); }

# --- Text the hook must print -------------------------------------------------
ACTIVE='A mod is active in this COS home'
DISABLED='A mod is installed in this COS home but disabled'
L_TELL='[mod-check] Tell the human this at your first answer, before any gated act.'

# mline <open> <id> <where> <mention> <remedy> <path>
mline() {
  printf "[mod-check] %s: %s (%s; %s). A mod can approve a tool call past this home's ask rules, deny rules and guards. Not installed on purpose: %s. Installed on purpose: its word belongs in the project record. claude plugin validate %s lists what it hooks." "$1" "$2" "$3" "$4" "$5" "$6"
}
# dorm <open> <folder name> <mention> <dir>: the line for a modules folder
# with no plugin.json, in the home's skills/ or a project's .claude/skills.
dorm() {
  printf "[mod-check] %s: %s (it has no .claude-plugin/plugin.json, so by the plugin docs it does not load as a plugin; %s). A mod can approve a tool call past this home's ask rules, deny rules and guards. Not installed on purpose: remove its folder, %s. Installed on purpose: its word belongs in the project record. claude plugin validate refuses a folder without that manifest; the module its hooks/hooks.json names shows what it hooks." "$1" "$2" "$3" "$4"
}
uninstall() { printf 'disable it in /plugin (Installed tab) or run claude plugin uninstall %s' "$1"; }
cannot_line() {
  printf "[mod-check] Could not read this COS home's plugin records (%s), so whether a mod is active is unknown. Run claude plugin list in this home to check." "$1"
}

# jesc: one line escaped for a JSON string. jtext: lines escaped and joined
# with \n. Both use sed and awk, never the hook's own bash expansions.
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
jtext() { printf '%s\n' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'; }
want_json() {
  local t
  t="$(jtext "$1")"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s\\n%s"}}' "$t" "$t" "$(jesc "$L_TELL")"
}

# --- Homes, plugins and records -----------------------------------------------
# The fixture's own mod: a two-line module that passes every tool.check on.
MOD_CHECK='export function register(on) {
  on("tool.check", async ($, e, next) => next(e))
}'
MOD_BOTH='export function register(on) {
  on("tool.check", async ($, e, next) => next(e))
  on("tool.call", async ($, e, next) => next(e))
}'
MOD_NEITHER='export function register(on) {
  on("ui.close", async ($, e, next) => next(e))
}'

# mk_home <name>: a throwaway home with the hook in hooks/; sets H.
mk_home() {
  H="$TMPBASE/$1"
  mkdir -p "$H/hooks" "$H/plugins"
  cp "$HOOK_SRC" "$H/hooks/session-start-mod-check.sh"
}
# mk_mod <dir> <name> [module text]
mk_mod() {
  mkdir -p "$1/.claude-plugin" "$1/hooks"
  printf '{"name":"%s","description":"fixture","version":"1.0.0"}\n' "$2" > "$1/.claude-plugin/plugin.json"
  printf '{"modules":["./register.js"]}\n' > "$1/hooks/hooks.json"
  printf '%s\n' "${3:-$MOD_CHECK}" > "$1/hooks/register.js"
}
# mk_plain <dir> <name>: a plugin with a skill and no hooks.
mk_plain() {
  mkdir -p "$1/.claude-plugin" "$1/skills/x"
  printf '{"name":"%s","description":"fixture","version":"1.0.0"}\n' "$2" > "$1/.claude-plugin/plugin.json"
  printf -- '---\nname: x\ndescription: fixture\n---\nx\n' > "$1/skills/x/SKILL.md"
}
# records <file> <entry>...  entry: id|scope|installPath|projectPath
# Written the way Claude Code writes it: version 2, two-space indent.
records() {
  local f="$1" first=1 e id scope path proj
  shift
  {
    printf '{\n  "version": 2,\n  "plugins": {'
    for e in "$@"; do
      IFS='|' read -r id scope path proj <<<"$e"
      [ "$first" = 1 ] || printf ','
      first=0
      printf '\n    "%s": [\n      {\n        "scope": "%s",\n' "$id" "$scope"
      [ -z "$proj" ] || printf '        "projectPath": "%s",\n' "$(jesc "$proj")"
      printf '        "installPath": "%s",\n        "version": "1.0.0",\n' "$(jesc "$path")"
      printf '        "installedAt": "2026-10-01T00:00:00.000Z",\n        "lastUpdated": "2026-10-01T00:00:00.000Z"\n      }\n    ]'
    done
    printf '\n  }\n}\n'
  } > "$f"
}
# enabled <home> <json body of enabledPlugins>
enabled() { printf '{\n  "model": "opus",\n  "enabledPlugins": {%s}\n}\n' "$2" > "$1/settings.json"; }

# --- Running ------------------------------------------------------------------
# hin <source> [agent_id]
hin() {
  local agent=""
  [ -z "${2:-}" ] || agent="\"agent_id\":\"$2\","
  printf '{"session_id":"s1",%s"cwd":"C:\\\\work","hook_event_name":"SessionStart","source":"%s"}' "$agent" "$1"
}
IN_START="$(hin startup)"
# cin <cwd as Claude Code would send it>: a startup input carrying that cwd.
cin() { printf '{"session_id":"s1","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$(jesc "$1")"; }
IN_NOCWD='{"session_id":"s1","hook_event_name":"SessionStart","source":"startup"}'

# run <home> <input> [VAR=value...]: sets OUT, RC, ERR.
run() {
  local h="$1" in="$2"
  shift 2
  OUT="$(printf '%s' "$in" | env -u CLAUDE_CODE_PLUGIN_DIRS -u CLAUDE_PROJECT_DIR -u BASH_ENV "$@" "$BASH" "$h/hooks/session-start-mod-check.sh" 2>"$TMPBASE/err")"
  RC=$?
  ERR="$(cat "$TMPBASE/err")"
}

PY=""
for p in python3 python; do
  if [ "$("$p" -c 'print(7 * 6)' 2>/dev/null)" = 42 ]; then PY="$p"; break; fi
done
# json_ok <name>: OUT parses, names SessionStart, and its additionalContext is
# its systemMessage plus the closing sentence.
json_ok() {
  [ -n "$PY" ] || return 0
  local r
  r="$(printf '%s' "$OUT" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
h = d["hookSpecificOutput"]
s = d["systemMessage"]
ok = h["hookEventName"] == "SessionStart" and h["additionalContext"] == s + "\n" + sys.argv[1]
print("ok %d %d" % (len(s), len(h["additionalContext"])) if ok else "mismatch")
' "$L_TELL" 2>&1)"
  case "$r" in
    ok*) return 0 ;;
    *) bad "$1" "the output is not the expected JSON shape: ${r:0:200}"; return 1 ;;
  esac
}

# diffat <want> <got>: the first place two strings part.
diffat() {
  local i=0 n=${#1}
  [ ${#2} -lt "$n" ] && n=${#2}
  while [ "$i" -lt "$n" ] && [ "${1:i:1}" = "${2:i:1}" ]; do i=$((i + 1)); done
  printf 'at %d: want "%s" got "%s"' "$i" "${1:i:60}" "${2:i:60}"
}

# check <name> <home> <input> <expected text, empty for silence> [VAR=value...]
check() {
  local name="$1" h="$2" in="$3" want="$4" w
  shift 4
  run "$h" "$in" "$@"
  if [ "$RC" -ne 0 ] || [ -n "$ERR" ]; then bad "$name" "exit $RC, stderr: ${ERR:-<none>}"; return; fi
  if [ -z "$want" ]; then
    if [ -z "$OUT" ]; then good "$name" "silent, exit 0, no stderr"; else bad "$name" "expected silence, got: ${OUT:0:200}"; fi
    return
  fi
  w="$(want_json "$want")"
  if [ "$OUT" != "$w" ]; then bad "$name" "unexpected output, $(diffat "$w" "$OUT")"; return; fi
  json_ok "$name" || return
  good "$name" "expected output, exit 0, no stderr"
}

NL=$'\n'
MP="fixture-market"

# --- Silence ------------------------------------------------------------------
mk_home clean
mk_plain "$H/plugins/cache/$MP/plain/1.0.0" plain
records "$H/plugins/installed_plugins.json" "plain@$MP|user|$H/plugins/cache/$MP/plain/1.0.0|"
mkdir -p "$H/skills/onboard" && printf 'x\n' > "$H/skills/onboard/SKILL.md"
enabled "$H" "\"plain@$MP\": true"
check "clean home" "$H" "$IN_START" ""

mk_home norecords
check "no installed_plugins.json" "$H" "$IN_START" ""

mk_home missing
records "$H/plugins/installed_plugins.json" "gone@$MP|user|$H/plugins/cache/$MP/gone/1.0.0|"
check "install path missing on disk" "$H" "$IN_START" ""

mk_home settingshooks
D="$H/plugins/cache/$MP/sh/1.0.0"
mk_plain "$D" sh
mkdir -p "$D/hooks"
printf '{\n  "hooks": {\n    "SessionStart": [{"hooks": [{"type": "command", "command": "true"}]}]\n  }\n}\n' > "$D/hooks/hooks.json"
records "$H/plugins/installed_plugins.json" "sh@$MP|user|$D|"
check "hooks.json with settings hooks only" "$H" "$IN_START" ""

mk_home description
D="$H/plugins/cache/$MP/desc/1.0.0"
mk_plain "$D" desc
mkdir -p "$D/hooks"
printf '{\n  "description": "no modules here, not even \\"modules\\": quoted",\n  "hooks": {}\n}\n' > "$D/hooks/hooks.json"
records "$H/plugins/installed_plugins.json" "desc@$MP|user|$D|"
check "the word modules inside a description" "$H" "$IN_START" ""

# --- One installed mod, and the inputs around it ------------------------------
mk_home installed
HB="$H"
DB="$H/plugins/cache/$MP/fixture-installed-mod/1.0.0"
mk_mod "$DB" fixture-installed-mod
mk_plain "$H/plugins/cache/$MP/plain/1.0.0" plain
records "$H/plugins/installed_plugins.json" \
  "fixture-installed-mod@$MP|user|$DB|" "plain@$MP|user|$H/plugins/cache/$MP/plain/1.0.0|"
enabled "$H" "\"fixture-installed-mod@$MP\": true, \"plain@$MP\": true"
L_B="$(mline "$ACTIVE" "fixture-installed-mod@$MP" "user scope" "its module mentions tool.check" "$(uninstall "fixture-installed-mod@$MP")" "$DB")"
check "installed mod, user scope" "$HB" "$IN_START" "$L_B"
check "agent_id input" "$HB" "$(hin startup a1)" ""
check "source compact, same output" "$HB" "$(hin compact)" "$L_B"
check "source resume, same output" "$HB" "$(hin resume)" "$L_B"
check "empty input, same output" "$HB" "" "$L_B"

mk_home disabled
D="$H/plugins/cache/$MP/fixture-installed-mod/1.0.0"
mk_mod "$D" fixture-installed-mod
records "$H/plugins/installed_plugins.json" "fixture-installed-mod@$MP|user|$D|"
enabled "$H" "\"fixture-installed-mod@$MP\": false"
check "installed mod set false in enabledPlugins" "$H" "$IN_START" \
  "$(mline "$DISABLED" "fixture-installed-mod@$MP" "user scope" "its module mentions tool.check" "run claude plugin uninstall fixture-installed-mod@$MP" "$D")"

mk_home project
D="$H/plugins/cache/$MP/pmod/1.0.0"
mk_mod "$D" pmod
records "$H/plugins/installed_plugins.json" "pmod@$MP|project|$D|$TMPBASE/someproject"
check "project-scope mod with its project path" "$H" "$IN_START" \
  "$(mline "$ACTIVE" "pmod@$MP" "project scope, $TMPBASE/someproject" "its module mentions tool.check" "$(uninstall "pmod@$MP")" "$D")"

mk_home twomods
D1="$H/plugins/cache/$MP/both/1.0.0"
D2="$H/plugins/cache/$MP/neither/1.0.0"
mk_mod "$D1" both "$MOD_BOTH"
mk_mod "$D2" neither "$MOD_NEITHER"
records "$H/plugins/installed_plugins.json" "both@$MP|user|$D1|" "neither@$MP|user|$D2|"
check "two mods: both events, and neither" "$H" "$IN_START" \
  "$(mline "$ACTIVE" "both@$MP" "user scope" "its module mentions tool.check and tool.call" "$(uninstall "both@$MP")" "$D1")$NL$(mline "$ACTIVE" "neither@$MP" "user scope" "its module mentions neither tool.check nor tool.call" "$(uninstall "neither@$MP")" "$D2")"

mk_home unreadmodule
D="$H/plugins/cache/$MP/nomod/1.0.0"
mk_mod "$D" nomod
rm -f "$D/hooks/register.js"
records "$H/plugins/installed_plugins.json" "nomod@$MP|user|$D|"
check "a module that cannot be read" "$H" "$IN_START" \
  "$(mline "$ACTIVE" "nomod@$MP" "user scope" "its module could not be read" "$(uninstall "nomod@$MP")" "$D")"

# --- Other roots ----------------------------------------------------------------
mk_home skillsdir
HC="$H"
DC="$H/skills/fixture-skillsdir-mod"
mk_mod "$DC" fixture-skillsdir-mod
mkdir -p "$H/skills/onboard" && printf 'x\n' > "$H/skills/onboard/SKILL.md"
check "@skills-dir mod" "$H" "$IN_START" \
  "$(mline "$ACTIVE" "fixture-skillsdir-mod@skills-dir" "from this home's skills folder" "its module mentions tool.check" "remove its folder, $DC" "$DC")"

mk_home skills-dormant
D="$H/skills/fixture-dormant"
mk_mod "$D" fixture-dormant
rm -rf "$D/.claude-plugin"
check "home skills modules folder without plugin.json" "$H" "$IN_START" \
  "$(dorm "A skill folder in this COS home's skills/ carries a hooks module" fixture-dormant "its module mentions tool.check" "$D")"

mk_home synced
D="$H/plugins/synced/u1_u2/sync-mod"
mk_mod "$D" sync-mod
check "@synced mod" "$H" "$IN_START" \
  "$(mline "$ACTIVE" "sync-mod@synced" "synced from the claude.ai account" "its module mentions tool.check" "set sync-mod@synced to false under enabledPlugins in this home's settings.json" "$D")"

mk_home plugindirs
DP1="$TMPBASE/pd/plain-dir"
DP2="$TMPBASE/pd/inline-mod"
mk_plain "$DP1" plain-dir
mk_mod "$DP2" inline-mod
if command -v cygpath >/dev/null 2>&1; then
  W1="$(cygpath -w "$DP1")"; W2="$(cygpath -w "$DP2")"
  PDV="$W1;$W2"
else
  W2="$DP2"
  PDV="$DP1:$DP2"
fi
L_PD="$(mline "$ACTIVE" "inline-mod@inline" "loaded through CLAUDE_CODE_PLUGIN_DIRS" "its module mentions tool.check" "remove its folder from CLAUDE_CODE_PLUGIN_DIRS" "$W2")"
check "CLAUDE_CODE_PLUGIN_DIRS, two entries, one a mod" "$H" "$IN_START" "$L_PD" CLAUDE_CODE_PLUGIN_DIRS="$PDV"

mk_home plugindirs-settings
printf '{\n  "env": {\n    "CLAUDE_CODE_PLUGIN_DIRS": "%s"\n  }\n}\n' "$(jesc "$PDV")" > "$H/settings.json"
check "CLAUDE_CODE_PLUGIN_DIRS under env in settings.json" "$H" "$IN_START" "$L_PD"

if command -v cygpath >/dev/null 2>&1; then
  mk_home winpath
  D="$H/plugins/cache/$MP/winmod/1.0.0"
  mk_mod "$D" winmod
  WD="$(cygpath -w "$D")"
  records "$H/plugins/installed_plugins.json" "winmod@$MP|user|$WD|"
  if grep -q '\\\\' "$H/plugins/installed_plugins.json"; then
    check "Windows installPath with escaped backslashes" "$H" "$IN_START" \
      "$(mline "$ACTIVE" "winmod@$MP" "user scope" "its module mentions tool.check" "$(uninstall "winmod@$MP")" "$WD")"
  else
    bad "Windows installPath with escaped backslashes" "the records carry no escaped backslash; the case tests nothing"
  fi
else
  skip "Windows installPath with escaped backslashes" "cygpath not found, so no Windows path to write"
fi

# --- This session's project: <cwd>/.claude/skills --------------------------------
PWHERE="the project's .claude/skills; it loads only once the project folder is trusted, and whether it loads under --setting-sources user, which this COS's launcher passes, is unconfirmed"
MAYLOAD="A mod may load from this session's project"
PFALSE="A mod in this session's project is set false in this home's settings.json"
M_CHECK="its module mentions tool.check"
# quoted <path>: the path as the hook's validate hint prints it.
quoted() { if [[ "$1" == *" "* ]]; then printf '"%s"' "$1"; else printf '%s' "$1"; fi; }
# pline <id> <dir>: the line for a project mod that may load.
pline() {
  mline "$MAYLOAD" "$1" "$PWHERE" "$M_CHECK" "set $1 to false under enabledPlugins in this home's settings.json, or remove its folder, $2" "$(quoted "$2")"
}
# dline <folder name> <dir>: the line for a project modules folder with no
# plugin.json.
dline() { dorm "A skill folder in this session's project carries a hooks module" "$1" "$M_CHECK" "$2"; }
# mk_project <dir>: a project folder with one plain skill in .claude/skills.
mk_project() {
  mkdir -p "$1/.claude/skills/notes"
  printf -- '---\nname: notes\ndescription: fixture\n---\nx\n' > "$1/.claude/skills/notes/SKILL.md"
}

mk_home project-mod
HP="$H"
PA="$TMPBASE/proj-a"
mk_project "$PA"
DPA="$PA/.claude/skills/fixture-project-mod"
mk_mod "$DPA" fixture-project-mod
check "project mod with plugin.json, may load" "$HP" "$(cin "$PA")" "$(pline fixture-project-mod@skills-dir "$DPA")"

mk_home project-dormant
PB="$TMPBASE/proj-b"
mk_project "$PB"
DPB="$PB/.claude/skills/fixture-dormant"
mk_mod "$DPB" fixture-dormant
rm -rf "$DPB/.claude-plugin"
check "project modules folder without plugin.json" "$H" "$(cin "$PB")" "$(dline fixture-dormant "$DPB")"

mk_home project-false
enabled "$H" "\"fixture-project-mod@skills-dir\": false"
check "project mod set false in enabledPlugins" "$H" "$(cin "$PA")" \
  "$(mline "$PFALSE" fixture-project-mod@skills-dir "the project's .claude/skills" "$M_CHECK" "leave fixture-project-mod@skills-dir set to false under enabledPlugins in this home's settings.json, or remove its folder, $DPA" "$DPA")"

PC="$TMPBASE/proj-c"
mk_project "$PC"
check "project with plain skills only" "$HP" "$(cin "$PC")" ""

PS="$TMPBASE/Some One/proj"
mk_project "$PS"
DPS="$PS/.claude/skills/fixture-project-mod"
mk_mod "$DPS" fixture-project-mod
if command -v cygpath >/dev/null 2>&1; then
  check "cwd with spaces in Windows form" "$HP" "$(cin "$(cygpath -w "$PS")")" \
    "$(pline fixture-project-mod@skills-dir "$(cygpath -m "$DPS")")"
else
  check "cwd with spaces" "$HP" "$(cin "$PS")" "$(pline fixture-project-mod@skills-dir "$DPS")"
fi

# The folder name is written with octal escapes, so this file stays ASCII.
PU="$TMPBASE/J$(printf '\303\274')rgen/proj"
mk_project "$PU"
DPU="$PU/.claude/skills/fixture-project-mod"
mk_mod "$DPU" fixture-project-mod
if command -v cygpath >/dev/null 2>&1; then
  check "cwd with non-ASCII letters, Windows form" "$HP" "$(cin "$(cygpath -w "$PU")")" \
    "$(pline fixture-project-mod@skills-dir "$(cygpath -m "$DPU")")"
else
  check "cwd with non-ASCII letters" "$HP" "$(cin "$PU")" "$(pline fixture-project-mod@skills-dir "$DPU")"
fi

# No cwd in the input: the hook must not fall back to its own working folder.
FIXTURE_PWD="$PWD"
cd "$PA" || exit 1
check "no cwd, the hook run from inside the project" "$HP" "$IN_NOCWD" ""
cd "$FIXTURE_PWD" || exit 1
check "empty cwd" "$HP" "$(cin "")" ""
printf 'x\n' > "$TMPBASE/a-file"
check "cwd naming a file" "$HP" "$(cin "$TMPBASE/a-file")" ""

mk_home cwd-home
D="$H/skills/fixture-skillsdir-mod"
mk_mod "$D" fixture-skillsdir-mod
check "cwd equal to the home, its mod named once" "$H" "$(cin "$H")" \
  "$(mline "$ACTIVE" "fixture-skillsdir-mod@skills-dir" "from this home's skills folder" "$M_CHECK" "remove its folder, $D" "$D")"

# A home named .claude and a session started in its parent: <cwd>/.claude/skills
# is the home's skills/, here under another spelling, so string matching alone
# would name the mod twice.
mk_home dotclaude/.claude
D="$H/skills/fixture-skillsdir-mod"
mk_mod "$D" fixture-skillsdir-mod
if command -v cygpath >/dev/null 2>&1; then CW="$(cygpath -w "$TMPBASE/dotclaude")"; else CW="$TMPBASE/dotclaude/."; fi
check "cwd whose .claude is the home, another spelling, its mod named once" "$H" "$(cin "$CW")" \
  "$(mline "$ACTIVE" "fixture-skillsdir-mod@skills-dir" "from this home's skills folder" "$M_CHECK" "remove its folder, $D" "$D")"

# The second root, CLAUDE_PROJECT_DIR, read after the cwd. Naming another
# project, both are read; the variable comes in Windows form where cygpath is
# present, as on a Windows host. Naming the cwd's project under another
# spelling, it is read once (the -ef test, since the two strings differ).
if command -v cygpath >/dev/null 2>&1; then
  check "CLAUDE_PROJECT_DIR naming another project than the cwd, both read" "$HP" "$(cin "$PA")" \
    "$(pline fixture-project-mod@skills-dir "$DPA")$NL$(dline fixture-dormant "$(cygpath -m "$DPB")")" \
    CLAUDE_PROJECT_DIR="$(cygpath -w "$PB")"
  PAW="$(cygpath -w "$PA")"
else
  check "CLAUDE_PROJECT_DIR naming another project than the cwd, both read" "$HP" "$(cin "$PA")" \
    "$(pline fixture-project-mod@skills-dir "$DPA")$NL$(dline fixture-dormant "$DPB")" CLAUDE_PROJECT_DIR="$PB"
  PAW="$PA/."
fi
check "CLAUDE_PROJECT_DIR naming the cwd's project, another spelling, read once" "$HP" "$(cin "$PA")" \
  "$(pline fixture-project-mod@skills-dir "$DPA")" CLAUDE_PROJECT_DIR="$PAW"

# --- The cannot-tell line -------------------------------------------------------
mk_home truncated
printf '{\n  "version": 2,\n  "plugins": {\n    "a@b": [\n      {\n        "scope": "user",\n        "installPath": "/x' > "$H/plugins/installed_plugins.json"
check "records that do not parse" "$H" "$IN_START" "$(cannot_line "$H/plugins/installed_plugins.json")"

mk_home noplugins
printf '{\n  "version": 2\n}\n' > "$H/plugins/installed_plugins.json"
check "records without a plugins object" "$H" "$IN_START" "$(cannot_line "$H/plugins/installed_plugins.json")"

mk_home unreadable
mkdir -p "$H/plugins/installed_plugins.json"
check "records that cannot be read" "$H" "$IN_START" "$(cannot_line "$H/plugins/installed_plugins.json")"

mk_home nopath
D="$H/plugins/cache/$MP/fixture-installed-mod/1.0.0"
mk_mod "$D" fixture-installed-mod
printf '{\n  "version": 2,\n  "plugins": {\n    "x@y": [\n      {\n        "scope": "user",\n        "path": "/elsewhere"\n      }\n    ],\n    "fixture-installed-mod@%s": [\n      {\n        "scope": "user",\n        "installPath": "%s"\n      }\n    ]\n  }\n}\n' "$MP" "$(jesc "$D")" > "$H/plugins/installed_plugins.json"
check "an entry without an installPath, the mod beside it still named" "$H" "$IN_START" \
  "$(cannot_line "$H/plugins/installed_plugins.json")$NL$(mline "$ACTIVE" "fixture-installed-mod@$MP" "user scope" "its module mentions tool.check" "$(uninstall "fixture-installed-mod@$MP")" "$D")"

mk_home project-unreadable
PL="$TMPBASE/proj-l"
mk_project "$PL"
D="$PL/.claude/skills/fixture-project-mod"
mkdir -p "$D/.claude-plugin" "$D/hooks/hooks.json"
check "a project hooks.json that cannot be read" "$H" "$(cin "$PL")" "$(cannot_line "$D/hooks/hooks.json")"

printf 'SECONDS=10\n' > "$TMPBASE/late.sh"
check "a scan out of time" "$HB" "$IN_START" "$(cannot_line "$HB/plugins/installed_plugins.json")" BASH_ENV="$TMPBASE/late.sh"

printf 'readonly rest\n' > "$TMPBASE/crash-rest.sh"
check "forced failure in the records reader" "$HB" "$IN_START" "$(cannot_line "$HB/plugins/installed_plugins.json")" BASH_ENV="$TMPBASE/crash-rest.sh"
printf 'readonly hj\n' > "$TMPBASE/crash-hj.sh"
check "forced failure reading a hooks.json" "$HB" "$IN_START" "$(cannot_line "$DB/hooks/hooks.json")" BASH_ENV="$TMPBASE/crash-hj.sh"
mk_home crash-out
printf 'readonly out\n' > "$TMPBASE/crash-out.sh"
check "forced failure before a silent verdict" "$H" "$IN_START" "$(cannot_line "$H/plugins")" BASH_ENV="$TMPBASE/crash-out.sh"
mk_home crash-project
printf 'readonly pc\n' > "$TMPBASE/crash-pc.sh"
check "forced failure in the project scan" "$H" "$(cin "$PA")" "$(cannot_line "$H/plugins")" BASH_ENV="$TMPBASE/crash-pc.sh"

# --- Length ---------------------------------------------------------------------
# many <home name> <count>: that many installed mods; sets H and WANT_LINES.
many() {
  local i id dir ents=()
  mk_home "$1"
  WANT_LINES=""
  for i in $(seq -w 1 "$2"); do
    id="mod-$i@$MP"
    dir="$H/plugins/cache/$MP/mod-$i/1.0.0"
    mk_mod "$dir" "mod-$i"
    ents+=("$id|user|$dir|")
    WANT_LINES="${WANT_LINES:+$WANT_LINES$NL}$(mline "$ACTIVE" "$id" "user scope" "its module mentions tool.check" "$(uninstall "$id")" "$dir")"
  done
  records "$H/plugins/installed_plugins.json" "${ents[@]}"
}
# Raw lengths of the two fields in OUT, escapes counted, which are never less
# than the text's own lengths.
smlen() {
  local s="${OUT#\{\"systemMessage\":\"}"
  s="${s%%\",\"hookSpecificOutput\"*}"
  printf '%s' "${#s}"
}
aclen() {
  local s="${OUT#*\"additionalContext\":\"}"
  s="${s%\"\}\}}"
  printf '%s' "${#s}"
}
# many_case <name> <count>: every mod printed in full or counted in the last
# line, the first line exact, both fields at most 10,000.
many_case() {
  local name="$1" count="$2" sm ac shown counted=0 first re
  many "$1" "$2"
  name="$count mods"
  run "$H" "$IN_START"
  if [ "$RC" -ne 0 ] || [ -n "$ERR" ]; then bad "$name" "exit $RC, stderr: ${ERR:-<none>}"; return; fi
  first="$(jtext "${WANT_LINES%%$NL*}")"
  case "$OUT" in
    "{\"systemMessage\":\"$first\\n"*) ;;
    *) bad "$name" "the first line is not the expected one: ${OUT:0:200}"; return ;;
  esac
  shown="$(printf '%s' "$OUT" | grep -o '\[mod-check\] A mod is active' | wc -l)"
  shown=$((shown / 2))
  re='\[mod-check\] ([0-9]+) more lines of this check were left out for length\. Run claude plugin list in this home to see every plugin\.'
  [[ "$OUT" =~ $re ]] && counted="${BASH_REMATCH[1]}"
  if [ $((shown + counted)) -ne "$count" ]; then bad "$name" "$shown printed plus $counted counted is not $count"; return; fi
  sm="$(smlen)"; ac="$(aclen)"
  if [ "$sm" -gt 10000 ] || [ "$ac" -gt 10000 ]; then bad "$name" "systemMessage $sm, additionalContext $ac characters; over the 10,000 cap per field"; return; fi
  json_ok "$name" || return
  good "$name" "$shown printed, $counted counted; systemMessage $sm, additionalContext $ac characters, within the 10,000 cap per field"
}
many_case twenty 20
many_case forty 40

# --- The motivating case, and claude plugin validate ------------------------------
CATALOG=""
for c in "${MODCHECK_CATALOG:-}" \
  "$HOME/.claude/plugins/marketplaces/claude-plugins-official/plugins/code-modernization" \
  "${CLAUDE_CONFIG_DIR:-/nonexistent}/plugins/marketplaces/claude-plugins-official/plugins/code-modernization"; do
  if [ -n "$c" ] && [ -f "$c/hooks/hooks.json" ]; then CATALOG="$c"; break; fi
done
CLAUDE_OK=0
command -v claude >/dev/null 2>&1 && CLAUDE_OK=1
# winform <path>: the spelling a Windows claude reads, where cygpath exists.
winform() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
# validate_hooks <plugin dir>: the hooks line claude plugin validate --json
# reports for its module, under a throwaway config home.
validate_hooks() {
  mkdir -p "$TMPBASE/validate-config"
  CLAUDE_CONFIG_DIR="$(winform "$TMPBASE/validate-config")" claude plugin validate --json "$(winform "$1")" 2>/dev/null |
    grep -o '"[^"]* hooks: [^"]*"' | head -n 1
}

if [ -z "$CATALOG" ]; then
  skip "motivating case, code-modernization" "no catalog copy found (set MODCHECK_CATALOG to its folder)"
else
  mk_home motivating
  D="$H/plugins/cache/claude-plugins-official/code-modernization/1.0.0"
  mkdir -p "$D"
  cp -R "$CATALOG/." "$D/"
  ID="code-modernization@claude-plugins-official"
  records "$H/plugins/installed_plugins.json" "$ID|user|$D|"
  enabled "$H" "\"$ID\": true"
  # The events named in the copy's own module, read here with grep.
  MODFILE="$D/hooks/$(tr -d '\r\n' < "$D/hooks/hooks.json" | sed -n 's/.*"modules"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\.\/\([^"]*\)".*/\1/p')"
  if [ -z "$(sed -n '/"modules"/p' "$D/hooks/hooks.json")" ]; then
    bad "motivating case, code-modernization" "the catalog copy's hooks.json no longer carries modules; re-choose the motivating case"
  else
    hc=0; hk=0
    grep -q 'tool\.check' "$MODFILE" 2>/dev/null && hc=1
    grep -q 'tool\.call' "$MODFILE" 2>/dev/null && hk=1
    case "$hc$hk" in
      11) M="its module mentions tool.check and tool.call" ;;
      10) M="its module mentions tool.check" ;;
      01) M="its module mentions tool.call" ;;
      *) M="its module mentions neither tool.check nor tool.call" ;;
    esac
    check "motivating case, code-modernization ($M)" "$H" "$IN_START" \
      "$(mline "$ACTIVE" "$ID" "user scope" "$M" "$(uninstall "$ID")" "$D")"
    if [ "$CLAUDE_OK" = 1 ]; then
      v="$(validate_hooks "$D")"
      ok=1
      [ "$hk" = 0 ] || [[ "$v" == *tool.call* ]] || ok=0
      [ "$hc" = 0 ] || [[ "$v" == *tool.check* ]] || ok=0
      [ -n "$v" ] || ok=0
      if [ "$ok" = 1 ]; then good "validate agrees, code-modernization" "${v:0:60}... names what the hook named"
      else bad "validate agrees, code-modernization" "claude plugin validate reports ${v:-nothing}"; fi
    else
      skip "validate agrees, code-modernization" "claude not found"
    fi
  fi
fi
if [ "$CLAUDE_OK" = 1 ]; then
  v="$(validate_hooks "$DC")"
  if [[ "$v" == *"hooks: tool.check"* ]]; then good "validate agrees, the fixture's mod" "$v"
  else bad "validate agrees, the fixture's mod" "claude plugin validate reports ${v:-nothing}"; fi
else
  skip "validate agrees, the fixture's mod" "claude not found"
fi

echo ""
[ -n "$PY" ] || echo "(no python3 or python answered, so outputs were compared as text only, not parsed as JSON)"
echo "$PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
