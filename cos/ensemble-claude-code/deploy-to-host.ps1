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
# shipped is left alone.
#
# settings.json is not copied but MERGED, by merge-settings.py, the one merge
# implementation both deploy scripts call. The home's own settings.json is the
# base. A single value the factory defines is written from the factory; a list
# gains the factory items it lacks and loses the ones the factory has retired
# since the last deploy; every other key the host carries is left exactly as it
# stands. settings.optout.json in the home names the factory items the host
# keeps out and the single values it keeps as its own. A host's own settings
# survive an update.
#
# PYTHON 3 IS A PREREQUISITE. Without it this script does not update
# settings.json at all: an existing host file is left exactly as it stands and
# the script says so, loudly, on every run until Python 3 is installed. Only a
# first deploy, where there is no host file to protect, writes source wholesale
# instead (a home with no settings file is useless).
#
# A CHROMIUM-FAMILY BROWSER IS A DECLARED HOST REQUIREMENT, NOT AN ENFORCED ONE.
# The Scout's retrieval kit (tools\scout-fetch.sh) renders script-filled pages
# in a headless Chrome, Edge or Chromium the host already carries (Brave is
# left out of the search until its headless behavior is settled; a Brave path
# still works when named through env.ENSEMBLE_BROWSER); this COS ships no
# browser. Once per run, after everything has landed, the script
# runs the deployed kit's own probe (tools\scout-fetch.sh --check, through Git
# Bash) and prints the result as an inventory line: the browser's path and
# version, or 'browser (NOT FOUND - the Scout's rendered reads report the
# gap)'. Never fatal: without a browser everything else lands and the run
# ends with exit code 0, and the Scout says so when a page needs rendering
# instead of guessing. A browser off the standard install paths is named as
# env.ENSEMBLE_BROWSER in the home's own settings.json
# (settings.optout.example.md).
#
# DOCUMENTED DIVERGENCE FROM deploy-to-host.sh - WHERE the no-Python warning is
# printed. The two scripts word that block identically, line for line. The
# stream differs. This script prints it with Write-Host, so it goes to the
# console through the host/information stream and never to stderr; the bash
# script writes every line of its copy to stderr. Measured by running the block
# on each side and capturing both streams: on each side everything lands on one
# stream and nothing at all on the other. What follows from it, on each side:
# '.\deploy-to-host.ps1 -Update > log.txt' inside a PowerShell session captures
# none of this block, because Write-Host does not write the success stream, and
# no stderr redirection can silence it either; './deploy-to-host.sh --update
# 2>/dev/null' silences the whole warning. Deliberate, not an oversight.
# PowerShell 5.1 has no coloured write to stderr, and Write-Error under
# $ErrorActionPreference = 'Stop' would throw and abort the deploy partway
# through, which is a worse outcome than a warning the ordinary redirections
# miss. The red block on the console is the point: a host with no Python 3 must
# not miss the one line telling it settings.json was left alone.
#
# Then it hash-verifies every file in the verified set (byte-identical against
# source, the agent cards against their guard-processed content; the six
# always-on copies excepted), asserts the deployed settings.json path by path
# against what the factory declares, and prints the inventory.
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
foreach ($d in 'rules', 'agents', 'skills', 'hooks', 'tools', 'launch') {
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
Copy-Item (Join-Path $src 'tools\*.sh') (Join-Path $target 'tools')
Copy-Item (Join-Path $src 'launch\*.ps1') (Join-Path $target 'launch')

Copy-Item (Join-Path $src '.mcp.json') $target
# HARNESS.md: the Claude Code version this COS was last weighed against (line 1)
# and the fixes its guards rely on. Read by hooks\session-start-harness-marker.sh
# at session start; never loaded into context.
Copy-Item (Join-Path $src 'HARNESS.md') $target

# --- settings.json: the preserving merge ------------------------------------
# The home's own settings.json is where host values live: the user edits it
# directly, and the launcher's --setting-sources user makes it the only settings
# file a session reads. Two files beside it in the home serve the merge, and
# Claude Code reads neither. settings.optout.json is the user's list of factory
# items to keep out and single values to keep as their own (tracked example
# settings.optout.example.json, guidance in settings.optout.example.md).
# factory-settings.last-deploy.json is the snapshot of the factory settings a
# deploy applied; the next deploy reads it to tell which list items the factory
# has retired since.
#
# A settings.local.json beside this script is the retired companion an earlier
# design read host values from. When one is found, merge-settings.py moves its
# values into the home's settings.json once and renames it to
# settings.local.json.retired-<timestamp>. Nothing of it is deleted.
#
# merge-settings.py is the single merge implementation both deploy scripts call
# (see its header for the model). It LEAVES EVERY HOST KEY THE FACTORY DOES NOT
# SET ALONE: a plugin toggle, a notification preference, a model entry the
# harness wrote, a deny rule added by hand all survive an update. Before it
# writes it prints one line per list item added, removed as retired, or skipped
# by opt-out, and names every host value it replaces. One implementation, so the
# two scripts cannot disagree about a security-relevant file.
#
# This block sits LAST, after every copy and after the .mcp.json write, so a
# failure here cannot leave a half-deployed home with everything else stale. The
# same reason the bash script has always had it here; the two orders now match.
#
# PYTHON 3 IS PROBED BY RUNNING IT, never by asking whether the command
# resolves. On Windows a Store alias at WindowsApps\python3.exe exists on
# machines with no Python at all and opens the Store instead of failing, so
# Get-Command / command -v answers yes on a host that cannot run a script.
# Running --version and reading the answer is the only honest probe.
#
# NO PYTHON 3. Python 3 is a stated prerequisite of this deploy, and the
# mechanism does not engineer around its absence with a second merge
# implementation. One merge in one language is what keeps parity risk out of a
# security-relevant path. Two branches, both scripts alike:
#
#   * A host settings.json EXISTS. It is not written. Not merged, not copied,
#     not touched. The script prints an unmissable block saying settings were
#     not updated and Python 3 must be installed, and prints it again at the end
#     of the run. It re-fires on every deploy while the condition holds, so the
#     condition is raised by the machine rather than left to anyone's memory.
#     Nothing is ever lost this way; the home simply keeps the settings it had.
#   * NO host settings.json (a first deploy). Source is written wholesale and
#     the script says plainly that nothing was merged and Python 3 is needed.
#     There is nothing to protect, and a home with no settings file is useless.
#     That copy is hash-verified against source like any other copied file.
$mergeScript = Join-Path $src 'merge-settings.py'
$settingsManifest = Join-Path $src 'settings-shipped.txt'
$legacyCompanion = Join-Path $src 'settings.local.json'
$targetSettings = Join-Path $target 'settings.json'
$optout = Join-Path $target 'settings.optout.json'
$snapshot = Join-Path $target 'factory-settings.last-deploy.json'
$hadLegacyCompanion = Test-Path $legacyCompanion

function Find-Python3 {
    foreach ($exe in @('python3', 'python')) {
        try {
            $out = (& $exe --version 2>&1 | Out-String)
        } catch {
            continue   # not on PATH at all, or the Store alias refused to run
        }
        if (($LASTEXITCODE -eq 0) -and ($out -match 'Python 3')) { return $exe }
    }
    return $null
}
$srcSettings = Join-Path $src 'settings.json'
$python = Find-Python3
$settingsMerged = $false
$settingsCopied = $false
$settingsSkipped = $false

# The block the no-Python branches print. Defined once so the end-of-run repeat
# is the same text, word for word, rather than a second wording of it.
function Write-NoPythonBlock($lines) {
    Write-Host ""
    Write-Host "***************************************************************" -ForegroundColor Red
    foreach ($l in $lines) { Write-Host $l -ForegroundColor Red }
    Write-Host "***************************************************************" -ForegroundColor Red
    Write-Host ""
}
$noPythonSkipped = @(
    "SETTINGS NOT UPDATED - PYTHON 3 IS MISSING",
    "",
    "No working Python 3 was found (tried running 'python3 --version' and",
    "'python --version'). Python 3 is a prerequisite of this deploy.",
    "",
    "settings.json was LEFT EXACTLY AS IT WAS:",
    "  $targetSettings",
    "Nothing of yours was lost - and nothing new landed there either. This home",
    "keeps running the settings it already had, including any older factory",
    "rules, until Python 3 is installed.",
    "",
    "Install Python 3, then run this script again."
)
$noPythonFirstDeploy = @(
    "PYTHON 3 IS MISSING - settings.json written as a WHOLESALE COPY of source",
    "",
    "No working Python 3 was found (tried running 'python3 --version' and",
    "'python --version'). Python 3 is a prerequisite of this deploy.",
    "",
    "This is a first deploy: there was no settings.json in the target home, so",
    "there was nothing to protect and source was copied there wholesale.",
    "Nothing was merged. A settings.local.json beside this script, if there is",
    "one, was NOT moved into the deployed file.",
    "",
    "Install Python 3, then run this script again."
)

if ($null -eq $python) {
    if (Test-Path $targetSettings) {
        $settingsSkipped = $true
        Write-NoPythonBlock $noPythonSkipped
    } else {
        Copy-Item $srcSettings $targetSettings -Force
        $settingsCopied = $true
        Write-NoPythonBlock $noPythonFirstDeploy
    }
} else {
    $mergeArgs = @('merge',
                   '--source', $srcSettings,
                   '--target', $targetSettings,
                   '--manifest', $settingsManifest,
                   '--optout', $optout,
                   '--snapshot', $snapshot)
    if ($hadLegacyCompanion) { $mergeArgs += @('--legacy-companion', $legacyCompanion) }
    & $python $mergeScript @mergeArgs
    if ($LASTEXITCODE -eq 3) {
        Write-Host "settings.json WRITTEN BUT NOT VERIFIED (merge-settings.py exited 3, a verification failure). The file was written and then failed its own path-by-path check; it is not trustworthy. See the lines above for which paths. The snapshot was not replaced, and a settings.local.json beside this script was not retired. The deploy stops here: every other file was copied before this step, but none was hash-verified and no inventory is printed. A clean run verifies them all." -ForegroundColor Red
        exit 1
    } elseif ($LASTEXITCODE -eq 5) {
        Write-Host "settings.json NOT UPDATED: $optout could not be read, so the merge stopped before writing anything. The home's settings.json is exactly as it was. Fix or remove that file and run this script again. The deploy stops here: every other file was copied before this step, but none was hash-verified and no inventory is printed. A clean run verifies them all." -ForegroundColor Red
        exit 1
    } elseif ($LASTEXITCODE -ne 0) {
        Write-Host "settings.json MERGE FAILED (merge-settings.py exited $LASTEXITCODE). The home's settings.json may not carry this deploy's settings; see the lines above. The deploy stops here: every other file was copied before this step, but none was hash-verified and no inventory is printed. A clean run verifies them all." -ForegroundColor Red
        exit 1
    }
    $settingsMerged = $true
}

# Integrity: the 46 files hash-compare against source, byte-identical except the
# five agent cards (against their guard-processed content, which equals the
# source byte-for-byte while the source ships clean, as it now does).
# settings.json is NOT in this set and cannot be: the deployed file legitimately
# carries host keys the factory never declared, so no hash of source, and no
# hash of a merged text, says anything true about it. It is verified instead by
# a post-write assertion below - the file is re-read from disk, parsed, and
# checked path by path.
# (23 core - the 19 that were here before, less settings.json, which the
# assertion now covers, plus the Scout's guard hooks\guard-scout-bash.sh,
# its retrieval kit tools\scout-fetch.sh, the Operator's live-reads guard
# hooks\guard-live-reads.sh, and the harness-version pair HARNESS.md and
# hooks\session-start-harness-marker.sh; + the 8
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
    'hooks\guard-push-gate.sh', 'hooks\guard-scout-bash.sh', 'hooks\guard-live-reads.sh',
    'hooks\session-start-harness-marker.sh',
    'tools\scout-fetch.sh',
    'launch\start-ensemble.ps1', 'launch\wire-mcp.ps1', 'launch\cos.ps1',
    '.mcp.json', 'HARNESS.md',
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

# settings.json's own verification: re-read the deployed file from disk, parse
# it, and assert that every factory value and list item not opted out is in
# place and no retired path remains. This is what the hash check used to be
# for, done in the only way that still means something. The removal of retired
# list items is checked inside the merge run, before the snapshot is replaced;
# here the snapshot already equals source, so there are none left to look for.
if ($settingsMerged) {
    $verifyArgs = @('verify',
                    '--source', $srcSettings,
                    '--target', $targetSettings,
                    '--manifest', $settingsManifest,
                    '--optout', $optout,
                    '--snapshot', $snapshot)
    & $python $mergeScript @verifyArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "SETTINGS VERIFICATION FAILED - the deployed settings.json does not carry what the factory declares (see the lines above)." -ForegroundColor Red
        exit 1
    }
} elseif ($settingsCopied) {
    # The first-deploy no-Python branch is a plain byte copy, so a hash is the
    # right instrument for it - the one the merged file can no longer take. It
    # was outside every check until now: dropped from $same because the merged
    # file cannot be hash-compared, and skipped by the assertion because no
    # merge ran.
    $a = (Get-FileHash $srcSettings -Algorithm SHA256).Hash
    $b = (Get-FileHash $targetSettings -Algorithm SHA256).Hash
    if ($a -ne $b) {
        Write-Host "HASH MISMATCH on: settings.json (wholesale copy of source)" -ForegroundColor Red
        exit 1
    }
    Write-Host "settings.json: wholesale copy of source, hash-verified byte-identical against it (no merge ran, so the path-by-path assertion does not apply)."
} else {
    Write-Host "settings.json: NOT WRITTEN this run - the existing host file was left untouched because Python 3 is missing. Nothing to verify; see the block above."
}

