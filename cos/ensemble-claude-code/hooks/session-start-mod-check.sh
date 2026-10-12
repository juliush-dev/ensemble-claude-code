#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - SessionStart mod-presence check.
#
# Says at every session start when a plugin carrying a hooks module, a mod, is
# present in this COS home. A mod runs inside Claude Code and can approve a
# tool call past this home's ask rules, deny rules and guards (HARNESS.md), so
# the session and the human are told, rather than left to a glance at /plugin.
#
# What it reads, in the home (the hook folder's parent) and, last, in the
# session's own project:
#
#   plugins/installed_plugins.json  every installPath of every entry, with the
#                                   plugin's id, scope and projectPath
#   skills/*/                       plugins loaded from the skills folder,
#                                   <name>@skills-dir
#   plugins/synced/*/*/             plugins synced from the claude.ai account,
#                                   <name>@synced
#   CLAUDE_CODE_PLUGIN_DIRS         each folder it names, from the environment
#                                   and from env in settings.json, <name>@inline
#   <root>/.claude/skills/*/        the session's project, under two roots, the
#                                   cwd of the hook input and CLAUDE_PROJECT_DIR
#                                   from the environment: plugins that may load
#                                   as <name>@skills-dir
#   settings.json enabledPlugins    an id set false is reported as disabled,
#                                   never dropped
#
# A folder in skills/ or in the project's .claude/skills whose hooks/hooks.json
# carries "modules" but which has no .claude-plugin/plugin.json is reported
# too, as one that by the docs does not load as a plugin: this COS reads a
# modules key as the mod signal wherever it sits, and the folder is one file
# short of loading. Its line names no plugin id, and says claude plugin
# validate refuses such a folder.
#
# The project's lines say a mod may load, never that it is active. The plugin
# docs load a project skills-dir plugin only from the session's primary
# working directory, only once that folder is trusted, and only when the
# folder holds .claude-plugin/plugin.json; whether one loads in a session
# started with --setting-sources user, as this COS's launcher starts it, is
# unconfirmed. No hook input names the primary working directory, so both
# roots are read. cwd follows Claude: after a cd in the session, a later clear
# or compact carries the folder Claude moved to. CLAUDE_PROJECT_DIR stays at
# the folder the session started in, also after /cd moves the primary. So in
# each of those one root is the primary, and the other may name a folder that
# loads nothing. Both arrive in Windows form on Windows and are turned like the
# home. A missing or empty root, one that is not a folder, a project without
# .claude/skills, a .claude/skills that is the home's own skills/ under another
# spelling (the -ef test; stage 2 read it), and the second root's
# .claude/skills when it is the first's (-ef again) skip silently.
#
# A plugin is a mod when its hooks/hooks.json carries a "modules" key. The
# module file named there is then searched for tool.check and tool.call, the
# two events that can approve or answer a tool call; a mention in a comment
# counts too. The hook reads the records and never calls claude plugin list or
# claude plugin validate: a nested claude costs a second or more at session
# start, and plugin list writes into a home that has no .claude.json yet. The
# line it prints names claude plugin validate for the human to run.
#
# Output is JSON: the same text in systemMessage, which the human sees, and in
# hookSpecificOutput.additionalContext, which the session reads, plus one
# sentence asking the session to tell the human at its first answer. One line
# per mod. Past 8,700 characters the remaining lines are counted in a last line
# instead, so each field stays under 9,000 characters, below the harness's
# 10,000-character cap.
#
# Fail direction: say more. It is silent when the scan finds no mod, a home
# without installed_plugins.json included (a fresh home has no plugins), and in
# the one failure the harness owns, below. Records that exist but cannot be
# read, records without a "plugins" object or with an entry lacking an
# installPath, a hooks.json that exists but cannot be read, a scan still
# running after 3 seconds, and any exit before a verdict (an EXIT trap) print
# the cannot-tell line. A failed assignment does not exit bash: it drops the
# whole top-level command and runs on. So each scan stage is one top-level
# group that sets a stage marker last, and a check after it exits into the
# trap when the marker did not move. Input that carries an agent_id prints
# nothing, as the session cue's does.
#
# The one silent failure is the harness's timeout. The 3-second limit is
# checked between steps, so it cannot cut short a single file test or read that
# blocks, as one on an unreachable network path can, in the home, a recorded
# plugin folder or the session's project. At the 5-second timeout
# in settings.json the harness cancels the hook and discards its output (hooks
# reference, Timeouts), so that start carries no line from this check, not
# even for a mod it had already found.
#
# The records reader copies what remains of the file at every token, so its
# time grows with the square of the file. On the host it was built on it took
# about 1 second at 100 recorded plugins, and past about 200 the scan outruns
# the 3-second limit and prints the cannot-tell line on a file that reads fine.
# The homes it was built against record fewer than 10.
#
# What it cannot see: a mod installed or reloaded after the session started,
# until the next startup, resume, clear, compact or fork (/reload-plugins fires
# no SessionStart); a mod loaded with the --plugin-dir flag, which no hook
# input carries; a folder added with --add-dir, whose .claude/skills it never
# reads (the docs load no skills-dir plugin from one); a mod in another config
# home, whose sessions this hook never runs in. After /cd and then a cd in the
# session, neither root is the folder /cd moved to, which plugins load from, so
# a clear or compact misses it (by the docs; unobserved). Unchecked: whether
# /clear moves the working folder back after a cd, and whether
# CLAUDE_PROJECT_DIR reaches this hook in a session started with
# --setting-sources user; without it only the cwd is read. Whether an enabled
# mod actually loaded is the /plugin tab's to show. A recorded path or a cwd
# written with JSON \u escapes is not decoded and reads as missing.
#
# Wired on matcher startup|resume|clear|compact|fork in settings.json with a
# 5-second timeout, beside the session cue; SessionStart hooks run in
# parallel. Exit 0 on every path, nothing on stderr. Bash builtins only,
# because each process a hook starts costs tens of milliseconds under Git Bash
# on every session start. ASCII only, LF endings.

