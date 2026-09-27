# Ensemble (ensemble-claude-code) - headless startup-context probe. Windows PowerShell 5.1 compatible.
#
# ASCII-ONLY FILE, deliberately: PowerShell 5.1 reads BOM-less files as ANSI,
# which turns UTF-8 punctuation (em dashes, smart quotes) into stray quote
# characters that break string parsing. Keep this file pure ASCII.
# PS 5.1 note: no '&&', no ternary, no null-coalescing anywhere in this file.
#
# PURPOSE
#   The ceiling-doctrine anchor reading: the always-on memory layer has NO
#   provider hard cap, so house sizing is tracked as the measured share of the
#   context window at
#   session start, pinned to a named model/window tier. This probe reads that
#   startup total non-interactively, from the SAME deployed home an interactive
#   session loads, so the anchor can be re-read at any -Update without the user
#   in the loop.
#
# HOW IT MIRRORS THE LIVE LAUNCH (grounded against launch/start-ensemble.ps1)
#   An interactive session launches as:  CLAUDE_CONFIG_DIR = <home>;
#   ENSEMBLE_CONCERTMASTER_APPENDED = 1; claude --setting-sources user
#   --append-system-prompt-file <home>\CONCERTMASTER.md ...   This probe sets the
#   SAME CLAUDE_CONFIG_DIR and marker and passes the SAME --setting-sources user
#   and the same appended main-session rules file, so the same deployed layer
#   (home CLAUDE.md + rules + the main-session rules + skill listing + members)
#   loads, and the session cue prints no fallback copy of the rules on top. A
#   home without CONCERTMASTER.md is probed without the flag or the marker, as
#   the launcher would start it. It adds
#   -p (headless) with a trivial prompt and --output-format stream-json --verbose,
#   and it deliberately does NOT pass --bare (--bare skips CLAUDE.md/skills/hooks/
#   MCP/auto-memory, which would defeat the reading). Run both this probe and an
#   interactive /context from the SAME working directory, same host, same day, so
#   the two are comparable (project-scope CLAUDE.md and git status, if any, load
#   from the working directory in both).
#
# CALIBRATION STATUS
#   This probe is the INSTRUMENT OF RECORD for the whole-startup share.
#   Interactive /context is the ATTRIBUTION instrument (it breaks the startup
#   total into categories); this probe's usage fields carry NO category
#   breakdown, so read /context when the tripwire fires or at deploy footprints.
#   Calibration pair (same host, same day, same working directory):
#     probe startup total 34,270 tokens (API-counted) vs interactive /context
#     estimate 35.3k; offset ~ -1.0k / ~2.9% (probe below /context), inside the
#     documented +/-10% /context wobble. The probe reports API-counted usage
#     where /context estimates.
#   The headless first-assistant-message usage is the same input-only quantity
#   the statusline docs define.
#
# GROUNDING NOTES
#   The always-on memory layer has no provider hard cap; the real limits are the
#   model/window tiers in the table below. Headless first-message usage is the
#   anchor path this probe reads.
#
# USAGE
#   powershell -ExecutionPolicy Bypass -File .\probe-context.ps1
#   powershell -ExecutionPolicy Bypass -File .\probe-context.ps1 -DryRun
#   powershell -ExecutionPolicy Bypass -File .\probe-context.ps1 -DryRun -SampleStreamPath .\sample-stream.ndjson
#
#   -EnsembleHome       config-dir home to load (default: %LOCALAPPDATA%\ensemble-claude-code)
#   -WorkingDirectory   dir to run from (default: current dir; keep it identical to the /context run)
#   -Prompt             the trivial prompt (default: "Reply with the single word: ready")
#   -DryRun             print the exact planned invocation; do NOT launch claude
#   -SampleStreamPath   with -DryRun, parse this NDJSON fixture instead of launching (tests the parse/report)
#
# BEHAVIOR NOTE
#   Under headless runs the SessionEnd litter-flag hook may report
#   "failed: Hook cancelled" on stderr - this is cosmetic (the -p process exits
#   before the hook completes) and does NOT affect the startup usage reading
#   this probe captures from the first assistant message. On PS 5.1, that
#   stderr line used to turn into a terminating NativeCommandError under this
#   script's own 'Stop' preference and kill the probe before it could read
#   anything; the live claude call below now runs under 'Continue' for itself
#   only (mirrors the wire-mcp.ps1 fix, commit 6478bed), so the noise stays
#   cosmetic in practice too.

