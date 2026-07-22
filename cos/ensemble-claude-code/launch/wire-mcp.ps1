# provenance: curation record curation/claude-code/records/playwright.md (tending third-party-curation, beat 2026-07-09-1)
# Ensemble (ensemble-claude-code) - one-time MCP wiring for the playwright OSCC realization.
# Windows PowerShell 5.1 compatible. ASCII-ONLY FILE, deliberately (PS 5.1 reads
# BOM-less files as ANSI; keep pure ASCII).
#
# WHY A SEPARATE HAND-RUN SCRIPT (not deploy-to-host.ps1):
# The playwright server registers at USER scope, which the harness stores in
# $CLAUDE_CONFIG_DIR\.claude.json - harness runtime state that deploy-to-host.ps1
# deliberately never touches (same boundary as login/session state). The staged
# .mcp.json at the config-home root is NOT a harness-read location for user scope
# (project scope reads .mcp.json from the WORKING directory only); that was the
# first footprint failure (2026-07-09). This script writes the one user-scope
# entry instead. Run it ONCE, in YOUR OWN PowerShell, after deploy:
#   powershell -ExecutionPolicy Bypass -File .\wire-mcp.ps1
#
# It is idempotent (re-running removes and re-adds the same pinned entry) and it
# verifies its own footprint, failing loudly if the entry did not land where
# expected. NOTE: the self-verify confirms the version pin (@playwright/mcp@0.0.77)
# only; if you ever edit this script, extend the verify to also check --isolated
# and -y, or re-verify those by eye.
#
# WINDOWS FOOTGUNS this script guards against (each undocumented; each caught by
# the verify step - if one bites, adjust here and record it in the curation
# record's patch ledger, do not silently wonder):
#   1. Whether CLAUDE_CONFIG_DIR redirects add-json WRITES (docs only promise it
#      redirects reads). If the entry lands in the default ~\.claude.json instead,
#      the verify below says so explicitly.
#   2. JSON quoting: PS 5.1 passes native-command args through CommandLineToArgvW,
#      so the inline JSON's double quotes are pre-escaped as \" below. If add-json
#      reports a JSON parse error, the escaping needs adjusting for your PS build.
#   3. npx stdio servers on native Windows sometimes need a "cmd /c" wrapper
#      (command "cmd", args "/c","npx",...) instead of bare "npx". The doc examples
#      use bare "npx -y"; this script does too. If "claude mcp list" shows
#      playwright NOT connected, switch to the cmd /c form and record it.

$ErrorActionPreference = 'Stop'

$ensembleHome = Join-Path $env:LOCALAPPDATA 'ensemble-claude-code'
if (-not (Test-Path (Join-Path $ensembleHome 'CLAUDE.md'))) {
    Write-Host "Ensemble home not found or incomplete at $ensembleHome - run deploy-to-host.ps1 first."
    exit 1
}

$configFile = Join-Path $ensembleHome '.claude.json'

# Pinned to the audited artifact (@playwright/mcp@0.0.77); -y so npx never blocks
# on an install prompt in a non-interactive stdio child; --isolated for an
# ephemeral, credential-free browser profile. Double quotes escaped as \" for
# PS 5.1 native-arg passing; no spaces in the JSON keeps PowerShell from
# re-wrapping the token. NO provenance or other custom keys inside this entry -
# .claude.json is harness-owned; the door is carried by the curation record and
# this script's header, never in-entry.
$serverJson = '{\"type\":\"stdio\",\"command\":\"npx\",\"args\":[\"-y\",\"@playwright/mcp@0.0.77\",\"--isolated\"]}'

$prev = $env:CLAUDE_CONFIG_DIR
try {
    $env:CLAUDE_CONFIG_DIR = $ensembleHome

    # Idempotence: if a playwright entry already exists in this home's config,
    # remove it first so the re-add is clean.
    $already = $false
    if (Test-Path $configFile) {
        try {
            $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($cfg.mcpServers -and $cfg.mcpServers.playwright) { $already = $true }
        } catch { }
    }
    if ($already) {
        Write-Host "Existing playwright entry found; removing it first (idempotent re-wire)."
        claude mcp remove playwright 2>$null
    }

    Write-Host "Registering playwright at user scope (pinned @playwright/mcp@0.0.77, --isolated)..."
    claude mcp add-json playwright $serverJson --scope user

    # --- Verify own footprint ---
    Write-Host ""
    Write-Host "Verifying the entry landed in $configFile ..."
    if (-not (Test-Path $configFile)) {
        Write-Host "FOOTPRINT FAIL: $configFile does not exist." -ForegroundColor Red
        Write-Host "add-json may have written to the default ~\.claude.json instead of the" -ForegroundColor Red
        Write-Host "CLAUDE_CONFIG_DIR home (footgun 1 - undocumented write redirect). Check" -ForegroundColor Red
        Write-Host "'claude mcp list' and your ~\.claude.json, then report back." -ForegroundColor Red
        exit 1
    }
    $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
    $entry = $null
    if ($cfg.mcpServers) { $entry = $cfg.mcpServers.playwright }
    if (-not $entry) {
        Write-Host "FOOTPRINT FAIL: no mcpServers.playwright entry in $configFile." -ForegroundColor Red
        Write-Host "The write did not land where expected (footgun 1 or 2)." -ForegroundColor Red
        exit 1
    }
    $argsText = ($entry.args -join ' ')
    if ($argsText -notmatch '@playwright/mcp@0\.0\.77') {
        Write-Host "FOOTPRINT FAIL: playwright entry present but not pinned to @playwright/mcp@0.0.77." -ForegroundColor Red
        Write-Host "  args: $argsText" -ForegroundColor Red
        exit 1
    }
    Write-Host "OK: mcpServers.playwright present and pinned."
    Write-Host "  args: $argsText"
    Write-Host ""
    Write-Host "claude mcp list (for your eyes - confirm 'playwright' shows connected):"
    claude mcp list
    Write-Host ""
    Write-Host "If playwright shows NOT connected, see footgun 3 in this script's header (cmd /c)."
    Write-Host "Then start a session and confirm the playwright tools appear and prompt (the ask rule)."
}
finally {
    $env:CLAUDE_CONFIG_DIR = $prev
}
