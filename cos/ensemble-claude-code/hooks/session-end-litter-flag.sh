#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) — SessionEnd litter-flag hook.
# Structural remedy for the pass-litter scar: at session end, flag open pass
# state where the next session's binding pickup read already looks.
# Zero per-turn cost: fires only at SessionEnd. Footprint-verified at deploy,
# never trusted from this file's existence.

set -u

input="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
# JSON escapes backslashes; collapse them so Windows paths resolve.
cwd="$(printf '%s' "$cwd" | sed 's/\\\\/\\/g')"

# Session-scoped grant cleanup: the grant file the path guard may have
# consulted for this session (hooks/guard-archivist-paths.sh's
# session-roots/<session_id>.txt) is scoped to the session's own lifetime, so
# it is removed here unconditionally of cwd being usable - unlike the litter
# flags below, a stray or missing cwd must never leave a grant behind. Parsed
# and validated from the same stdin JSON, same charset as the guard's own
# check (non-empty, [0-9A-Za-z-]+ only).
session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
case "$session_id" in
  ''|*[!0-9A-Za-z-]*) session_id="" ;;
esac
[ -n "$session_id" ] && rm -f "$(dirname "$0")/session-roots/$session_id.txt"

[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
cd "$cwd" || exit 0

stamp="$(date +%Y-%m-%d)"
marker="<!-- ensemble-litter-flag -->"

# --- Litter kind 1: iteration records left open.
# A record under routes/<route>/iterations/ still carrying `status: open`
# means a pass ended without its stop duties (pass-discipline runbook).
# The flag lands beside the route's Handoff.md, where the binding pickup
# read already looks.

open_routes="$(find . -name .git -prune -o -type f \
  -path '*/routes/*/iterations/iteration-*.md' \
  -not -path '*-evidence/*' -print 2>/dev/null \
  | while IFS= read -r rec; do
      if grep -q '^status: open' "$rec" 2>/dev/null; then
        dirname "$(dirname "$rec")"
      fi
    done | sort -u)"

# Clear flags this hook wrote whose condition no longer holds.
find . -name .git -prune -o -type f -name 'LITTER-FLAG.md' -print 2>/dev/null \
  | while IFS= read -r f; do
      grep -q "$marker" "$f" 2>/dev/null || continue
      d="$(dirname "$f")"
      # Root-level dirty-tree flags are handled below; skip them here.
      [ "$d" = "." ] && continue
      if ! printf '%s\n' "$open_routes" | grep -Fxq "$d"; then
        rm -f "$f"
      fi
    done

# Write or refresh flags where open records exist now.
printf '%s\n' "$open_routes" | while IFS= read -r d; do
  [ -n "$d" ] || continue
  recs="$(grep -l '^status: open' "$d"/iterations/iteration-*.md 2>/dev/null | sed 's|^\./||')"
  {
    echo "$marker"
    echo "# LITTER FLAG — open pass state at session end ($stamp)"
    echo
    echo "A session ended while this route held iteration records still marked \`status: open\`:"
    echo
    printf '%s\n' "$recs" | sed 's/^/- `/; s/$/`/'
    echo
    echo "The pass may have ended without its stop duties. Before new work on this route, run the pass-discipline runbook's stop moment for the litter (complete the record, update and prune the handoff, freeze), then delete this flag."
  } > "$d/LITTER-FLAG.md"
done

# --- Litter kind 2: dirty working tree at session end.
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$root" ]; then
    if [ -n "$(git -C "$root" status --porcelain 2>/dev/null)" ]; then
      {
        echo "$marker"
        echo "# LITTER FLAG — dirty working tree at session end ($stamp)"
        echo
        echo "A session ended with uncommitted changes in this tree. Commit discipline is a notebook obligation: review the state, form coherent commits (or deliberately discard), then delete this flag."
      } > "$root/LITTER-FLAG.md"
    elif [ -f "$root/LITTER-FLAG.md" ] && grep -q "$marker" "$root/LITTER-FLAG.md" 2>/dev/null; then
      rm -f "$root/LITTER-FLAG.md"
    fi
  fi
fi

exit 0
