#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) — Examiner PreToolUse guard on Bash.
# The Examiner's shell exists to run tests and checks; it never changes
# anything. This guard blocks write-shaped commands. It is a mitigation,
# not a boundary: the binding refusal is the Examiner's tool envelope
# (no edit tools); this narrows the openly named Bash write-escape on a
# sandbox-less host. Footprint-verified at deploy.
#
# The branches below also cover arbitrary-constructed-string execution —
# a write built at runtime and handed to a shell pipe (... | sh), an
# inline command string (sh -c / bash -lc ...), or eval — so a command
# whose write only exists after decoding no longer slips past the string
# match. But this remains string-matching, and therefore CANNOT, by
# construction, cover: direct language interpreters used to write
# (python -c, perl -e, node -e, ruby -e); inline powershell/pwsh -c
# (legitimately used read-only for Get-*, so deliberately not blocked);
# process substitution <(...); or writing a script file then running it.
# Those are the acknowledged residual that only OS-level containment
# closes.

set -u

input="$(cat 2>/dev/null || true)"
# Key-scoped, non-greedy capture of the command value: stop at the value's own
# closing quote, treating a backslash-escaped quote as interior text, so any
# JSON field after "command" in tool_input cannot bleed into the string and
# hide a write-shaped command from the checks below.
cmd="$(printf '%s' "$input" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1)"
[ -n "$cmd" ] || exit 0

# Allow harmless redirects, then treat any remaining redirection as write-shaped.
stripped="$(printf '%s' "$cmd" | sed -E 's|[0-9]*>>?[[:space:]]*/dev/null||g; s|[0-9]*>&[0-9-]+||g')"

block() {
  echo "Examiner guard: this command looks write-shaped ($1). The Examiner verifies and reports; it never changes anything. Report the finding and nominate the Builder or Archivist." >&2
  exit 2
}

printf '%s' "$stripped" | grep -q '>' && block "redirection"

printf '%s' "$stripped" | grep -Eq '(^|[[:space:];&|(])(rm|mv|cp|tee|touch|mkdir|rmdir|truncate|dd|chmod|chown|ln|install)([[:space:]]|$)' \
  && block "file mutation"

printf '%s' "$stripped" | grep -Eq 'sed[[:space:]][^|;&]*-i' \
  && block "in-place edit"

# Tolerate option tokens (and their arguments, e.g. "-C <path>") between git
# and its verb, so "git -C /repo commit|reset|stash|clean" is caught too.
# Errs toward matching more; over-blocking is this guard's safe direction.
printf '%s' "$stripped" | grep -Eq 'git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+(add|commit|push|merge|rebase|reset|restore|clean|stash|tag)([[:space:]]|$)' \
  && block "VCS mutation"

printf '%s' "$stripped" | grep -Eq '(^|[[:space:];&|(])(npm|pnpm|yarn|pip|pipx|cargo|gem)[[:space:]]+(install|uninstall|update|upgrade|publish|add|remove)([[:space:]]|$)' \
  && block "package mutation"

# PowerShell is case-insensitive, so this cmdlet branch matches case-insensitively
# (-i) — "set-content", "REMOVE-ITEM" and the like are the same destructive
# cmdlets as their PascalCase spelling. The bash-native and git branches above
# stay case-sensitive on purpose: their verbs are case-significant in bash and a
# blanket -i would only add over-blocking.
printf '%s' "$stripped" | grep -Eqi '(Set-Content|Out-File|Add-Content|New-Item|Remove-Item|Move-Item|Copy-Item)' \
  && block "PowerShell file mutation"

# These three sinks execute constructed strings the matcher cannot inspect: a
# write built at runtime (decoded, printf-assembled) is invisible to the checks
# above until it reaches the shell that runs it. Block the sinks themselves —
# the pipe into a POSIX shell, the inline "-c" command string, and eval — so the
# danger is caught regardless of how the string was assembled. Decoders that only
# print (base64 -d, printf) stay harmless; only their execution sink is blocked.
printf '%s' "$stripped" | grep -Eq '\|[[:space:]]*(sh|bash|dash|zsh|ksh)([[:space:]]|$)' \
  && block "shell-pipe execution"

printf '%s' "$stripped" | grep -Eq '(^|[[:space:];&|(])(sh|bash|dash|zsh|ksh)[[:space:]]+-[[:alnum:]]*c([[:space:]]|$)' \
  && block "inline shell execution"

printf '%s' "$stripped" | grep -Eq '(^|[[:space:];&|(])eval([[:space:]]|$)' \
  && block "eval execution"

exit 0