param(
    [string]$EnsembleHome = (Join-Path $env:LOCALAPPDATA 'ensemble-claude-code'),
    [string]$WorkingDirectory = (Get-Location).Path,
    [string]$Prompt = 'Reply with the single word: ready',
    [switch]$DryRun,
    [string]$SampleStreamPath
)

$ErrorActionPreference = 'Stop'

# --- Named-tier window table (edit here; token counts are provider-set) --------
# Match is case-insensitive substring against the model id reported by the stream.
# The first tier with any matching substring wins.
$tierTable = @(
    @{ Tier = '1M (Sonnet 5 / Opus 4.8 / Opus 5 / Opus 5.5 / Fable 5)'; Window = 1000000; Match = @('sonnet-5', 'opus-4-8', 'opus-5', 'fable-5', 'fable', '[1m]') },
    @{ Tier = '200K (Haiku 4.5 / legacy Sonnet 4.5 / Opus 4.5 / Opus 4.1 / gateway / disabled-1M)'; Window = 200000; Match = @('haiku', 'sonnet-4-5', 'opus-4-5', 'opus-4-1') }
)
$defaultWindow = 1000000
$defaultTier = 'UNMATCHED - defaulted to 1M (edit the tier table for this model)'

function Get-IntField {
    param($obj, [string]$name)
    if ($null -eq $obj) { return 0 }
    $v = $obj.$name
    if ($null -eq $v) { return 0 }
    return [int]$v
}

function Resolve-Tier {
    param([string]$model)
    $m = $model.ToLowerInvariant()
    foreach ($t in $tierTable) {
        foreach ($sub in $t.Match) {
            if ($m.Contains($sub.ToLowerInvariant())) {
                return @{ Tier = $t.Tier; Window = $t.Window }
            }
        }
    }
    return @{ Tier = $defaultTier; Window = $defaultWindow }
}

function Show-Report {
    param([string[]]$lines)

    $model = $null
    $usage = $null

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0) { continue }
        $obj = $null
        try {
            $obj = $trimmed | ConvertFrom-Json
        } catch {
            continue
        }
        if ($null -eq $obj) { continue }

        # Model: prefer the init/system event; fall back to any object carrying .model.
        if ($null -eq $model) {
            if ($obj.type -eq 'system' -and $obj.model) { $model = [string]$obj.model }
            elseif ($obj.model) { $model = [string]$obj.model }
            elseif ($obj.message -and $obj.message.model) { $model = [string]$obj.message.model }
        }

        # Usage: the FIRST assistant message's usage object is the startup reading.
        if ($null -eq $usage -and $obj.type -eq 'assistant' -and $obj.message -and $obj.message.usage) {
            $usage = $obj.message.usage
            if ($null -eq $model -and $obj.message.model) { $model = [string]$obj.message.model }
        }
    }

    if ($null -eq $usage) {
        Write-Host "ERROR: no assistant-message 'usage' object found in the stream." -ForegroundColor Red
        Write-Host "Confirm the run used --output-format stream-json --verbose and was NOT --bare."
        exit 1
    }
    if ($null -eq $model) { $model = '(model not reported in stream)' }

    $inputTok = Get-IntField $usage 'input_tokens'
    $cacheCreate = Get-IntField $usage 'cache_creation_input_tokens'
    $cacheRead = Get-IntField $usage 'cache_read_input_tokens'
    $outputTok = Get-IntField $usage 'output_tokens'
    $startupTotal = $inputTok + $cacheCreate + $cacheRead

    $tier = Resolve-Tier $model
    $pct = 0
    if ($tier.Window -gt 0) {
        $pct = [math]::Round(($startupTotal / $tier.Window) * 100, 4)
    }

    Write-Host ""
    Write-Host "=== Ensemble startup-context probe (ceiling-doctrine anchor reading) ==="
    Write-Host ("Model reported : {0}" -f $model)
    Write-Host ("Tier / window  : {0}  ({1:N0} tokens)" -f $tier.Tier, $tier.Window)
    Write-Host ""
    Write-Host "First assistant-message usage (startup context, input-only formula):"
    Write-Host ("  input_tokens                : {0,10:N0}" -f $inputTok)
    Write-Host ("  cache_creation_input_tokens : {0,10:N0}" -f $cacheCreate)
    Write-Host ("  cache_read_input_tokens     : {0,10:N0}" -f $cacheRead)
    Write-Host ("  (output_tokens, excluded)   : {0,10:N0}" -f $outputTok)
    Write-Host "  --------------------------------------------"
    Write-Host ("  startup total               : {0,10:N0}" -f $startupTotal)
    Write-Host ""
    Write-Host ("Share of window : {0}%  (raw {1:N0} / {2:N0}, tier: {3})" -f $pct, $startupTotal, $tier.Window, $tier.Tier)
    Write-Host ""
    Write-Host "Note: this is a headless fresh-process startup reading, NOT a live /context."
    Write-Host "This probe is the instrument of record for the whole-startup share; interactive /context is the attribution instrument (category grain)."
    Write-Host ""
}

