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

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

# Key-scoped, non-greedy capture of the command value: stop at the value's own
# closing quote, treating a backslash-escaped quote as interior text, so any
# JSON field after "command" in tool_input (e.g. "description") can no longer
# bleed into the captured string and defeat the terminal push anchor below.
cmd="$(printf '%s' "$input" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1)"

ask() {
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$1"}}
JSON
  exit 0
}

# Input present but the command value could not be isolated: fail toward the
# ask, never a silent pass (the push gate over-asks by design).
[ -n "$cmd" ] || ask "Push gate: the command could not be isolated from the tool input. Asking to be safe; the prompt is the gate."

# git ... push within one pipeline segment: "git" (or git.exe) as a word,
# then "push" as a word, with no segment separator (; & |) between them.
if printf '%s' "$cmd" | grep -Eq '(^|[[:space:];&|(])git(\.exe)?[[:space:]]([^;&|]*[[:space:]])?push([[:space:]]|$)'; then
  ask "Push gate: this command looks push-shaped. Pushes are a hard human gate; the prompt is the gate, whatever the command's spelling."
fi

exit 0
