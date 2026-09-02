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
# outside its shared workspace (a session-side "deploy" to %LOCALAPPDATA% is
# invisible on the real host). The human runs the final hop; the script's own
# output is the deploy-time footprint.
#
# What it does: copies the staged set from this folder to
# %LOCALAPPDATA%\ensemble-claude-code. The source ships CLEAN of factory
# provenance since 2026-09-02 (the line-1 always-on comments and the agent cards'
# provenance: frontmatter field were relocated to the workbench's factory-side
# provenance ledger), so the two strip functions below run as structural GUARDS:
# on a clean source they find nothing and pass every file through unchanged, and
# would act only if a provenance line ever crept back into a body copy. It prunes
# a host skills\ folder only when skills-shipped.txt (the append-only manifest of
# every skill this COS has ever shipped) lists it AND the current source no longer
# carries it - a shipped-then-retired skill; a host-added skill this COS never
# shipped is left alone. Then it hash-verifies every file in the verified set
# (byte-identical against source, the agent cards against their guard-processed
# content, settings.json against the merged text when a host companion is present;
# the six always-on copies excepted) and prints the inventory.
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
        Write-Host "Update mode: overwriting the staged files in place; session, trust, and login state stay untouched. (Git rolls back anything the source ever carried. A host skills folder this COS shipped in an earlier release but no longer carries is pruned - it came from the source, so git can restore it; a skills folder this COS never shipped is left alone as yours. -Force is the other path: it moves the whole home to a timestamped backup - plugins, sessions, and login move with it and are re-established by hand.)"
    } elseif (-not $Force) {
        Write-Host ""
        Write-Host "Target already exists. Contents:"
        Get-ChildItem $target | Select-Object -ExpandProperty Name
        Write-Host ""
        Write-Host "Re-run with -Update to refresh the staged files in place (keeps login/session state; prunes only a skill this COS shipped and has since retired, and leaves any skill you added yourself alone),"
        Write-Host "or with -Force to replace the whole home (the existing directory is moved to a timestamped backup first; plugins, sessions, and login move with it and are re-established by hand)."
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

# Guard: strip a line-1 provenance comment if one is present, without touching
# anything else. The source ships clean since 2026-09-02, so this normally finds
# nothing and copies the file byte-for-byte; it acts only if a comment ever
# creeps back into a body copy.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$alwaysOnStrippedCount = 0
function Copy-Stripped($from, $to) {
    $text = [IO.File]::ReadAllText($from)
    $stripped = $text -replace '^<!-- provenance:[^\r\n]*\r?\n', ''
    if ($stripped -ne $text) { $script:alwaysOnStrippedCount++ }
    [IO.File]::WriteAllText($to, $stripped, $utf8NoBom)
}

# Guard: strip a provenance frontmatter field from an agent card (the YAML
# frontmatter block only, between the leading --- fences) without touching
# anything else. The source ships clean since 2026-09-02, so every card now has
# no provenance key and deploys unchanged; the guard acts only if a key ever
# creeps back. Were a value present, it would be a single-line scalar; a future
# multi-line value (block scalar, an unclosed single quote, or an indented
# continuation) fails loudly here rather than half-stripping a card. Integrity is
# checked against this guard-processed content (identical to source when the card
# is clean), not against a separate raw path (the hash step below).
$strippedExpected = @{}
$fmStrippedCount = 0
function Copy-StrippedFrontmatter($from, $to, $rel) {
    $text = [IO.File]::ReadAllText($from)
    $m = [regex]::Match($text, '\A---\r?\n(?<fm>.*?\r?\n)---\r?\n', 'Singleline')
    if ($m.Success) {
        $fm = $m.Groups['fm'].Value
        $pm = [regex]::Match($fm, '(?m)^provenance:(?<val>[^\r\n]*)(?:\r?\n|\z)')
        if ($pm.Success) {
            $val = $pm.Groups['val'].Value.Trim()
            if ($val -match '^[|>]') { throw "Refusing to strip $rel : provenance uses a multi-line block scalar." }
            if (($val -match "^'") -and ($val -notmatch "'\s*`$")) { throw "Refusing to strip $rel : provenance single-quoted value is not closed on one line." }
            $after = $pm.Index + $pm.Length
            if (($after -lt $fm.Length) -and (($fm[$after] -eq ' ') -or ($fm[$after] -eq "`t"))) { throw "Refusing to strip $rel : provenance value continues onto the next line." }
            $fmStart = $m.Groups['fm'].Index
            $text = $text.Substring(0, $fmStart) + $fm.Remove($pm.Index, $pm.Length) + $text.Substring($fmStart + $fm.Length)
            $script:fmStrippedCount++
        }
    }
    [IO.File]::WriteAllText($to, $text, $utf8NoBom)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $strippedExpected[$rel] = ([BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($text)))) -replace '-', ''
}

