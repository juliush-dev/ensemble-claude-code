#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - session-level PreToolUse guard on Bash|PowerShell.
# Pushes are a hard human gate. The staged ask rules are prefix patterns and
# were evaded by the ordinary flag-first shape (git -C <path> push - P8 probe
# 10, leg C), so the binding carrier is this guard: it matches push-shaped git
# commands anywhere in the command string, immune to argument order, and
# downgrades them to an explicit ask - never a silent pass, never a hard block
# (the human may approve at the prompt; the prompt IS the gate). The ask rules
# stay staged as defense in depth. Footprint-verified at deploy.

set -u

# Fail-closed, like the sibling guards: every verdict goes through ask or
# pass, and an exit that reaches neither (a crash, a signal) asks from the
# EXIT trap. Empty input asks too; the harness always sends input.
ask() {
  DECIDED=1
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$1"}}
JSON
  exit 0
}
pass() { DECIDED=1; exit 0; }
on_exit() {
  [ "${DECIDED:-0}" = 1 ] && exit 0
  ask "Push gate: the gate stopped before reaching a verdict (exit status $1), and an unfinished check never passes. The prompt is the gate."
}
DECIDED=0
trap 'on_exit $?' EXIT
trap 'exit 143' HUP INT TERM

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || ask "Push gate: no tool input reached the gate. Asking to be safe; the prompt is the gate."

# Key-scoped, non-greedy capture of the command value: stop at the value's own
# closing quote, treating a backslash-escaped quote as interior text, so any
# JSON field after "command" in tool_input (e.g. "description") can no longer
# bleed into the captured string and defeat the terminal push anchor below.
cmd="$(printf '%s' "$input" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1)"

# Input present but the command value could not be isolated: fail toward the
# ask, never a silent pass (the push gate over-asks by design).
[ -n "$cmd" ] || ask "Push gate: the command could not be isolated from the tool input. Asking to be safe; the prompt is the gate."

# git ... push within one pipeline segment, matched on the command text as it
# sits in the JSON string (a newline is the two characters \n) and without
# regard to case (on Windows "GIT push" runs git). "git" or "git.exe" starts
# at the text's start or after anything a command word can follow: whitespace,
# ; & | ( ) { } ! a backtick, a quote, a path's slash, a backslash, or one of
# the escapes \n \t \r. After it, optionally a closing quote, then
# whitespace or \n \t \r. Between it and "push" nothing crosses a segment
# separator (; & |), and "push" follows whitespace, \n \t \r or "=" (an
# inline alias), optionally opened by a quote. After "push" comes the end,
# whitespace, or a shell metacharacter: ; & | ( ) < > a backtick, a quote,
# or a backslash (a JSON newline, a backslash-newline continuation).
# Tightening only: the pattern contains the one it replaced, so whatever
# asked before still asks. It over-asks by design: "git stash push",
# "git log --grep=push", "push" opening a quoted message, and a newline
# read as no separator, so "git status", a newline, "echo push done" asks,
# and so does a trailing "# ... push" comment.
# Still string matching, so this guard misses a push the shell or
# PowerShell assembles at run time: through a variable, a git-config alias,
# quotes, escapes or expansion inside a word (git pu''sh, git p\ush,
# git {push,}, ${GIT:-git} push, git $(echo pu)sh), eval of a split string,
# arguments from xargs, or PowerShell's own quote, escape and space
# characters or array arguments (git @('push')). It also misses a
# separator inside an argument between git and push (git -C 'a;b' push),
# a script file, and git's other push commands (send-pack, http-push).
# Those rest on the ask rules, as far as they reach, and on review, not on
# this guard. The source tree's fixtures/push-gate/run-fixture.sh holds the
# cases both ways.
q="'"
push_shape='(^|[[:space:];&|(){}!`"/'"$q"']|\\[ntr]?)git(\.exe)?(\\?["'"$q"'])?([[:space:]]|\\[ntr])([^;&|]*([[:space:]=]|\\[ntr]))?(\\?["'"$q"'])?push($|[[:space:];&|()<>`"'"$q"']|\\)'
# Only grep's own "no match" (exit 1) passes. A match asks, and so does any
# other status: a grep that errors must not read as no match.
printf '%s' "$cmd" | grep -Eiq "$push_shape"
rc=$?
[ "$rc" -eq 1 ] && pass
[ "$rc" -eq 0 ] && ask "Push gate: this command looks push-shaped. Pushes are a hard human gate; the prompt is the gate, whatever the command's spelling."
ask "Push gate: the pattern check failed (grep exit status $rc). Asking to be safe; the prompt is the gate."