set -u
exec 2>/dev/null

IFS= read -r -d '' input || true

re='"agent_id"[[:space:]]*:'
[[ "$input" =~ $re ]] && exit 0

LC_ALL=C

# esc and emit use positional parameters only, so the EXIT trap can still
# print when a variable the scan uses has failed.
esc() {
  set -- "${1//\\/\\\\}"
  set -- "${1//\"/\\\"}"
  set -- "${1//$'\n'/\\n}"
  set -- "${1//[$'\001'-$'\037']/}"
  printf '%s' "$1"
}
emit() {
  printf '{"systemMessage":"'
  esc "$1"
  printf '","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"'
  esc "$1"$'\n'"[mod-check] Tell the human this at your first answer, before any gated act."
  printf '"}}\n'
}
on_exit() {
  [ "${verdict:-0}" = 1 ] && exit 0
  verdict=1
  emit "${out:+$out$'\n'}[mod-check] Could not read this COS home's plugin records (${at:-${home:-.}/plugins}), so whether a mod is active is unknown. Run claude plugin list in this home to check."
  exit 0
}
trap on_exit EXIT
trap 'exit 143' HUP INT TERM

# The home is the hook folder's parent. A Windows spelling is turned to
# forward slashes, so globs and parent cuts work the same everywhere.
winpath() { [[ "$1" == [A-Za-z]:[\\/]* || "$1" == \\\\* ]]; }
norm() { np="$1"; winpath "$np" && np="${np//\\//}"; return 0; }
hookdir="${0%/*}"
[ "$hookdir" = "$0" ] && hookdir="${0%\\*}"
[ "$hookdir" = "$0" ] && hookdir="."
home="$hookdir/.."
case "$hookdir" in
  */hooks) home="${hookdir%/hooks}" ;;
  *\\hooks) home="${hookdir%\\hooks}" ;;