Copy-Stripped (Join-Path $src 'always-on\CLAUDE.md') (Join-Path $target 'CLAUDE.md')
Get-ChildItem (Join-Path $src 'always-on\rules') -Filter *.md | ForEach-Object {
    Copy-Stripped $_.FullName (Join-Path $target ("rules\" + $_.Name))
}
Get-ChildItem (Join-Path $src 'agents') -Filter *.md | ForEach-Object {
    $rel = "agents\" + $_.Name
    Copy-StrippedFrontmatter $_.FullName (Join-Path $target $rel) $rel
}
Get-ChildItem (Join-Path $src 'skills') -Directory | ForEach-Object {
    $d = Join-Path $target ("skills\" + $_.Name)
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Copy-Item (Join-Path $_.FullName 'SKILL.md') $d
    # Carry a skill's references\ folder if it has one (five skills ship
    # references - the curated obsidian trio plus felt-intent-extraction and
    # mermaid-multiview-learning-document; the seven native runbooks do not).
    $refs = Join-Path $_.FullName 'references'
    if (Test-Path $refs) {
        $rd = Join-Path $d 'references'
        New-Item -ItemType Directory -Force -Path $rd | Out-Null
        Copy-Item (Join-Path $refs '*') $rd
    }
}
# Prune retired factory skills, gated by skills-shipped.txt (the append-only
# manifest of every skill folder this COS has ever shipped). A host skills\ folder
# is removed ONLY when it is BOTH listed in the manifest (an earlier release
# shipped it) AND absent from the current source (this release retired it) - e.g.
# skills\unslop, shipped then renamed to writing-and-talking-style, would
# otherwise linger beside its replacement on an -Update. A folder NOT in the
# manifest is one this COS never shipped (a host-added skill) and is kept. Scoped
# strictly to skills\ subdirectories; nothing else is ever removed.
$manifestPath = Join-Path $src 'skills-shipped.txt'
$shipped = @()
if (Test-Path $manifestPath) {
    $shipped = Get-Content $manifestPath | Where-Object { $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
# Self-policing: every skill this release ships must be listed in the manifest, or
# a future retirement of it could never be pruned (the gate would read it as
# host-added). Warn loudly per missing name; the deploy still proceeds.
Get-ChildItem (Join-Path $src 'skills') -Directory | ForEach-Object {
    if ($shipped -notcontains $_.Name) {
        Write-Warning "skills-shipped.txt does not list '$($_.Name)' - add it, or a future retirement cannot be pruned."
    }
}
$targetSkills = Join-Path $target 'skills'
if (Test-Path $targetSkills) {
    Get-ChildItem $targetSkills -Directory | ForEach-Object {
        $sk = $_.Name
        if (Test-Path (Join-Path $src ("skills\" + $sk))) { return }  # still in source: keep
        if ($shipped -contains $sk) {
            Remove-Item $_.FullName -Recurse -Force
            Write-Host "Pruned retired factory skill: skills\$sk (an earlier release shipped it; this one does not)"
        } else {
            Write-Host "Kept host-added skill: skills\$sk (this COS never shipped it, so the deploy does not manage it)"
        }
    }
}

Copy-Item (Join-Path $src 'hooks\*.sh') (Join-Path $target 'hooks')
Copy-Item (Join-Path $src 'launch\*.ps1') (Join-Path $target 'launch')

# Host companion: settings.local.json beside this script (gitignored, never
# tracked - publishable-clean) carries host-specific settings such as
# permissions.additionalDirectories. When present it is deep-merged into the
# deployed settings.json (objects merge key by key, arrays concatenate without
# duplicates, companion scalars win); the tracked settings.json stays clean.
# The launcher's --setting-sources user means only the deployed settings.json
# governs a session, so this merge is the one door for host values. Tracked
# example: settings.local.example.json. (ConvertTo-Json re-serializes: the
# deployed text is JSON-equivalent to the source, not byte-identical, so the
# hash check below compares the target against the merged text itself.)
function Merge-Json($base, $over) {
    foreach ($p in $over.PSObject.Properties) {
        $name = $p.Name
        $ov = $p.Value
        $bp = $base.PSObject.Properties[$name]
        if ($null -eq $bp) {
            $base | Add-Member -NotePropertyName $name -NotePropertyValue $ov
            continue
        }
        $bv = $bp.Value
        if (($bv -is [System.Management.Automation.PSCustomObject]) -and ($ov -is [System.Management.Automation.PSCustomObject])) {
            Merge-Json $bv $ov
        } elseif (($bv -is [System.Array]) -and ($ov -is [System.Array])) {
            $bp.Value = @(($bv + $ov) | Select-Object -Unique)
        } else {
            $bp.Value = $ov
        }
    }
}
$companion = Join-Path $src 'settings.local.json'
$settingsMergedText = $null
if (Test-Path $companion) {
    $base = Get-Content (Join-Path $src 'settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $over = Get-Content $companion -Raw -Encoding UTF8 | ConvertFrom-Json
    Merge-Json $base $over
    $settingsMergedText = ($base | ConvertTo-Json -Depth 20)
    [IO.File]::WriteAllText((Join-Path $target 'settings.json'), $settingsMergedText, $utf8NoBom)
    Write-Host "settings.json: deployed as source merged with the host companion settings.local.json."
} else {
    Copy-Item (Join-Path $src 'settings.json') $target
}
Copy-Item (Join-Path $src '.mcp.json') $target

# Integrity: the 42 files hash-compare against source, byte-identical except
# settings.json (against the merged text when a host companion is present) and
# the five agent cards (against their guard-processed content, which equals the
# source byte-for-byte while the source ships clean, as it now does).
# (19 core - the 18 v1 core plus launch\cos.ps1, the cos dispatcher; + the 8
# curated obsidian skill files: three SKILL.md plus five references; + the 11
# promoted formal-library files: six SKILL.md (cross-shell-command,
# skill-frontmatter, decision-proposal, felt-intent-extraction,
# ubiquitous-language, mermaid-multiview) plus felt-intent's one reference
# (ontological-audit.md) and mermaid's four references (REFERENCE,
# QUALITY_CHECKLIST, and two flattened templates); + 3 native skills
# (operational-lane-discipline, health-check, wrap); + 1 curated skill
# (writing-and-talking-style, one SKILL.md, no references/).)
$same = @(
    'agents\scout.md', 'agents\builder.md', 'agents\examiner.md', 'agents\archivist.md', 'agents\operator.md',
    'hooks\session-end-litter-flag.sh', 'hooks\guard-examiner-bash.sh', 'hooks\guard-archivist-paths.sh',
    'hooks\guard-push-gate.sh',
    'launch\start-ensemble.ps1', 'launch\wire-mcp.ps1', 'launch\cos.ps1',
    'settings.json', '.mcp.json',
    'skills\onboard\SKILL.md', 'skills\pass-discipline\SKILL.md', 'skills\unit-close\SKILL.md',
    'skills\occurrence\SKILL.md', 'skills\designate\SKILL.md',
    'skills\operational-lane-discipline\SKILL.md',
    'skills\health-check\SKILL.md',
    'skills\wrap\SKILL.md',
    'skills\writing-and-talking-style\SKILL.md',
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
    if (($p -eq 'settings.json') -and ($null -ne $settingsMergedText)) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $a = ([BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($settingsMergedText)))) -replace '-', ''
        $b = (Get-FileHash (Join-Path $target $p) -Algorithm SHA256).Hash
        if ($a -ne $b) { $failed += $p }
        continue
    }
    if ($strippedExpected.ContainsKey($p)) {
        $b = (Get-FileHash (Join-Path $target $p) -Algorithm SHA256).Hash
        if ($strippedExpected[$p] -ne $b) { $failed += $p }
        continue
    }
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
Write-Host "All $($same.Count) files hash-verified (settings.json against the merged text when a host companion is present; the agent cards against their guard-processed content). Provenance guards ran clean: $alwaysOnStrippedCount always-on comment line(s) and $fmStrippedCount agent card field(s) stripped - the source ships clean of factory provenance, so the guards act only if it ever creeps back."
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
Write-Host "(or install the one-word cos dispatcher - see launch\cos.ps1's header - then: cos launch)."
Write-Host ""
Write-Host "Next step (one-time): launch it and run /login once. After that, P8 smoke can begin."
Write-Host ""
Write-Host "IMPORTANT: restart any Ensemble session that is already open - config (settings, permission rules, MCP wiring) is read at session start, so a running session keeps its old instructions until you relaunch it."
