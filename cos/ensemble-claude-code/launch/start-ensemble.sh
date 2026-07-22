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

set -euo pipefail

home="${CLAUDE_ENSEMBLE_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ensemble-claude-code}"

if [ ! -f "$home/CLAUDE.md" ]; then
  echo "Ensemble home not found or incomplete at $home - run deploy-to-host.sh first." >&2
  exit 1
fi

# --setting-sources user: only the home's own settings govern the session (no
# project or local settings files) - the whole-shape consistency lever.
CLAUDE_CONFIG_DIR="$home" exec claude --setting-sources user "$@"