esac
[ -n "$home" ] || home="/"
norm "$home"; home="$np"
at="$home/plugins"

out=""
more=0
late=0
seen="|"

add() {
  if [ $(( ${#out} + ${#1} + 1 )) -le 8700 ]; then
    out="${out:+$out$'\n'}$1"
  else
    more=$((more + 1))
  fi
}
cannot() {
  add "[mod-check] Could not read this COS home's plugin records ($1), so whether a mod is active is unknown. Run claude plugin list in this home to check."
}
intime() {
  [ "$late" = 0 ] || return 1
  [ "${SECONDS:-0}" -lt 3 ] && return 0
  late=1
  cannot "$at"
  return 1
}

st=""
[ -f "$home/settings.json" ] && IFS= read -r -d '' st < "$home/settings.json"
ep=""
re='"enabledPlugins"[[:space:]]*:[[:space:]]*\{([^}]*)\}'
[[ "$st" =~ $re ]] && ep="${BASH_REMATCH[1]//[[:space:]]/}"

# check <dir as recorded> <id, or empty> <where>
#       <installed|skills|synced|inline|project>
check() {
  local shown="$1" id="$2" where="$3" kind="$4"
  local dir f hj hint list m mp mod mention remedy open pj vp re
  local has_check=0 has_call=0 unread=0 off=0 haspj=0
  intime || return 0
  norm "$shown"; dir="${np%/}"
  case "$seen" in *"|$dir|"*) return 0 ;; esac
  seen="$seen$dir|"
  f="$dir/hooks/hooks.json"
  at="$f"
  [ -e "$f" ] || return 0
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then cannot "$f"; return 0; fi
  hj=""
  IFS= read -r -d '' hj < "$f"
  re='"modules"[[:space:]]*:'
  [[ "$hj" =~ $re ]] || return 0

  list=""
  re='"modules"[[:space:]]*:[[:space:]]*\[([^]]*)\]'
  [[ "$hj" =~ $re ]] && list="${BASH_REMATCH[1]}"
  [ -n "$list" ] || unread=1
  re='"(([^"\\]|\\.)*)"'
  while [[ "$list" =~ $re ]]; do
    list="${list#*"${BASH_REMATCH[0]}"}"
    m="${BASH_REMATCH[1]//\\\\/\\}"
    norm "$m"
    case "$np" in
      /*) mp="$np" ;;
      [A-Za-z]:/*) mp="$np" ;;
      *) mp="$dir/hooks/${np#./}" ;;
    esac
    if [ -f "$mp" ] && [ -r "$mp" ]; then
      mod=""
      IFS= read -r -d '' mod < "$mp"
      [[ "$mod" == *tool.check* ]] && has_check=1
      [[ "$mod" == *tool.call* ]] && has_call=1
    else
      unread=1
    fi
  done
  if [ "$has_check$has_call" = 11 ]; then mention="its module mentions tool.check and tool.call"
  elif [ "$has_check" = 1 ]; then mention="its module mentions tool.check"
  elif [ "$has_call" = 1 ]; then mention="its module mentions tool.call"
  elif [ "$unread" = 1 ]; then mention="its module could not be read"
  else mention="its module mentions neither tool.check nor tool.call"
  fi

  # A plugin found by folder takes its manifest's name, else the folder's. A
  # skills or project folder without a manifest keeps the bare folder name: by
  # the plugin docs it does not load as a plugin, so it has no plugin id.
  [ -f "$dir/.claude-plugin/plugin.json" ] && haspj=1
  if [ -z "$id" ]; then
    id="${dir##*/}"
    pj=""
    [ "$haspj" = 1 ] && IFS= read -r -d '' pj < "$dir/.claude-plugin/plugin.json"
    re='"name"[[:space:]]*:[[:space:]]*"([^"\\]+)"'
    [[ "$pj" =~ $re ]] && id="${BASH_REMATCH[1]}"
    case "$kind" in
      skills|project) [ "$haspj" = 0 ] || id="$id@skills-dir" ;;
      synced) id="$id@synced" ;;
      inline) id="$id@inline" ;;
    esac
  fi
  [[ "$ep" == *"\"$id\":false"* ]] && off=1

  vp="$shown"
  [[ "$vp" == *" "* ]] && vp="\"$vp\""
  hint="claude plugin validate $vp lists what it hooks."
  open="A mod is active in this COS home"
  [ "$off" = 0 ] || open="A mod is installed in this COS home but disabled"
  case "$kind" in
    installed)
      remedy="run claude plugin uninstall $id"
      [ "$off" = 1 ] || remedy="disable it in /plugin (Installed tab) or $remedy" ;;
    skills)
      remedy="remove its folder, $shown"
      [ "$haspj" = 1 ] || open="A skill folder in this COS home's skills/ carries a hooks module" ;;
    synced)
      remedy="set $id to false under enabledPlugins in this home's settings.json"
      [ "$off" = 0 ] || remedy="leave $id set to false under enabledPlugins in this home's settings.json" ;;
    project)
      remedy="remove its folder, $shown"
      if [ "$haspj" = 0 ]; then
        open="A skill folder in this session's project carries a hooks module"
      elif [ "$off" = 1 ]; then
        open="A mod in this session's project is set false in this home's settings.json"
        where="the project's .claude/skills"
        remedy="leave $id set to false under enabledPlugins in this home's settings.json, or $remedy"
      else
        open="A mod may load from this session's project"
        remedy="set $id to false under enabledPlugins in this home's settings.json, or $remedy"
      fi ;;
    *) remedy="remove its folder from CLAUDE_CODE_PLUGIN_DIRS" ;;
  esac
  # A skills or project folder without a manifest does not load as a plugin,
  # and claude plugin validate refuses it, so the line says both.
  case "$kind$haspj" in
    skills0|project0)
      where="it has no .claude-plugin/plugin.json, so by the plugin docs it does not load as a plugin"
      hint="claude plugin validate refuses a folder without that manifest; the module its hooks/hooks.json names shows what it hooks." ;;
  esac
  add "[mod-check] $open: $id ($where; $mention). A mod can approve a tool call past this home's ask rules, deny rules and guards. Not installed on purpose: $remedy. Installed on purpose: its word belongs in the project record. $hint"
}

