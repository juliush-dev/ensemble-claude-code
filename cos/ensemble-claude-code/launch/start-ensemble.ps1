# provenance: pursuit claude-code-cos-realization (contracts/2026-07-07-claude-code-cos-realization/)
# Ensemble (ensemble-claude-code) - session launcher. Windows PowerShell 5.1 compatible.
# ASCII-ONLY FILE, deliberately (PS 5.1 reads BOM-less files as ANSI; keep pure ASCII).
#
# Starts a Claude Code session inside the Ensemble's isolated home, from any
# directory. The config home is set for this launch only; your shell keeps its
# own environment afterward. Extra arguments pass through to claude, e.g.:
#   & "$env:LOCALAPPDATA\ensemble-claude-code\launch\start-ensemble.ps1" -p "hello"
#
# Optional one-word entry: add this line to your PowerShell profile ($PROFILE):
#   function ensemble { & "$env:LOCALAPPDATA\ensemble-claude-code\launch\start-ensemble.ps1" @args }

$ensembleHome = Join-Path $env:LOCALAPPDATA 'ensemble-claude-code'
if (-not (Test-Path (Join-Path $ensembleHome 'CLAUDE.md'))) {
    Write-Host "Ensemble home not found or incomplete at $ensembleHome - run deploy-to-host.ps1 first."
    exit 1
}

$prev = $env:CLAUDE_CONFIG_DIR
$code = 0
try {
    $env:CLAUDE_CONFIG_DIR = $ensembleHome
    # --setting-sources user: only the home's own settings govern the session
    # (no project or local settings files) - the whole-shape consistency lever.
    claude --setting-sources user @args
    $code = $LASTEXITCODE
}
finally {
    $env:CLAUDE_CONFIG_DIR = $prev
}
exit $code
