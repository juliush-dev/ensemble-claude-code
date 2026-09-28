#!/usr/bin/env bash
# Ensemble (ensemble-claude-code) - one-time MCP wiring for the two user-scope
# servers: playwright (the curated browser realization, browser live-control)
# and open-knowledge (OpenKnowledge, a declared host requirement). Linux / macOS.
# ASCII-ONLY FILE with LF line endings, deliberately (a CRLF shebang breaks on
# Linux; keep pure ASCII, LF-only).
#
# WHY A SEPARATE HAND-RUN SCRIPT (not deploy-to-host.sh):
# Both servers register at USER scope, which the harness stores in
# $CLAUDE_CONFIG_DIR/.claude.json - harness runtime state that deploy-to-host.sh
# deliberately never touches (same boundary as login/session state). The staged
# .mcp.json at the config-home root is NOT a harness-read location for user-scope
# MCP wiring; this script writes the two user-scope entries instead. Run it
# ONCE, in your own shell, after deploy, and again after an update that changes
# an entry:
#   ./wire-mcp.sh
#
# It loops over the two entries. Each is idempotent (any existing user-scope
# entry of that name is removed, then the entry is added again) and each verifies
# its own footprint, by name and by its version string, failing loudly if the
# entry did not land where expected. NOTE: the self-verify confirms each entry's
# version string only (@playwright/mcp@0.0.77; @inkeep/open-knowledge@ plus
# OK_ENUMERATED); if you edit this script, extend the verify to also check
# playwright's --isolated and -y and the launcher's branches, or re-verify those
# by eye. jq is used for a structural check when present; without jq the script
# falls back to a grep-based check (no hard jq dependency).
#
# THE OPEN-KNOWLEDGE ENTRY. OpenKnowledge routes each call to a project by the
# call's own cwd, so one user-scope server serves every project. The entry is a
# short launcher run by sh -c: the ok command the OpenKnowledge app or
# npm i -g puts on PATH, when command -v finds it; else npx running
# @inkeep/open-knowledge at OK_ENUMERATED; else exit 127 with one stderr line
# naming the requirement. A host without OpenKnowledge still gets the entry: the
# session starts, the tools are absent, and the members say so (report, never
# fail).
#
# OK_ENUMERATED is the version the COS enumerated OpenKnowledge's tool list at;
# hooks/guard-openknowledge.sh's key table and the member cards derive from that
# list. It is TRACKED, not pinned: a present ok always wins whatever its version,
# and deploy-to-host.sh reports a host version that differs; only the npx
# fallback runs exactly this version. Moving it is the re-enumeration duty:
# re-capture tools/list, diff it against the recorded capture, update the
# guard's key table, its fixtures and the cards where a tool or field moved, then
# move this line and its twin in wire-mcp.ps1 together. deploy-to-host.sh reads
# this line (it looks for OK_ENUMERATED=) and warns when it is missing.

set -euo pipefail

# The version OpenKnowledge's tool list was enumerated at. Keep the spelling
# OK_ENUMERATED='x.y.z' (no spaces): deploy-to-host.sh reads it by that text.
OK_ENUMERATED='0.78.0'

home="${CLAUDE_ENSEMBLE_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ensemble-claude-code}"

if [ ! -f "$home/CLAUDE.md" ]; then
  echo "Ensemble home not found or incomplete at $home - run deploy-to-host.sh first." >&2
  exit 1
fi

config_file="$home/.claude.json"

# playwright: pinned to the audited artifact (@playwright/mcp@0.0.77); -y so npx
# never blocks on an install prompt in a non-interactive stdio child; --isolated
# for an ephemeral, credential-free browser profile. Plain single-quoted JSON -
# Bash passes it literally, so no PS-5.1-style \" escaping is needed.
playwright_json='{"type":"stdio","command":"npx","args":["-y","@playwright/mcp@0.0.77","--isolated"]}'

# open-knowledge: the launcher is one sh -c string. It carries no double quotes,
# so it sits in the JSON string as written.
ok_launcher="if command -v ok >/dev/null 2>&1; then exec ok mcp; elif command -v npx >/dev/null 2>&1; then exec npx -y @inkeep/open-knowledge@${OK_ENUMERATED} mcp; else echo open-knowledge: neither ok nor npx was found - install the OpenKnowledge app, or Node 24 or later for the npx fallback >&2; exit 127; fi"
open_knowledge_json="{\"type\":\"stdio\",\"command\":\"sh\",\"args\":[\"-c\",\"${ok_launcher}\"]}"

