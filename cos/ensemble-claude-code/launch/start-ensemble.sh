#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - session launcher for Linux / macOS.
# ASCII-ONLY FILE with LF line endings, deliberately (a CRLF shebang breaks on
# Linux; keep pure ASCII, LF-only).
#
# Starts a Claude Code session inside the Ensemble's isolated home, from any
# directory. The config home is set for THIS process only: exec replaces the
# shell with claude, carrying CLAUDE_CONFIG_DIR in its environment, so the
# calling shell keeps its own environment untouched and no save/restore dance
# is needed. (The PowerShell launcher uses a try/finally to restore the variable
# because it mutates its own shell in place; exec makes that unnecessary here,
# and claude's exit code passes straight through.) Extra arguments pass through
# to claude, e.g.:
#   ./start-ensemble.sh -p "hello"
#
# Optional one-word entry: add to ~/.bashrc or ~/.zshrc:
#   alias ensemble='"$HOME/.config/ensemble-claude-code/launch/start-ensemble.sh"'
# (adjust the path if you deployed to a custom CLAUDE_ENSEMBLE_HOME or a
# non-default XDG_CONFIG_HOME.)
# (On Windows/PowerShell the maintained one-word pattern is instead the `cos`
# dispatcher, launch/cos.ps1; a bash `cos` sibling is deferred until a second
# lived long-invocation on WSL/remote - see the pursuit's on-trigger residues.)

set -euo pipefail

home="${CLAUDE_ENSEMBLE_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ensemble-claude-code}"

if [ ! -f "$home/CLAUDE.md" ]; then
  echo "Ensemble home not found or incomplete at $home - run deploy-to-host.sh first." >&2
  exit 1
fi

# Fullscreen TUI rendering (a research-preview harness feature; no CLI flag) as an
# ensemble-launch default: CLAUDE_CODE_NO_FLICKER=1 turns on the fullscreen/alt-
# screen rendering, and CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1 fixes a documented
# Windows Terminal stale-fragment bug in that mode (WSL sessions typically render
# inside Windows Terminal, so it applies here too). Both are set-if-unset (:= keeps
# a deliberate override such as =0 to opt out for a session), then exported so the
# exec'd claude child inherits them; this script runs in its own process, so the
# calling shell is untouched with no restore needed.
: "${CLAUDE_CODE_NO_FLICKER:=1}"
: "${CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT:=1}"
export CLAUDE_CODE_NO_FLICKER CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT

# --setting-sources user: only the home's own settings govern the session (no
# project or local settings files) - the whole-shape consistency lever.
CLAUDE_CONFIG_DIR="$home" exec claude --setting-sources user "$@"
