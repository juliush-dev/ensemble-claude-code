# Ensemble (ensemble-claude-code) - session launcher. Windows PowerShell 5.1 compatible.
# ASCII-ONLY FILE, deliberately (PS 5.1 reads BOM-less files as ANSI; keep pure ASCII).
#
# Starts a Claude Code session inside the Ensemble's isolated home, from any
# directory. The config home is set for this launch only; your shell keeps its
# own environment afterward. Extra arguments pass through to claude, e.g.:
#   & "$env:LOCALAPPDATA\ensemble-claude-code\launch\start-ensemble.ps1" -p "hello"
#
# One-word entry is now the `cos` dispatcher (launch\cos.ps1) - the single
# maintained profile pattern for this home. Add this line to your PowerShell
# profile ($PROFILE), which dot-sources the deployed dispatcher:
#   . "$env:LOCALAPPDATA\ensemble-claude-code\launch\cos.ps1"
# then start a session from any directory with:  cos launch [args]
# (The former standalone `function ensemble { ... }` one-liner is retired in
# favor of the dispatcher, so the launch invocation lives in exactly one place.)

$ensembleHome = Join-Path $env:LOCALAPPDATA 'ensemble-claude-code'
if (-not (Test-Path (Join-Path $ensembleHome 'CLAUDE.md'))) {
    Write-Host "Ensemble home not found or incomplete at $ensembleHome - run deploy-to-host.ps1 first."
    exit 1
}

# The main-session rules: the home's CONCERTMASTER.md, the Concertmaster's own
# rules, which no member loads. They reach the main session's system prompt
# through --append-system-prompt-file (members never receive that prompt), and
# ENSEMBLE_CONCERTMASTER_APPENDED=1 tells the session cue hook
# (hooks\session-start-cue.sh) not to print them again as its fallback. A home
# without the file launches without either, and the hook finds no file to print.
$mainRules = Join-Path $ensembleHome 'CONCERTMASTER.md'
$mainArgs = @()
if (Test-Path $mainRules) {
    $mainArgs = @('--append-system-prompt-file', $mainRules)
} else {
    Write-Host "Ensemble home has no CONCERTMASTER.md at $ensembleHome - the main-session rules are missing; run deploy-to-host.ps1 -Update."
}

$prev = $env:CLAUDE_CONFIG_DIR
$prevNoFlicker = $env:CLAUDE_CODE_NO_FLICKER
$prevRepaint = $env:CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT
$prevAppended = $env:ENSEMBLE_CONCERTMASTER_APPENDED
$code = 0
try {
    $env:CLAUDE_CONFIG_DIR = $ensembleHome
    if ($mainArgs.Count -gt 0) { $env:ENSEMBLE_CONCERTMASTER_APPENDED = '1' } else { $env:ENSEMBLE_CONCERTMASTER_APPENDED = $null }
    # Fullscreen TUI rendering (a research-preview harness feature; no CLI flag)
    # as an ensemble-launch default: CLAUDE_CODE_NO_FLICKER=1 turns on the
    # fullscreen/alt-screen rendering, and CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1
    # fixes a documented Windows Terminal stale-fragment bug in that mode. Both are
    # set-if-unset so a deliberate override (e.g. =0 to opt out for a session) wins,
    # and both are restored below so the calling shell stays untouched.
    if (-not (Test-Path Env:CLAUDE_CODE_NO_FLICKER)) { $env:CLAUDE_CODE_NO_FLICKER = '1' }
    if (-not (Test-Path Env:CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT)) { $env:CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT = '1' }
    # --setting-sources user: only the home's own settings govern the session
    # (no project or local settings files) - the whole-shape consistency lever.
    claude --setting-sources user @mainArgs @args
    $code = $LASTEXITCODE
}
finally {
    $env:CLAUDE_CONFIG_DIR = $prev
    $env:CLAUDE_CODE_NO_FLICKER = $prevNoFlicker
    $env:CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT = $prevRepaint
    $env:ENSEMBLE_CONCERTMASTER_APPENDED = $prevAppended
}
exit $code