# NO provenance or other custom keys inside either entry - .claude.json is
# harness-owned; the rationale for this wiring lives in this script's header,
# never in-entry.

export CLAUDE_CONFIG_DIR="$home"

has_entry() {
  # has_entry <name>: 0 when this home's config carries mcpServers.<name>.
  [ -f "$config_file" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg n "$1" '.mcpServers[$n]' "$config_file" >/dev/null 2>&1
  else
    grep -q "\"$1\"" "$config_file" 2>/dev/null
  fi
}

wire() {
  # wire <name> <json> <version string the args must carry> <label>
  local name="$1" json="$2" want="$3" label="$4" args_text
  echo ""

  # Idempotence: remove any existing user-scope entry of this name first, so
  # the re-add is clean. Scoped to user, so a project-scope .mcp.json of the
  # same name in the current folder is never the one removed.
  if has_entry "$name"; then
    echo "Existing $name entry found; removing it first (idempotent re-wire)."
    claude mcp remove "$name" --scope user >/dev/null 2>&1 || true
  fi

  echo "Registering $name at user scope ($label)..."
  claude mcp add-json "$name" "$json" --scope user

  # --- Verify own footprint ---
  echo "Verifying the $name entry landed in $config_file ..."
  if [ ! -f "$config_file" ]; then
    echo "FOOTPRINT FAIL: $config_file does not exist." >&2
    echo "add-json may have written to the default ~/.claude.json instead of the" >&2
    echo "CLAUDE_CONFIG_DIR home. Check 'claude mcp list' and your ~/.claude.json, then report back." >&2
    exit 1
  fi

  if command -v jq >/dev/null 2>&1; then
    if ! jq -e --arg n "$name" '.mcpServers[$n]' "$config_file" >/dev/null 2>&1; then
      echo "FOOTPRINT FAIL: no mcpServers.$name entry in $config_file." >&2
      echo "The write did not land where expected." >&2
      exit 1
    fi
    args_text="$(jq -r --arg n "$name" '.mcpServers[$n].args | join(" ")' "$config_file")"
    case "$args_text" in
      *"$want"*) : ;;
      *) echo "FOOTPRINT FAIL: $name entry present but its args do not carry $want." >&2
         echo "  args: $args_text" >&2
         exit 1 ;;
    esac
  else
    # No jq: grep-based fallback against the whole config file. Less structural
    # certainty than jq (it matches the string anywhere in the file), but no hard
    # jq dependency; install jq for the exact structural check.
    if ! grep -q "\"$name\"" "$config_file" 2>/dev/null; then
      echo "FOOTPRINT FAIL: no $name entry found in $config_file." >&2
      exit 1
    fi
    if ! grep -qF "$want" "$config_file" 2>/dev/null; then
      echo "FOOTPRINT FAIL: $name entry present but $want is not in $config_file (grep check)." >&2
      exit 1
    fi
    args_text="(jq not installed; grep confirmed $want present in $config_file)"
  fi

  echo "OK: mcpServers.$name present and carrying $want."
  echo "  args: $args_text"
}

wire playwright "$playwright_json" '@playwright/mcp@0.0.77' 'pinned @playwright/mcp@0.0.77, --isolated'
wire open-knowledge "$open_knowledge_json" "@inkeep/open-knowledge@${OK_ENUMERATED}" "ok on PATH, else npx fallback at the enumerated @inkeep/open-knowledge@${OK_ENUMERATED}"

echo ""
echo "claude mcp list (for your eyes - confirm 'playwright' and 'open-knowledge' show connected):"
# For your eyes only: the verify above decided success, so a non-zero exit here
# must not end the script under set -e.
claude mcp list || echo "(claude mcp list exited non-zero; the entries above are verified regardless.)"
echo ""
echo "If playwright shows NOT connected, the npx stdio child may need adjusting for"
echo "your platform (re-check node/npx on PATH and the version pin); record what you changed."
echo "If open-knowledge shows NOT connected, this host may carry neither ok nor npx: the"
echo "members report the gap, and deploy-to-host.sh's inventory names it."
