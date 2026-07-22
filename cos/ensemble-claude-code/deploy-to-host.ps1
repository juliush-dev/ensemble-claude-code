# provenance: pursuit claude-code-cos-realization (contracts/2026-07-07-claude-code-cos-realization/)
# Ensemble (ensemble-claude-code) - host deploy script. Windows PowerShell 5.1 compatible.
#
# ASCII-ONLY FILE, deliberately: PowerShell 5.1 reads BOM-less files as ANSI,
# which turns UTF-8 punctuation (em dashes, smart quotes) into stray quote
# characters that break string parsing. Keep this file pure ASCII.
#
# Run this in YOUR OWN PowerShell on the target host:
#   powershell -ExecutionPolicy Bypass -File .\deploy-to-host.ps1
#
# Why user-executed: an agent session cannot draw a trustworthy footprint
# outside its shared workspace (2026-07-08 lesson: a session-side "deploy"
# to %LOCALAPPDATA% was invisible on the real host). The human runs the final
# hop; the script's own output is the deploy-time footprint.
#
# What it does: copies the staged set from this folder to
# %LOCALAPPDATA%\ensemble-claude-code per the COS.md deploy map, stripping the
# provenance comment line from the deployed always-on copies (the source keeps
# them), then hash-verifies every byte-identical file and prints the inventory.
# It refuses to overwrite an existing target unless -Force (which moves the
# existing directory to a timestamped backup first; that backup is the
# rollback baseline).

param([switch]$Force, [switch]$Update)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$target = Join-Path $env:LOCALAPPDATA 'ensemble-claude-code'

Write-Host "Source: $src"
Write-Host "Target: $target"

if (Test-Path $target) {
    if ($Update) {
        Write-Host "Update mode: overwriting the staged files in place; session, trust, and login state stay untouched. (Git holds the source history for rollback.)"
    } elseif (-not $Force) {
        Write-Host ""
        Write-Host "Target already exists. Contents:"
        Get-ChildItem $target | Select-Object -ExpandProperty Name
        Write-Host ""
        Write-Host "Re-run with -Update to refresh the staged files in place (keeps login/session state),"
        Write-Host "or with -Force to replace the whole home (the existing directory is moved to a timestamped backup first)."
        exit 1
    } else {
        $backup = "$target.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Move-Item $target $backup
        Write-Host "Rollback baseline: existing target moved to $backup"
    }
} else {
    Write-Host "Rollback baseline: target absent before deploy ($(Get-Date -Format s))"
}

New-Item -ItemType Directory -Force -Path $target | Out-Null
foreach ($d in 'rules', 'agents', 'skills', 'hooks', 'launch') {
    New-Item -ItemType Directory -Force -Path (Join-Path $target $d) | Out-Null
}

# Strip the provenance comment line (first line only) without touching anything else.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Copy-Stripped($from, $to) {
    $text = [IO.File]::ReadAllText($from)
    $text = $text -replace '^<!-- provenance:[^\r\n]*\r?\n', ''
    [IO.File]::WriteAllText($to, $text, $utf8NoBom)
}