# --- 1. Installed plugins: plugins/installed_plugins.json ----------------------
# A small JSON reader: one token at a time, with the grammar checked, so a
# truncated or reshaped file reads as cannot-tell rather than as no plugins.
# The entries it keeps are the objects in each plugins.<id> array.
scan_records() {
  e_id=(); e_path=(); e_scope=(); e_proj=()
  rf="$home/plugins/installed_plugins.json"
  [ -e "$rf" ] || [ -L "$rf" ] || return 0
  at="$rf"
  rec=""
  [ -f "$rf" ] && [ -r "$rf" ] && IFS= read -r -d '' rec < "$rf"
  rest="$rec"
  bad=0; d=0; xp=v; top=0; plug=0; ent=0
  obj=(); pk=(); kk=()
  ip=""; sc=""; pp=""
  re='^[[:space:]]*("([^"\\]|\\.)*"|[][{}:,]|[^][{}:,"[:space:]]+)'
  while [[ "$rest" =~ $re ]]; do
    intime || break
    t="${BASH_REMATCH[1]}"
    rest="${rest:${#BASH_REMATCH[0]}}"
    # inplug: the container at depth 2 is the top object's "plugins" object.
    inplug=0
    [ "$d" -ge 2 ] && [ "${pk[2]}" = '"plugins"' ] && [ "${obj[2]}" = 1 ] && inplug=1
    case "$t" in
      '{'|'[')
        case "$xp" in v|vc) ;; *) bad=1; break ;; esac
        [ "$d" = 0 ] && [ "$top" = 1 ] && { bad=1; break; }
        top=1
        pk[d+1]=""
        [ "$d" -gt 0 ] && [ "${obj[d]}" = 1 ] && pk[d+1]="${kk[d]}"
        d=$((d + 1))
        if [ "$t" = '{' ]; then obj[d]=1; xp=kc; else obj[d]=0; xp=vc; fi
        if [ "$d" = 2 ] && [ "${pk[2]}" = '"plugins"' ] && [ "$t" = '{' ]; then plug=1; fi
        if [ "$inplug" = 1 ]; then
          [ "$d" = 3 ] && [ "$t" != '[' ] && bad=1
          [ "$d" = 4 ] && [ "$t" != '{' ] && bad=1
          if [ "$d" = 4 ] && [ "$t" = '{' ]; then ent=1; ip=""; sc=""; pp=""; fi
        fi ;;
      '}'|']')
        [ "$d" -gt 0 ] || { bad=1; break; }
        if [ "$t" = '}' ]; then
          [ "${obj[d]}" = 1 ] || { bad=1; break; }
          case "$xp" in kc|s) ;; *) bad=1; break ;; esac
        else
          [ "${obj[d]}" = 0 ] || { bad=1; break; }
          case "$xp" in vc|s) ;; *) bad=1; break ;; esac
        fi
        if [ "$d" = 4 ] && [ "$ent" = 1 ]; then
          ent=0
          if [ -z "$ip" ]; then
            bad=1
          else
            m="${pk[3]:1:${#pk[3]}-2}"
            e_id+=("${m//\\\\/\\}"); e_path+=("$ip"); e_scope+=("$sc"); e_proj+=("$pp")
          fi
        fi
        d=$((d - 1))
        xp=s ;;
      ':')
        [ "$xp" = c ] || { bad=1; break; }
        xp=v ;;
      ',')
        [ "$xp" = s ] && [ "$d" -gt 0 ] || { bad=1; break; }
        if [ "${obj[d]}" = 1 ]; then xp=k; else xp=v; fi ;;
      *)
        case "$xp" in
          k|kc)
            [ "${t:0:1}" = '"' ] || { bad=1; break; }
            kk[d]="$t"
            xp=c ;;
          v|vc)
            top=1
            if [ "$inplug" = 1 ]; then
              [ "$d" -le 3 ] && bad=1
              if [ "$d" = 4 ] && [ "$ent" = 1 ] && [ "${t:0:1}" = '"' ]; then
                m="${t:1:${#t}-2}"
                m="${m//\\\\/\\}"
                case "${kk[4]}" in
                  '"installPath"') ip="$m" ;;
                  '"scope"') sc="$m" ;;
                  '"projectPath"') pp="$m" ;;
                esac
              fi
            fi
            xp=s ;;
          *) bad=1; break ;;
        esac ;;
    esac
  done
  if ! { [ "$d" = 0 ] && [ "$xp" = s ] && [[ "$rest" =~ ^[[:space:]]*$ ]]; }; then bad=1; fi
  [ "$plug" = 1 ] || bad=1
  if [ "$bad" = 1 ] && [ "$late" = 0 ]; then cannot "$rf"; fi
  for i in "${!e_path[@]}"; do
    w="${e_scope[i]:-unknown} scope"
    [ -z "${e_proj[i]}" ] || w="$w, ${e_proj[i]}"
    check "${e_path[i]}" "${e_id[i]}" "$w" installed
  done
  return 0
}

