# Ensemble (ensemble-claude-code) - one-time MCP wiring for the two user-scope
# servers: playwright (the curated browser realization) and open-knowledge
# (OpenKnowledge, a declared host requirement).
# Windows PowerShell 5.1 compatible. ASCII-ONLY FILE, deliberately (PS 5.1 reads
# BOM-less files as ANSI; keep pure ASCII).
#
# WHY A SEPARATE HAND-RUN SCRIPT (not deploy-to-host.ps1):
# Both servers register at USER scope, which the harness stores in
# $CLAUDE_CONFIG_DIR\.claude.json - harness runtime state that deploy-to-host.ps1
# deliberately never touches (same boundary as login/session state). The staged
# .mcp.json at the config-home root is NOT a harness-read location for user scope
# (project scope reads .mcp.json from the WORKING directory only). This script
# writes the two user-scope entries instead. Run it ONCE, in YOUR OWN PowerShell,
# after deploy, and again after an update that changes an entry:
#   powershell -ExecutionPolicy Bypass -File .\wire-mcp.ps1
#
# It loops over the two entries. Each is idempotent (any existing user-scope
# entry of that name is removed, then the entry is added again) and each verifies
# its own footprint, by name and by its version string, failing loudly if the
# entry did not land where expected. NOTE: the self-verify confirms each entry's
# version string only (@playwright/mcp@0.0.77; @inkeep/open-knowledge@ plus
# OK_ENUMERATED); if you ever edit this script, extend the verify to also check
# playwright's --isolated and -y and the launcher's branches, or re-verify those
# by eye.
#
# THE OPEN-KNOWLEDGE ENTRY. OpenKnowledge routes each call to a project by the
# call's own cwd, so one user-scope server serves every project. The entry is a
# short launcher run by powershell -NoProfile -NonInteractive -Command: the
# ok.cmd the OpenKnowledge app puts on PATH, when Get-Command resolves it; else
# npx.cmd running @inkeep/open-knowledge at OK_ENUMERATED; else exit 127 with one
# stderr line naming the requirement. A host without OpenKnowledge still gets the
# entry: the session starts, the tools are absent, and the members say so
# (report, never fail). The launcher carries no double quotes and none of
# cmd.exe's & | < > ^, so it reaches claude intact whether claude is claude.exe
# or an npm claude.cmd shim (probed both ways).
#
# OK_ENUMERATED is the version the COS enumerated OpenKnowledge's tool list at;
# hooks\guard-openknowledge.sh's key table and the member cards derive from that
# list. It is TRACKED, not pinned: a present ok always wins whatever its version,
# and deploy-to-host.ps1 reports a host version that differs; only the npx
# fallback runs exactly this version. Moving it is the re-enumeration duty:
# re-capture tools/list, diff it against the recorded capture, update the
# guard's key table, its fixtures and the cards where a tool or field moved, then
# move this line and its twin in wire-mcp.sh together. deploy-to-host.ps1 reads
# this line (it looks for OK_ENUMERATED=) and warns when it is missing.
#
# WINDOWS FOOTGUNS this script guards against (each undocumented; each caught by
# the verify step - if one bites, adjust here and note the divergence in this
# script's own output or report it upstream, do not silently wonder):
#   1. Whether CLAUDE_CONFIG_DIR redirects add-json WRITES (docs only promise it
#      redirects reads). If an entry lands in the default ~\.claude.json instead,
#      the verify below says so explicitly.
#   2. JSON quoting: PS 5.1's legacy native-argument quoting leaves an argument
#      holding both a double quote and a space unwrapped, so it splits at the
#      space, and it double-wraps one that already starts with a quote (both
#      probed). So each entry's JSON is handed to claude after the
#      stop-parsing token --%, from an environment variable, its double quotes
#      escaped as \"; PowerShell passes that text verbatim. If add-json reports
#      a JSON parse error, the escaping needs adjusting for your PS build.
#   3. npx stdio servers on native Windows sometimes need a "cmd /c" wrapper
#      (command "cmd", args "/c","npx",...) instead of bare "npx". The doc examples
#      use bare "npx -y"; the playwright entry does too. If "claude mcp list"
#      shows playwright NOT connected, switch to the cmd /c form and record it.

$ErrorActionPreference = 'Stop'

# The version OpenKnowledge's tool list was enumerated at. Keep the spelling
# OK_ENUMERATED='x.y.z' (no spaces): deploy-to-host.ps1 reads it by that text.
$OK_ENUMERATED='0.77.7'

$ensembleHome = Join-Path $env:LOCALAPPDATA 'ensemble-claude-code'
if (-not (Test-Path (Join-Path $ensembleHome 'CLAUDE.md'))) {
    Write-Host "Ensemble home not found or incomplete at $ensembleHome - run deploy-to-host.ps1 first."
    exit 1
}

$configFile = Join-Path $ensembleHome '.claude.json'

# playwright: pinned to the audited artifact (@playwright/mcp@0.0.77); -y so npx
# never blocks on an install prompt in a non-interactive stdio child; --isolated
# for an ephemeral, credential-free browser profile.
$playwrightJson = '{"type":"stdio","command":"npx","args":["-y","@playwright/mcp@0.0.77","--isolated"]}'

