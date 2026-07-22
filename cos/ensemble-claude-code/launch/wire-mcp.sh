#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - one-time MCP wiring for the playwright OSCC
# realization (browser live-control). Linux / macOS.
# ASCII-ONLY FILE with LF line endings, deliberately (a CRLF shebang breaks on
# Linux; keep pure ASCII, LF-only).
#
# WHY A SEPARATE HAND-RUN SCRIPT (not deploy-to-host.sh):
# The playwright server registers at USER scope, which the harness stores in
# $CLAUDE_CONFIG_DIR/.claude.json - harness runtime state that deploy-to-host.sh
# deliberately never touches (same boundary as login/session state). The staged
# .mcp.json at the config-home root is NOT a harness-read location for user-scope
# MCP wiring; this script writes the one user-scope entry instead. Run it ONCE,
# in your own shell, after deploy:
#   ./wire-mcp.sh
#
# It is idempotent (re-running removes and re-adds the same pinned entry) and it
# verifies its own footprint, failing loudly if the entry did not land where
# expected. NOTE: the self-verify confirms the version pin (@playwright/mcp@0.0.77)
# only; if you edit this script, extend the verify to also check --isolated and
# -y, or re-verify those by eye. jq is used for a structural check when present;
# without jq the script falls back to a grep-based check (no hard jq dependency).

set -euo pipefail

home="${CLAUDE_ENSEMBLE_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ensemble-claude-code}"

if [ ! -f "$home/CLAUDE.md" ]; then
  echo "Ensemble home not found or incomplete at $home - run deploy-to-host.sh first." >&2
  exit 1
fi

config_file="$home/.claude.json"

# Pinned to the audited artifact (@playwright/mcp@0.0.77); -y so npx never blocks
# on an install prompt in a non-interactive stdio child; --isolated for an
# ephemeral, credential-free browser profile. Plain single-quoted JSON - Bash
# passes it literally, so no PS-5.1-style \" escaping is needed. NO provenance or
# other custom keys inside this entry - .claude.json is harness-owned; the door
# is carried by the curation record and this script's header, never in-entry.
server_json='{"type":"stdio","command":"npx","args":["-y","@playwright/mcp@0.0.77","--isolated"]}'

export CLAUDE_CONFIG_DIR="$home"

# Idempotence: if a playwright entry already exists in this home's config,
# remove it first so the re-add is clean.
already=0
if [ -f "$config_file" ]; then
  if command -v jq >/dev/null 2>&1; then
    if jq -e '.mcpServers.playwright' "$config_file" >/dev/null 2>&1; then already=1; fi
  else
    if grep -q '"playwright"' "$config_file" 2>/dev/null; then already=1; fi
  fi
fi
if [ "$already" -eq 1 ]; then
  echo "Existing playwright entry found; removing it first (idempotent re-wire)."
  claude mcp remove playwright 2>/dev/null || true
fi

echo "Registering playwright at user scope (pinned @playwright/mcp@0.0.77, --isolated)..."
claude mcp add-json playwright "$server_json" --scope user

# --- Verify own footprint ---
echo ""
echo "Verifying the entry landed in $config_file ..."
if [ ! -f "$config_file" ]; then
  echo "FOOTPRINT FAIL: $config_file does not exist." >&2
  echo "add-json may have written to the default ~/.claude.json instead of the" >&2
  echo "CLAUDE_CONFIG_DIR home. Check 'claude mcp list' and your ~/.claude.json, then report back." >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  if ! jq -e '.mcpServers.playwright' "$config_file" >/dev/null 2>&1; then
    echo "FOOTPRINT FAIL: no mcpServers.playwright entry in $config_file." >&2
    echo "The write did not land where expected." >&2
    exit 1
  fi
  args_text="$(jq -r '.mcpServers.playwright.args | join(" ")' "$config_file")"
  case "$args_text" in
    *@playwright/mcp@0.0.77*) : ;;
    *) echo "FOOTPRINT FAIL: playwright entry present but not pinned to @playwright/mcp@0.0.77." >&2
       echo "  args: $args_text" >&2
       exit 1 ;;
  esac
else
  # No jq: grep-based fallback against the whole config file. Less structural
  # certainty than jq (it matches the pin anywhere in the file), but no hard
  # jq dependency; install jq for the exact structural check.
  if ! grep -q '"playwright"' "$config_file" 2>/dev/null; then
    echo "FOOTPRINT FAIL: no playwright entry found in $config_file." >&2
    exit 1
  fi
  if ! grep -q '@playwright/mcp@0\.0\.77' "$config_file" 2>/dev/null; then
    echo "FOOTPRINT FAIL: playwright entry present but not pinned to @playwright/mcp@0.0.77 (grep check)." >&2
    exit 1
  fi
  args_text="(jq not installed; grep confirmed @playwright/mcp@0.0.77 present in $config_file)"
fi

echo "OK: mcpServers.playwright present and pinned."
echo "  args: $args_text"
echo ""
echo "claude mcp list (for your eyes - confirm 'playwright' shows connected):"
claude mcp list
echo ""
echo "If playwright shows NOT connected, the npx stdio child may need adjusting for"
echo "your platform (re-check node/npx on PATH and the version pin); record what you changed."
