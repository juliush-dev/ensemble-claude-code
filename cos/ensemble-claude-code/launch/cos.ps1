# Ensemble (ensemble-claude-code) - the `cos` dispatcher: short subcommands that
# replace the long, fully-typed COS usage and management invocations. Windows
# PowerShell 5.1 compatible.
# ASCII-ONLY FILE, deliberately (PS 5.1 reads BOM-less files as ANSI; keep pure ASCII).
# PS 5.1 note: no '&&', no ternary, no null-coalescing anywhere in this file.
#
# DELEGATION-ONLY: every subcommand is a thin `& <script> @args`
# call to a canonical script. This dispatcher re-implements NO flag, argument, or
# invocation logic of its targets - it never spells out `claude --setting-sources
# user`, never re-does a deploy step. If a target script moves or changes its
# parameters, this dispatcher keeps working or fails loudly, because it carries no
# duplicated knowledge of what the targets do.
#
# WHAT DELEGATES WHERE:
#   cos launch    -> DEPLOYED  launch\start-ensemble.ps1   (post-deploy session start)
#   cos wire-mcp  -> DEPLOYED  launch\wire-mcp.ps1         (post-deploy MCP wiring)
#   cos update    -> REPO      deploy-to-host.ps1 -Update  (source-side; the deploy
#                                                           script never deploys itself)
#   cos probe     -> REPO      probe-context.ps1           (source-side; never deploys)
#   cos help      -> this dispatcher (no delegation)
# Deployed-side targets live under %LOCALAPPDATA%\ensemble-claude-code and need no
# anchor. Repo-side targets (update, probe) are located via the $env:OSCC_WORKBENCH
# anchor - the workbench repo root - which the user sets in the gitignored host-local
# companion. No host path is ever tracked in source (publishable-clean).
#
# `cos release` is deliberately ABSENT: the release-hop keeps its
# own gating; no shortcut around it lives here, not even as a stub.
#
# INSTALL (one-time; the user's own hand, under its own permission gate): add this
# one line to your PowerShell profile ($PROFILE), which dot-sources the DEPLOYED
# copy so `cos` is defined in every new shell:
#   . "$env:LOCALAPPDATA\ensemble-claude-code\launch\cos.ps1"
# This file is safe to dot-source repeatedly - it only (re)defines the function.

function cos {
    $sub = $null
    $rest = @()
    if ($args.Count -ge 1) {
        $sub = [string]$args[0]
        if ($args.Count -ge 2) {
            $rest = @($args[1..($args.Count - 1)])
        }
    }

    function Resolve-CosRepoScript {
        param([string]$Leaf)
        $anchor = $env:OSCC_WORKBENCH
        if ([string]::IsNullOrWhiteSpace($anchor)) {
            Write-Host ("cos: `$env:OSCC_WORKBENCH is not set. Point it at your oscc-workbench repo root " +
                "(set it in the gitignored host-local companion), then reopen the shell. " +
                "Repo-side commands (update, probe) cannot be located without it.") -ForegroundColor Red
            return $null
        }
        $path = Join-Path $anchor (Join-Path 'cos\ensemble-claude-code' $Leaf)
        if (-not (Test-Path $path)) {
            Write-Host ("cos: repo script not found at {0} - is `$env:OSCC_WORKBENCH pointing at the workbench repo root?" -f $path) -ForegroundColor Red
            return $null
        }
        return $path
    }

    function Resolve-CosDeployedScript {
        param([string]$Leaf)
        $deployedHome = Join-Path $env:LOCALAPPDATA 'ensemble-claude-code'
        $path = Join-Path $deployedHome (Join-Path 'launch' $Leaf)
        if (-not (Test-Path $path)) {
            Write-Host ("cos: deployed script not found at {0} - run 'cos update' (or deploy-to-host.ps1) first." -f $path) -ForegroundColor Red
            return $null
        }
        return $path
    }

    switch ($sub) {
        'launch' {
            $s = Resolve-CosDeployedScript 'start-ensemble.ps1'
            if ($s) { & $s @rest }
        }
        'wire-mcp' {
            $s = Resolve-CosDeployedScript 'wire-mcp.ps1'
            if ($s) { & $s @rest }
        }
        'update' {
            $s = Resolve-CosRepoScript 'deploy-to-host.ps1'
            if ($s) { & $s -Update @rest }
        }
        'probe' {
            $s = Resolve-CosRepoScript 'probe-context.ps1'
            if ($s) { & $s @rest }
        }
        default {
            if ($sub -and $sub -ne 'help') {
                Write-Host ("cos: unknown subcommand '{0}'." -f $sub)
                Write-Host ""
            }
            $deployedHome = Join-Path $env:LOCALAPPDATA 'ensemble-claude-code'
            Write-Host "cos - Ensemble COS dispatcher (delegation-only wrappers)"
            Write-Host ""
            Write-Host "  cos launch [args]     start a session in the deployed home"
            Write-Host "                          -> DEPLOYED  launch\start-ensemble.ps1"
            Write-Host "  cos update [args]     refresh the deployed home from the repo (-Update)"
            Write-Host "                          -> REPO      deploy-to-host.ps1   (needs `$env:OSCC_WORKBENCH)"
            Write-Host "  cos probe  [args]     read the startup-context anchor headlessly"
            Write-Host "                          -> REPO      probe-context.ps1    (needs `$env:OSCC_WORKBENCH)"
            Write-Host "  cos wire-mcp [args]   wire curated MCP servers into the deployed home"
            Write-Host "                          -> DEPLOYED  launch\wire-mcp.ps1"
            Write-Host "  cos help              this list"
            Write-Host ""
            Write-Host ("Deployed home : {0}" -f $deployedHome)
            if ([string]::IsNullOrWhiteSpace($env:OSCC_WORKBENCH)) {
                Write-Host "Repo anchor   : `$env:OSCC_WORKBENCH is UNSET (update, probe will fail until you set it)."
            } else {
                Write-Host ("Repo anchor   : {0}" -f $env:OSCC_WORKBENCH)
            }
        }
    }
}