# --- 2. The skills folder, 3. synced plugins -----------------------------------
scan_folders() {
  for f in "$home"/skills/*/hooks/hooks.json; do
    [ -e "$f" ] || continue
    check "${f%/hooks/hooks.json}" "" "from this home's skills folder" skills
  done
  for f in "$home"/plugins/synced/*/*/hooks/hooks.json; do
    [ -e "$f" ] || continue
    check "${f%/hooks/hooks.json}" "" "synced from the claude.ai account" synced
  done
  return 0
}

# --- 4. CLAUDE_CODE_PLUGIN_DIRS ----------------------------------------------
# Separated by ; on Windows and : elsewhere: a value holding ; or starting with
# a drive letter splits on ;, any other on :.
plugdirs() {
  local v="$1" sep=":" e
  case "$v" in *";"*) sep=";" ;; esac
  winpath "$v" && sep=";"
  while [ -n "$v" ]; do
    e="${v%%"$sep"*}"
    if [ "$e" = "$v" ]; then v=""; else v="${v#*"$sep"}"; fi
    [ -z "$e" ] || check "$e" "" "loaded through CLAUDE_CODE_PLUGIN_DIRS" inline
  done
}
scan_plugdirs() {
  plugdirs "${CLAUDE_CODE_PLUGIN_DIRS:-}"
  re='"CLAUDE_CODE_PLUGIN_DIRS"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
  if [[ "$st" =~ $re ]]; then
    m="${BASH_REMATCH[1]}"
    plugdirs "${m//\\\\/\\}"
  fi
  return 0
}