# open-knowledge: the launcher, one statement per line, joined with the two
# characters \n that JSON reads as a newline. Single quotes are doubled inside
# these PowerShell literals.
$okLauncher = @(
    '$ok = @(Get-Command ok.cmd -CommandType Application -ErrorAction SilentlyContinue)',
    'if ($ok.Count -gt 0) { . $ok[0].Source mcp; exit $LASTEXITCODE }',
    '$npx = @(Get-Command npx.cmd -CommandType Application -ErrorAction SilentlyContinue)',
    ('if ($npx.Count -gt 0) { . $npx[0].Source -y ''@inkeep/open-knowledge@' + $OK_ENUMERATED + ''' mcp; exit $LASTEXITCODE }'),
    '[Console]::Error.WriteLine(''open-knowledge: neither ok.cmd nor npx.cmd was found - install the OpenKnowledge app, or Node 24 or later for the npx fallback'')',
    'exit 127'
) -join '\n'
$openKnowledgeJson = '{"type":"stdio","command":"powershell","args":["-NoProfile","-NonInteractive","-Command","' + $okLauncher + '"]}'

# NO provenance or other custom keys inside either entry - .claude.json is
# harness-owned; the rationale for this wiring lives in this script's header,
# never in-entry.
$entries = @(
    @{ Name = 'playwright';     Json = $playwrightJson;    Want = '@playwright/mcp@0.0.77';                  Label = 'pinned @playwright/mcp@0.0.77, --isolated' },
    @{ Name = 'open-knowledge'; Json = $openKnowledgeJson; Want = ('@inkeep/open-knowledge@' + $OK_ENUMERATED); Label = ('ok on PATH, else npx fallback at the enumerated @inkeep/open-knowledge@' + $OK_ENUMERATED) }
)

function Read-HomeConfig {
    if (-not (Test-Path $configFile)) { return $null }
    try { return (Get-Content $configFile -Raw | ConvertFrom-Json) } catch { return $null }
}

function Get-Entry($cfg, $name) {
    if ($null -eq $cfg -or $null -eq $cfg.mcpServers) { return $null }
    $p = $cfg.mcpServers.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

$prev = $env:CLAUDE_CONFIG_DIR
try {
    $env:CLAUDE_CONFIG_DIR = $ensembleHome

    foreach ($e in $entries) {
        $name = $e.Name
        Write-Host ""

        # Idempotence: remove any existing user-scope entry of this name first,
        # so the re-add is clean. Scoped to user, so a project-scope .mcp.json of
        # the same name in the current folder is never the one removed.
        if ($null -ne (Get-Entry (Read-HomeConfig) $name)) {
            Write-Host "Existing $name entry found; removing it first (idempotent re-wire)."
            $eap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            claude mcp remove $name --scope user 2>$null | Out-Null
            $ErrorActionPreference = $eap
        }

        Write-Host "Registering $name at user scope ($($e.Label))..."
        $env:ENSEMBLE_WIRE_NAME = $name
        $env:ENSEMBLE_WIRE_JSON = $e.Json -replace '"', '\"'
        claude --% mcp add-json %ENSEMBLE_WIRE_NAME% "%ENSEMBLE_WIRE_JSON%" --scope user

        # --- Verify own footprint ---
        Write-Host "Verifying the $name entry landed in $configFile ..."
        if (-not (Test-Path $configFile)) {
            Write-Host "FOOTPRINT FAIL: $configFile does not exist." -ForegroundColor Red
            Write-Host "add-json may have written to the default ~\.claude.json instead of the" -ForegroundColor Red
            Write-Host "CLAUDE_CONFIG_DIR home (footgun 1 - undocumented write redirect). Check" -ForegroundColor Red
            Write-Host "'claude mcp list' and your ~\.claude.json, then report back." -ForegroundColor Red
            exit 1
        }
        $entry = Get-Entry (Read-HomeConfig) $name
        if (-not $entry) {
            Write-Host "FOOTPRINT FAIL: no mcpServers.$name entry in $configFile (or the file could not be parsed)." -ForegroundColor Red
            Write-Host "The write did not land where expected (footgun 1 or 2)." -ForegroundColor Red
            exit 1
        }
        $argsText = ($entry.args -join ' ')
        if (-not $argsText.Contains($e.Want)) {
            Write-Host "FOOTPRINT FAIL: $name entry present but its args do not carry $($e.Want)." -ForegroundColor Red
            Write-Host "  args: $argsText" -ForegroundColor Red
            exit 1
        }
        Write-Host "OK: mcpServers.$name present and carrying $($e.Want)."
        Write-Host "  args: $argsText"
    }
    Remove-Item Env:\ENSEMBLE_WIRE_NAME, Env:\ENSEMBLE_WIRE_JSON -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "claude mcp list (for your eyes - confirm 'playwright' and 'open-knowledge' show connected):"
    # For your eyes only: the verify above decided success. The nested claude can
    # print hook noise on stderr, which PS 5.1 under 'Stop' turns into a
    # terminating NativeCommandError and a false exit 1. So this one call runs
    # under 'Continue', its stderr shown among its output lines.
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        claude mcp list 2>&1 | ForEach-Object { Write-Host "$_" }
    } catch {
        Write-Host "claude mcp list did not run ($($_.Exception.Message)); the entries above are verified regardless."
    } finally {
        $ErrorActionPreference = $eap
    }
    Write-Host ""
    Write-Host "If playwright shows NOT connected, see footgun 3 in this script's header (cmd /c)."
    Write-Host "If open-knowledge shows NOT connected, this host may carry neither the OpenKnowledge app's ok.cmd nor Node's npx.cmd: the members report the gap, and deploy-to-host.ps1's inventory names it."
    Write-Host "Then start a session and confirm the playwright tools appear and prompt (in the main session every playwright call asks, through the live-reads guard), and that the mcp__open-knowledge__* tools are listed."
}
finally {
    $env:CLAUDE_CONFIG_DIR = $prev
}
# Reached only when every entry verified. Explicit, so a non-zero exit left by
# the informational claude mcp list never reads as a failed wiring.
exit 0