Copy-Stripped (Join-Path $src 'always-on\CLAUDE.md') (Join-Path $target 'CLAUDE.md')
Get-ChildItem (Join-Path $src 'always-on\rules') -Filter *.md | ForEach-Object {
    Copy-Stripped $_.FullName (Join-Path $target ("rules\" + $_.Name))
}
Copy-Item (Join-Path $src 'agents\*.md') (Join-Path $target 'agents')
Get-ChildItem (Join-Path $src 'skills') -Directory | ForEach-Object {
    $d = Join-Path $target ("skills\" + $_.Name)
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Copy-Item (Join-Path $_.FullName 'SKILL.md') $d
    # Carry a skill's references\ folder if it has one (the curated obsidian
    # trio ships references; the five native runbooks do not).
    $refs = Join-Path $_.FullName 'references'
    if (Test-Path $refs) {
        $rd = Join-Path $d 'references'
        New-Item -ItemType Directory -Force -Path $rd | Out-Null
        Copy-Item (Join-Path $refs '*') $rd
    }
}
Copy-Item (Join-Path $src 'hooks\*.sh') (Join-Path $target 'hooks')
Copy-Item (Join-Path $src 'launch\*.ps1') (Join-Path $target 'launch')
Copy-Item (Join-Path $src 'settings.json') $target
Copy-Item (Join-Path $src '.mcp.json') $target

# Integrity: the 38 files deployed byte-identical hash-compare against source.
# (18 core + the 8 curated obsidian skill files: three SKILL.md plus five
# references, admitted through curation/claude-code/records/obsidian.md; + the
# 11 promoted formal-library files, admitted through the designated-work door
# via pursuit formal-skills-promotion: six SKILL.md (cross-shell-command,
# skill-frontmatter, decision-proposal, felt-intent-extraction,
# ubiquitous-language, mermaid-multiview) plus felt-intent's one reference
# (the strict-ontological audit slice, ontological-audit.md) and mermaid's
# four references (REFERENCE, QUALITY_CHECKLIST, and two flattened templates);
# + 1 native skill (operational-lane-discipline) through the designated-work
# door, the operational-lane adoption on the user's word 2026-07-11.)
$same = @(
    'agents\scout.md', 'agents\builder.md', 'agents\examiner.md', 'agents\archivist.md', 'agents\operator.md',
    'hooks\session-end-litter-flag.sh', 'hooks\guard-examiner-bash.sh', 'hooks\guard-archivist-paths.sh',
    'hooks\guard-push-gate.sh',
    'launch\start-ensemble.ps1', 'launch\wire-mcp.ps1',
    'settings.json', '.mcp.json',
    'skills\onboard\SKILL.md', 'skills\pass-discipline\SKILL.md', 'skills\unit-close\SKILL.md',
    'skills\occurrence\SKILL.md', 'skills\designate\SKILL.md',
    'skills\operational-lane-discipline\SKILL.md',
    'skills\cross-shell-command-discipline\SKILL.md',
    'skills\skill-frontmatter-discipline\SKILL.md',
    'skills\decision-proposal-discipline\SKILL.md',
    'skills\felt-intent-extraction\SKILL.md',
    'skills\felt-intent-extraction\references\ontological-audit.md',
    'skills\ubiquitous-language-stewardship\SKILL.md',
    'skills\mermaid-multiview-learning-document\SKILL.md',
    'skills\mermaid-multiview-learning-document\references\REFERENCE.md',
    'skills\mermaid-multiview-learning-document\references\QUALITY_CHECKLIST.md',
    'skills\mermaid-multiview-learning-document\references\document-template.md',
    'skills\mermaid-multiview-learning-document\references\research-ledger-template.md',
    'skills\obsidian-markdown\SKILL.md',
    'skills\obsidian-markdown\references\CALLOUTS.md',
    'skills\obsidian-markdown\references\EMBEDS.md',
    'skills\obsidian-markdown\references\PROPERTIES.md',
    'skills\obsidian-bases\SKILL.md',
    'skills\obsidian-bases\references\FUNCTIONS_REFERENCE.md',
    'skills\json-canvas\SKILL.md',
    'skills\json-canvas\references\EXAMPLES.md'
)
$failed = @()
foreach ($p in $same) {
    $a = (Get-FileHash (Join-Path $src $p) -Algorithm SHA256).Hash
    $b = (Get-FileHash (Join-Path $target $p) -Algorithm SHA256).Hash
    if ($a -ne $b) { $failed += $p }
}
if ($failed.Count -gt 0) {
    Write-Host "HASH MISMATCH on:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host ""
Write-Host "All 38 byte-identical files hash-verified; 6 always-on files deployed with the provenance line stripped."
Write-Host ""
Write-Host "Deployed inventory (the staged set only):"
$staged = @('CLAUDE.md', 'settings.json', '.mcp.json')
$staged += Get-ChildItem (Join-Path $src 'always-on\rules') -Filter *.md | ForEach-Object { "rules\" + $_.Name }
$staged += Get-ChildItem (Join-Path $src 'agents') -Filter *.md | ForEach-Object { "agents\" + $_.Name }
$staged += Get-ChildItem (Join-Path $src 'skills') -Directory | ForEach-Object {
    $sk = $_.Name
    $items = @("skills\$sk\SKILL.md")
    $refs = Join-Path $_.FullName 'references'
    if (Test-Path $refs) {
        $items += Get-ChildItem $refs -File | ForEach-Object { "skills\$sk\references\" + $_.Name }
    }
    $items
}
$staged += Get-ChildItem (Join-Path $src 'hooks') -Filter *.sh | ForEach-Object { "hooks\" + $_.Name }
$staged += Get-ChildItem (Join-Path $src 'launch') -Filter *.ps1 | ForEach-Object { "launch\" + $_.Name }
$staged | Sort-Object | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "Anything else inside the target (credentials, sessions, caches, file history, the plugin-marketplace catalog the harness fetches on its own) is the harness's runtime state; this script never touches it."

Write-Host ""
Write-Host "Start sessions from any directory with:"
Write-Host '  & "$env:LOCALAPPDATA\ensemble-claude-code\launch\start-ensemble.ps1"'
Write-Host "(or add the one-word profile function named in that script's header)."
Write-Host ""
Write-Host "Next step (one-time): launch it and run /login once. After that, P8 smoke can begin."
Write-Host ""
Write-Host "IMPORTANT: restart any Ensemble session that is already open - config (settings, permission rules, MCP wiring) is read at session start, so a running session keeps its old instructions until you relaunch it."