# --- 5. This session's project: <root>/.claude/skills/*/ -----------------------
# Two roots in turn: the cwd of the hook input, unescaped, then
# CLAUDE_PROJECT_DIR from the environment, each turned like the home. A root
# that is missing, empty or not a folder, or has no .claude/skills: nothing to
# read. The home's own skills/ under another spelling is skipped by -ef, the
# same file on disk, since stage 2 read it; so is the second root's
# .claude/skills when it is the first's.
scan_project() {
  intime || return 0
  pc=""
  re='"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
  [[ "$input" =~ $re ]] && pc="${BASH_REMATCH[1]//\\\\/\\}"
  pd1=""
  scan_root "$pc"
  scan_root "${CLAUDE_PROJECT_DIR:-}"
  return 0
}
scan_root() {
  intime || return 0
  norm "$1"
  pc="$np"
  [ -n "$pc" ] || return 0
  while [[ "$pc" == */ ]]; do pc="${pc%/}"; done
  [ -d "$pc/" ] || return 0
  pd="$pc/.claude/skills"
  [ -d "$pd" ] || return 0
  [ "$pd" -ef "$home/skills" ] && return 0
  [ -n "$pd1" ] && [ "$pd" -ef "$pd1" ] && return 0
  pd1="$pd"
  at="$pd"
  for f in "$pd"/*/hooks/hooks.json; do
    [ -e "$f" ] || continue
    check "${f%/hooks/hooks.json}" "" "the project's .claude/skills; it loads only once the project folder is trusted, and whether it loads under --setting-sources user, which this COS's launcher passes, is unconfirmed" project
  done
  return 0
}

# --- The scan, one guarded stage at a time -----------------------------------
# A stage bash drops partway leaves the marker behind, and the check after it
# exits into the trap; an unset marker exits there too.
stage=0
{ scan_records; stage=1; }
[ "$stage" = 1 ] || exit 1
{ scan_folders; stage=2; }
[ "$stage" = 2 ] || exit 1
{ scan_plugdirs; stage=3; }
[ "$stage" = 3 ] || exit 1
{ scan_project; stage=4; }
[ "$stage" = 4 ] || exit 1

# --- The verdict ---------------------------------------------------------------
if [ "$more" -gt 0 ]; then
  out="$out"$'\n'"[mod-check] $more more lines of this check were left out for length. Run claude plugin list in this home to see every plugin."
fi
# Read before the verdict, so a variable that failed exits here, into the trap.
: "$out"
verdict=1
if [ "${verdict:-0}" = 1 ] && [ -n "$out" ]; then emit "$out"; fi
exit 0
