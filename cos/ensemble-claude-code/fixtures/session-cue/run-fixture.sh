#!/usr/bin/env bash
# run-fixture.sh: the fixture for hooks/session-start-cue.sh, the session cue
# and its fallback print of the main-session rules (always-on/CONCERTMASTER.md).
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it by hand, from anywhere:   bash run-fixture.sh
# Exit 0 PASS, exit 1 FAIL. It stages a throwaway home (hooks/ plus
# CONCERTMASTER.md, the deployed layout) in a temp directory it removes on the
# way out, and never touches a deployed home. On Windows run it from Git Bash:
# a bare 'bash' typed in PowerShell may start WSL's bash.
#
# THE SIZE CHECK. Claude Code caps a hook's plain stdout at 10,000 characters,
# measured whole; above it the model gets a 2,000-character preview and a file
# path instead (hooks reference, 2.1.283). The longest thing this hook prints
# is the fallback on a startup with no project face: the "No face here" line,
# the decision-proposal line, the fallback header and the whole file. This
# fixture prints exactly that and fails above LIMIT, 9,000 characters. The
# 1,000-character margin covers what is documented but not observed here (how
# the harness counts a trailing newline or any framing) and an edit or two to
# the file made between runs of this fixture, which nothing runs
# automatically. The file must stay ASCII: then characters equal bytes, the
# count needs no locale, and the Git Bash print cannot mis-decode it.
#
# THE CASES. With and without ENSEMBLE_CONCERTMASTER_APPENDED (the launcher's
# marker): startup, resume and compact, in a project face and outside one; an
# agent_id input; empty input. Every case must exit 0 with nothing on stderr.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$HERE/../../hooks/session-start-cue.sh"
RULES_SRC="$HERE/../../always-on/CONCERTMASTER.md"
LIMIT=9000
[ -f "$HOOK_SRC" ] || { echo "FAIL (setup): hook not found at $HOOK_SRC"; exit 1; }
[ -f "$RULES_SRC" ] || { echo "FAIL (setup): rules file not found at $RULES_SRC"; exit 1; }

PASSED=0
FAILED=0

TMPBASE="$(mktemp -d 2>/dev/null)" || { echo "FAIL (setup): mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMPBASE"' EXIT
HOME_DIR="$TMPBASE/home"
FACE="$TMPBASE/project"
mkdir -p "$HOME_DIR/hooks" "$FACE" || { echo "FAIL (setup): mkdir"; exit 1; }
cp "$HOOK_SRC" "$HOME_DIR/hooks/session-start-cue.sh" || { echo "FAIL (setup): copy hook"; exit 1; }
cp "$RULES_SRC" "$HOME_DIR/CONCERTMASTER.md" || { echo "FAIL (setup): copy rules"; exit 1; }
: > "$FACE/Constitution.md"
HOOK="$HOME_DIR/hooks/session-start-cue.sh"
NOFACE="/ensemble-fixture-no-such-dir/work"

L_FACE='[session-cue] Wrapped project: load onboard before working.'
L_NONE='[session-cue] No face here: ask the human before working (wrap offer).'
L_DPD='[session-cue] Load decision-proposal-discipline before the first ask.'
L_HEAD='[session-cue] This session was not launched with the main-session rules appended; they follow in full.'
BODY="$(tr -d '\r' < "$RULES_SRC")"

bad() { echo "FAIL ($1): $2"; FAILED=$((FAILED + 1)); }
good() { echo "PASS ($1): $2"; PASSED=$((PASSED + 1)); }

# hin <source> <cwd> [agent_id]
hin() {
  local agent=""
  [ -z "${3:-}" ] || agent="\"agent_id\":\"$3\","
  printf '{"session_id":"s1",%s"cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$agent" "$2" "$1"
}

# check <name> <marker 0|1> <raw input> <expected output>
check() {
  local name="$1" marker="$2" json="$3" want="$4" out rc err
  if [ "$marker" = 1 ]; then
    out="$(printf '%s' "$json" | env ENSEMBLE_CONCERTMASTER_APPENDED=1 "$BASH" "$HOOK" 2>"$TMPBASE/err")"
  else
    out="$(printf '%s' "$json" | env -u ENSEMBLE_CONCERTMASTER_APPENDED "$BASH" "$HOOK" 2>"$TMPBASE/err")"
  fi
  rc=$?
  err="$(cat "$TMPBASE/err")"
  if [ "$rc" -ne 0 ] || [ -n "$err" ]; then bad "$name" "exit $rc, stderr: ${err:-<none>}"; return; fi
  if [ "$out" != "$want" ]; then bad "$name" "unexpected output, first line: ${out%%$'\n'*}"; return; fi
  good "$name" "expected output, exit 0, no stderr"
}

NL=$'\n'
FALLBACK="$L_HEAD$NL$BODY"

# --- The size check ---------------------------------------------------------
if LC_ALL=C grep -q '[^ -~[:space:]]' "$RULES_SRC"; then
  bad size "always-on/CONCERTMASTER.md carries a non-ASCII byte; keep it ASCII"
else
  out="$(hin startup "$NOFACE" | env -u ENSEMBLE_CONCERTMASTER_APPENDED "$BASH" "$HOOK" 2>/dev/null; printf x)"
  out="${out%x}"
  LC_ALL=C
  chars=${#out}
  unset LC_ALL
  if [ "$chars" -gt "$LIMIT" ]; then
    bad size "longest print is $chars characters, over the $LIMIT limit (the hook cap is 10,000)"
  elif [ "$out" != "$L_NONE$NL$L_DPD$NL$FALLBACK$NL" ]; then
    bad size "the longest print is not the expected no-face startup fallback"
  else
    good size "longest print $chars characters, $((LIMIT - chars)) under the $LIMIT limit, $((10000 - chars)) under the cap"
  fi
fi

# --- The cases --------------------------------------------------------------
check startup-face-nomarker      0 "$(hin startup "$FACE")"   "$L_FACE$NL$L_DPD$NL$FALLBACK"
check startup-face-marker        1 "$(hin startup "$FACE")"   "$L_FACE$NL$L_DPD"
check startup-noface-marker      1 "$(hin startup "$NOFACE")" "$L_NONE$NL$L_DPD"
check resume-face-nomarker       0 "$(hin resume "$FACE")"    "$L_FACE$NL$L_DPD$NL$FALLBACK"
check resume-face-marker         1 "$(hin resume "$FACE")"    "$L_FACE$NL$L_DPD"
check compact-nomarker           0 "$(hin compact "$FACE")"   "$FALLBACK"
check compact-marker             1 "$(hin compact "$FACE")"   ""
check agent-nomarker             0 "$(hin startup "$FACE" a1)" ""
check agent-compact-nomarker     0 "$(hin compact "$FACE" a1)" ""
check empty-input-nomarker       0 ""                         "$FALLBACK"
check empty-input-marker         1 ""                         ""

echo ""
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