Write-Host ""
Write-Host "All $($same.Count) files hash-verified (the agent cards against their guard-processed content; settings.json is verified separately, by the assertion above). Provenance guards ran clean: $alwaysOnStrippedCount always-on comment line(s) and $fmStrippedCount agent card field(s) stripped - the source ships clean of factory provenance, so the guards act only if it ever creeps back."
# --- The browser probe: a declared host requirement, reported, never fatal ----
# Runs the DEPLOYED kit's own --check once, through Git Bash (the hooks'
# prerequisite): Claude Code's CLAUDE_CODE_GIT_BASH_PATH when set, then Git's
# standard install paths, then the bash.exe beside git.exe on PATH. The WSL
# bash in System32 is never used; it cannot run a Git Bash script against
# Windows paths. The kit prints everything on stdout; this reads its exit code
# (0 found, 3 no browser, 4 found but the headless render failed) and its
# BROWSER and VERSION lines. Any failure here only changes the inventory line.
function Find-GitBash {
    $cands = @()
    if ($env:CLAUDE_CODE_GIT_BASH_PATH) { $cands += $env:CLAUDE_CODE_GIT_BASH_PATH }
    if ($env:ProgramFiles) { $cands += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') }
    if (${env:ProgramFiles(x86)}) { $cands += (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe') }
    if ($env:LOCALAPPDATA) { $cands += (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe') }
    $git = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
        $gd = Split-Path (Split-Path $git.Source)
        $cands += (Join-Path $gd 'bin\bash.exe')
        $cands += (Join-Path (Split-Path $gd) 'bin\bash.exe')
    }
    foreach ($c in $cands) {
        if ($c -and ($c -notmatch '\\System32\\') -and (Test-Path $c -PathType Leaf)) { return $c }
    }
    return $null
}
function Get-BrowserLine {
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $bash = Find-GitBash
        if ($null -eq $bash) { return 'browser (NOT CHECKED - no Git Bash found to run tools\scout-fetch.sh --check)' }
        $kit = (Join-Path $target 'tools\scout-fetch.sh') -replace '\\', '/'
        $out = @(& $bash $kit --check 2>$null)
        $rc = $LASTEXITCODE
        $path = ($out | Where-Object { $_ -like 'BROWSER: *' } | Select-Object -First 1)
        $ver = ($out | Where-Object { $_ -like 'VERSION: *' } | Select-Object -First 1)
        if ($path) { $path = $path.Substring(9) }
        if ($ver) { $ver = $ver.Substring(9) }
        if ($rc -eq 0) { return "browser ($path, $ver)" }
        if ($rc -eq 3) { return "browser (NOT FOUND - the Scout's rendered reads report the gap)" }
        if ($rc -eq 4) { return "browser (FOUND at $path, $ver, but its headless render returned nothing - the Scout's rendered reads report the gap)" }
        return "browser (NOT CHECKED - the probe exited $rc)"
    } catch {
        return "browser (NOT CHECKED - the probe could not run: $($_.Exception.Message))"
    } finally {
        $ErrorActionPreference = $eap
        # The probe's exit code (3 for no browser) must not become the deploy's:
        # this script ends without an explicit exit, so the last native exit code
        # is what a caller such as the cos dispatcher reads.
        $global:LASTEXITCODE = 0
    }
}
$browserLine = Get-BrowserLine

Write-Host ""
Write-Host "Deployed inventory (the staged set only):"
# settings.json is annotated with what actually happened to it, as the .sh does:
# an unannotated line in a list of copied files would read as another copy.
if ($settingsMerged) {
    $settingsLine = if ($hadLegacyCompanion) {
        'settings.json (factory settings merged into the host''s own, the legacy settings.local.json moved into it; see the lines above)'
    } else {
        'settings.json (factory settings merged into the host''s own)'
    }
} elseif ($settingsCopied) {
    $settingsLine = 'settings.json (WHOLESALE COPY of source - no Python 3, first deploy, nothing merged)'
} else {
    $settingsLine = 'settings.json (NOT WRITTEN - no Python 3; the host file is untouched and unchanged)'
}
$staged = @('CLAUDE.md', 'HARNESS.md', $settingsLine, '.mcp.json', $browserLine)
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
$staged += Get-ChildItem (Join-Path $src 'tools') -Filter *.sh | ForEach-Object { "tools\" + $_.Name }
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

# The no-Python block again, last, so the run cannot end without it having been
# the final thing on screen. It re-fires on every deploy while Python 3 is
# missing; the condition is raised by the script, never left to memory.
if ($settingsSkipped) { Write-NoPythonBlock $noPythonSkipped }
if ($settingsCopied)  { Write-NoPythonBlock $noPythonFirstDeploy }
