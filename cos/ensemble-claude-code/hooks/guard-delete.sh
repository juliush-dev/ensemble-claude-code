#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - session-level PreToolUse guard on Bash|PowerShell.
# The delete guard. On 2026-10-13 a member's command chained a clone that
# failed, a cd the && chain then skipped, and a ';' into find ... -exec rm -rf,
# which ran in the repository's root and wiped its working tree. This guard asks,
# never denies, on any command whose text deletes or resets a tree, for every
# caller, so such a command reaches the human as a prompt naming it before it
# runs. Since 2.1.211 a PreToolUse ask on Bash floors at a prompt in auto mode
# (HARNESS.md). An ask's reason is shown to the human, not to the agent, so the
# message is written for him; the agent sees only the approval or the denial.
#
# The shapes, matched without regard to case on the command text as it sits in
# the JSON string (a newline is the two characters \n), each verb starting
# where a command word can start:
#   1  rm with r or R in a short option cluster, or --recursive (rm.exe,
#      /bin/rm and sudo rm included)
#   2  find ... -delete
#   3  find ... -exec rm, -execdir rm
#   4  xargs ... rm
#   5  git ... clean, unless its segment carries -n or --dry-run
#   6  git ... reset ... --hard
#   7  git ... checkout of a tree (., .., ./, :/, *, -- dir/) or with -f/--force
#   8  git ... restore of a tree (., .., ./, :/, *, dir/), unless its segment
#      has --staged or -S and neither --worktree nor -W
#   9  Remove-Item, ri, rd, del, erase, rmdir with -r, -re, ..., -Recurse
#  10  rmdir, rd, del, erase with /s (cmd)
#  11  shutil.rmtree, rmtree(, os.removedirs, [IO.Directory]::Delete(
#  12  rimraf, recursive: true (node's rmSync)
#  13  rsync ... --delete
#  14  git ... worktree remove
# The two exemptions (5 and 8) are judged per segment: a segment ends at ; & |
# or a newline, a backslash-newline continuation joining it. Nothing else is
# exempt: a scratchpad target and the guarded form (cd "<abs>" || exit;
# case "$PWD" ...; find "<abs>" ...) ask too, by decision in v1.
#
# It over-asks by design: a delete shape anywhere in the text asks, inside
# quotes, a heredoc that only writes a file, a grep pattern or an echo string
# included, and for the shapes a newline does not end a segment, so "rm x", a
# newline, "ls -r" asks. recursive: true asks in a mkdirSync call too. Single-
# file rm, git checkout -- file, git restore file, git rm --cached, git branch
# -D and git stash drop pass. PowerShell rm with any single-dash word carrying
# an r (-Force, -LiteralPath, -Verbose, -ErrorAction) asks. The ask message
# strips non-ASCII bytes from the quoted command. Still string matching, so it
# misses a delete the shell assembles at run time (${RM} -rf, eval, a variable-
# named command, PowerShell splatting), a quoted subcommand (git "clean"), a
# recursive listing piped to a Remove-Item without -Recurse, a delete inside a
# file the command only runs (bash x.sh, python x.py), and a directory pathspec
# without a trailing slash (git restore src, git checkout -- src). A hook that
# cannot start fails open, and so does one the 10-second timeout kills; the
# exemptions judge at most 40 segments and ask past that. The source tree's
# fixtures/delete-guard/run-fixture.sh holds the cases.

set -u
LC_ALL=C; export LC_ALL   # byte semantics: ASCII classes and case, every host alike

# Fail-closed: every verdict goes through ask or pass, and an exit that reaches
# neither (a crash, a signal) asks from the EXIT trap. Empty input asks too.
ask() {
  DECIDED=1
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$1"}}
JSON
  exit 0
}
pass() { DECIDED=1; exit 0; }
grep_failed() { ask "Delete guard: the pattern check failed (grep exit status $1), so the guard cannot tell whether this command deletes a tree. Check the command before approving."; }
on_exit() {
  [ "${DECIDED:-0}" = 1 ] && exit 0
  ask "Delete guard: the guard stopped before reaching a verdict (exit status $1), and an unfinished check never passes. Check the command before approving."
}
DECIDED=0
trap 'on_exit $?' EXIT
trap 'exit 143' HUP INT TERM

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || ask "Delete guard: no tool input reached the guard, so it cannot tell whether the command deletes a tree. Check the command before approving."

# Key-scoped, non-greedy capture of the command value (the push gate's): a
# description or any other field cannot bleed into it.
cmd="$(printf '%s' "$input" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1)"
[ -n "$cmd" ] || ask "Delete guard: the command could not be read from the tool input, so the guard cannot tell whether it deletes a tree. Check the command before approving."

q="'"
B='(^|[[:space:];&|(){}!`"/'"$q"']|\\[ntr]?)'  # before a verb
A='([[:space:];&|()<>`"'"$q"']|\\|$)'           # after a verb or flag
W='([[:space:]]|\\[ntr])'                        # a gap between words
Q='(\\?["'"$q"'])?'                              # an optional quote
O='([^;&|]*'"$W"')?'                             # more words, same segment
F='(([^;&|]|\\\\;)*'"$W"')?'                     # find's words; \; stays inside
G="$B"'git(\.exe)?'"$Q$W$O"                      # git and its options
T='(\.\.?/?|:/|\*)'                              # a tree pathspec