# --- Build the launch shape (mirrors launch/start-ensemble.ps1) ----------------
$mainRules = Join-Path $EnsembleHome 'CONCERTMASTER.md'
$mainArgs = @()
if (Test-Path $mainRules) { $mainArgs = @('--append-system-prompt-file', $mainRules) }
$claudeArgs = @('--setting-sources', 'user') + $mainArgs + @(
    '-p', $Prompt,
    '--output-format', 'stream-json',
    '--verbose'
)
$markerLine = 'ENSEMBLE_CONCERTMASTER_APPENDED=<unset>'
if ($mainArgs.Count -gt 0) { $markerLine = 'ENSEMBLE_CONCERTMASTER_APPENDED=1' }

Write-Host ("Ensemble home     : {0}" -f $EnsembleHome)
Write-Host ("Working directory : {0}" -f $WorkingDirectory)
Write-Host ("Planned command   : CLAUDE_CONFIG_DIR=<home> {0} claude {1}" -f $markerLine, ($claudeArgs -join ' '))

if ($DryRun) {
    Write-Host ""
    Write-Host "-DryRun: the live 'claude' binary is NOT invoked."
    if ($SampleStreamPath) {
        if (-not (Test-Path $SampleStreamPath)) {
            Write-Host ("ERROR: -SampleStreamPath not found: {0}" -f $SampleStreamPath) -ForegroundColor Red
            exit 1
        }
        Write-Host ("Parsing fixture stream: {0}" -f $SampleStreamPath)
        $sampleLines = Get-Content -LiteralPath $SampleStreamPath
        Show-Report -lines $sampleLines
    } else {
        Write-Host "Pass -SampleStreamPath <ndjson> to exercise the parse/report on a fixture."
    }
    exit 0
}

# --- Live run ------------------------------------------------------------------
if (-not (Test-Path (Join-Path $EnsembleHome 'CLAUDE.md'))) {
    Write-Host ("ERROR: Ensemble home not found or incomplete at {0} - run deploy-to-host.ps1 first." -f $EnsembleHome) -ForegroundColor Red
    exit 1
}

$prevConfig = $env:CLAUDE_CONFIG_DIR
$prevAppended = $env:ENSEMBLE_CONCERTMASTER_APPENDED
$prevLocation = (Get-Location).Path
$prevEap = $ErrorActionPreference
$rawLines = $null
try {
    $env:CLAUDE_CONFIG_DIR = $EnsembleHome
    if ($mainArgs.Count -gt 0) { $env:ENSEMBLE_CONCERTMASTER_APPENDED = '1' } else { $env:ENSEMBLE_CONCERTMASTER_APPENDED = $null }
    Set-Location -LiteralPath $WorkingDirectory
    Write-Host ""
    Write-Host "Launching headless probe against the deployed home..."
    # The nested claude's own SessionEnd hook can print noise on stderr as the
    # -p process exits (see BEHAVIOR NOTE above). Under 'Stop', PS 5.1 turns
    # that stderr line into a terminating NativeCommandError, killing the probe
    # before Show-Report ever runs. This one call runs under 'Continue' so
    # stderr becomes a non-terminating, displayed-but-uncaptured error record
    # instead: $rawLines still gets only stdout, unchanged from before.
    $ErrorActionPreference = 'Continue'
    $rawLines = & claude @claudeArgs
    $ErrorActionPreference = $prevEap
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Host ("WARNING: claude exited with code {0}; parsing whatever streamed." -f $exitCode) -ForegroundColor Yellow
    }
}
finally {
    $ErrorActionPreference = $prevEap
    $env:CLAUDE_CONFIG_DIR = $prevConfig
    $env:ENSEMBLE_CONCERTMASTER_APPENDED = $prevAppended
    Set-Location -LiteralPath $prevLocation
}

if ($null -eq $rawLines) {
    Write-Host "ERROR: no output captured from claude." -ForegroundColor Red
    exit 1
}

Show-Report -lines $rawLines