names=(); pats=()
add() { names+=("$1"); pats+=("$2"); }
add 'rm -r'                  "$B"'rm(\.exe)?'"$Q$W$O"'(-[a-z]*r[a-z]*|--recursive)(:|'"$A"')'
add 'find -delete'           "$B"'find(\.exe)?'"$W$F"'-delete'"$A"
add 'find -exec rm'          "$B"'find(\.exe)?'"$W$F"'-exec(dir)?'"$W"'+'"$Q"'([^;&|[:space:]]*/)?(sudo'"$W"'+)?rm(\.exe)?'"$Q$A"
add 'xargs rm'               "$B"'xargs(\.exe)?'"$W$O$Q"'([^;&|[:space:]]*/)?rm(\.exe)?'"$Q$A"
add 'git clean'              "$G"'clean'"$A"
add 'git reset --hard'       "$G"'reset'"$W$O"'--hard'"$A"
add 'git checkout of a tree' "$G"'checkout'"$W$O"'(-[a-z]*f[a-z]*|--force|'"$Q$T"'|--'"$W"'+'"$O$Q"'[^;&|[:space:]]*/)'"$A"
add 'git restore of a tree'  "$G"'restore'"$W$O$Q"'('"$T"'|[^;&|[:space:]]*/)'"$A"
add 'Remove-Item -Recurse'   "$B"'(remove-item|ri|rd|del|erase|rmdir)(\.exe)?'"$Q$W$O"'-r[a-z]*(:|'"$A"')'
add 'rmdir /s'               "$B"'(rmdir|rd|del|erase)(\.exe)?'"$W$O"'(/[a-z]+)*/s([/:]|'"$A"')'
add 'rmtree'                 'shutil\.rmtree|rmtree[[:space:]]*\(|os\.removedirs|directory\]::delete[[:space:]]*\('
add 'rimraf or recursive: true' 'rimraf|recursive(\\*["'"$q"'])?[[:space:]]*:[[:space:]]*true'
add 'rsync --delete'         "$B"'rsync(\.exe)?'"$W$O"'--del(ete[a-z-]*)?'"$A"
add 'git worktree remove'    "$G"'worktree'"$W"'+remove'"$A"

# One grep over every shape; only grep's own "no match" (exit 1) passes.
args=(); for p in "${pats[@]}"; do args+=(-e "$p"); done
printf '%s' "$cmd" | grep -Eiq "${args[@]}"
rc=$?
[ "$rc" -eq 1 ] && pass
[ "$rc" -eq 0 ] || grep_failed "$rc"

# The two exemptions, per segment. A segment character is anything but ; & |
# and a backslash, or a backslash pair that is not a JSON \n or \r, or a
# backslash-newline continuation. Exempt only when every segment of the shape
# was found and proven exempt; a failed check or a segment not found asks.
N='(\\\\\\[nr]|\\[^nr]|[^;&|\\])'
S2='([[:space:]]|\\t)'
seg() { printf '%s' "$cmd" | grep -oEi -e "$B"'git(\.exe)?'"$Q$S2"'('"$N"'*'"$S2"')?'"$1$N"'*'; }
has() { printf '%s' "$1" | grep -Eq -e "$W""$2"'([[:space:]=;&|()<>`"'"$q"']|\\|$)'; }  # case-sensitive
exempt_clean() {
  local segs s
  segs="$(seg clean)" && [ -n "$segs" ] || return 1
  [ "$(printf '%s\n' "$segs" | wc -l)" -le 40 ] || return 1
  while IFS= read -r s; do
    has "$s" '(-[a-zA-Z]*n[a-zA-Z]*|--dry-run)' || return 1
  done <<EOF
$segs
EOF
  return 0
}
exempt_restore() {
  local segs s trees=0 r
  segs="$(seg restore)" && [ -n "$segs" ] || return 1
  [ "$(printf '%s\n' "$segs" | wc -l)" -le 40 ] || return 1
  while IFS= read -r s; do
    has "$s" "$Q$T"; r=$?
    [ "$r" -eq 1 ] && { has "$s" "$Q"'[^;&|[:space:]]*/'; r=$?; }
    [ "$r" -eq 1 ] && continue
    [ "$r" -eq 0 ] || return 1
    trees=1
    has "$s" '(--staged|-[a-zA-Z]*S[a-zA-Z]*)' || return 1
    has "$s" '(--worktree|-[a-zA-Z]*W[a-zA-Z]*)'; r=$?
    [ "$r" -eq 1 ] || return 1
  done <<EOF
$segs
EOF
  [ "$trees" -eq 1 ]
}

found=""
for i in "${!pats[@]}"; do
  printf '%s' "$cmd" | grep -Eiq -e "${pats[$i]}"
  rc=$?
  [ "$rc" -eq 1 ] && continue
  [ "$rc" -eq 0 ] || grep_failed "$rc"
  case "${names[$i]}" in
    'git clean') exempt_clean && continue ;;
    'git restore of a tree') exempt_restore && continue ;;
  esac
  found="${found:+$found, }${names[$i]}"
done
[ -n "$found" ] || pass

# The command for the message: printable ASCII only (a raw control or a cut
# multibyte character would break the JSON), its first 300 characters, a cut
# escape at the end dropped.
snip="$(printf '%s' "$cmd" | tr -cd ' -~' | head -c 300 | sed -E 's/(^|[^\\])((\\\\)*)\\(u[0-9A-Fa-f]{0,3})?$/\1\2/')"
[ "${#cmd}" -gt 300 ] && snip="$snip ..."
ask "Delete guard: this command deletes or resets a tree (shape: $found): $snip. Check the working directory and the target before approving; a failed cd followed by ';' runs the delete where the shell happens to be."
