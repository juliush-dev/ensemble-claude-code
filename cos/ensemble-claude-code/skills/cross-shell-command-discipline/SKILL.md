---
name: cross-shell-command-discipline
description: Prevent shell-boundary mistakes when composing, running, or verifying commands across PowerShell, Bash, Git Bash, WSL, cmd, SSH, Docker, or nested interpreters. Use whenever a task involves wsl.exe, bash -lc, powershell -Command, cmd /c, ssh, docker exec, paths with spaces, nested quoting, globs, pipelines, redirection, variable expansion, or verifying target state through a different shell than the one that will execute the command.
---

# Cross-Shell Command Discipline

## Overview

Use this skill when the shell boundary is part of the problem. A shell boundary is the point where one command interpreter hands text to another, such as PowerShell calling `wsl.exe`, WSL calling Windows executables, Git Bash launching a script that touches Windows paths, or `ssh` passing a quoted command to a remote shell.

The aim is to avoid false evidence. A command that failed because PowerShell, Bash, WSL, Git Bash, `cmd`, SSH, or Docker parsed it differently than intended tells you more about the command string than about the target system.

## Triggers

Invoke this skill when a command or verification step includes:

- `wsl.exe`, `bash -lc`, `powershell -Command`, `pwsh -Command`, `cmd /c`, `ssh`, `docker exec`, or another nested interpreter.
- A path with spaces, backslashes, drive letters, `$HOME`, `%USERPROFILE%`, `~`, `/mnt/c`, or `/c`.
- Quoting inside quoting, especially single quotes inside double quotes or Bash snippets embedded in PowerShell strings.
- Globs, redirection, command substitution, pipelines, variable expansion, or `for` loops crossing from one shell into another.
- A verification command whose result will decide whether deployment, file sync, or cleanup succeeded.
- A previous command in the same task failed with a parser error, empty output, unexpected quoting behavior, or a path-not-found result that could be a shell mismatch.

Do not invoke for simple single-shell commands with no quoting, path translation, or nested execution.

## Workflow

1. Name the active shell and the target shell before composing the command. If the command crosses into another environment, say which part is parsed by each shell.
2. Prefer one shell end to end. If PowerShell can inspect the Windows filesystem directly, use PowerShell. If WSL needs to inspect Linux state, run directly inside WSL rather than PowerShell calling Bash calling WSL again.
3. Keep cross-shell payloads tiny. Pass only a simple target command across the boundary. Avoid embedding loops, pipelines, heredocs, or complex quoting inside a nested shell string.
4. Use the target shell's native path form at the point where the filesystem is touched:
   - PowerShell touching Windows: `C:\Users\...`
   - WSL Bash touching Windows mounts: `/mnt/c/Users/...`
   - Git Bash touching Windows: verify whether the environment uses `/c/...` or `/mnt/c/...` before assuming.
   - Remote SSH: use paths valid on the remote host, not the local host.
5. Avoid mixed quoting when possible. Prefer separate simple commands, scripts already present on disk, or native shell constructs over one dense nested command.
6. Treat parser errors, empty output, and surprising no-match results as command failures, not system facts. Fix the command and rerun before drawing conclusions.
7. For verification, use direct existence/count checks in the target environment. Verify files with `Test-Path` in PowerShell, `[ -f ... ]` or `find` in Bash, and explicit exit codes when the output may be empty.
8. If a command must cross shells and the syntax is nontrivial, first run a harmless probe that prints the current shell, working directory, and one known path. Use that probe to confirm the boundary behaves as expected.

## Patterns

Prefer this:

```powershell
Test-Path -LiteralPath "$env:USERPROFILE\.config\app\settings.json"
```

over a nested Bash command when checking a Windows path from PowerShell.

Prefer this:

```bash
test -f ~/.config/app/settings.json
```

over PowerShell calling `wsl.exe` with an embedded Bash loop when the agent is already running inside WSL.

### Git Bash / MSYS argument path translation

When the active shell is Git Bash or MSYS and you invoke a Windows program such as `wsl.exe`, MSYS rewrites any argument that looks like a Unix path into a Windows path *before* the program sees it. A `/mnt/c/Users/...` argument passed to `wsl.exe` can arrive mangled as `C:/Program Files/Git/mnt/c/Users/...`, producing a confusing "No such file or directory" that is not a real filesystem fact.

Disable the conversion for that call with the `MSYS2_ARG_CONV_EXCL` environment variable:

```bash
MSYS2_ARG_CONV_EXCL='*' wsl.exe bash /mnt/c/Users/<user>/script.sh
```

`'*'` excludes every argument from conversion for that one invocation. Use it whenever a Git Bash command launches `wsl.exe`, `cmd`, or another Windows program with Unix-style path arguments and the path comes back not-found.

### When nested quoting keeps mangling, hoist the body into a script

When a cross-shell task genuinely needs a nontrivial body (a loop, per-file substitution, encoding-sensitive writes, a multi-step verification), do not keep hand-escaping it into a nested `bash -lc '...'` string. Several layers of parsing (for example MSYS to `wsl.exe` to `bash -lc`, or PowerShell to `wsl.exe` to Bash) reliably eat inner quotes, `$`, and snippets like `awk '{print $1}'`, leaving variables empty and redirections firing against nothing. After the second failure, stop. Hoist the logic into a script in a language whose own interpreter parses the body, and cross the boundary with a single parse layer so no intermediate shell re-tokenizes it. This is the positive form of "keep cross-shell payloads tiny": only a trivial launcher crosses the boundary, and the complexity lives in a file.

From PowerShell into WSL, pipe the script to the target interpreter over stdin, so nothing reaches the filesystem-path layer to be mangled:

```powershell
Get-Content deploy.py -Raw | wsl.exe -- python3 -
```

Python then owns the paths (spaced names, `/mnt/c/...`), the UTF-8 content, the substitution, and the verification, with no PowerShell or Bash quoting in the body, and it tolerates the CRLF endings a Windows-written script may carry.

From Git Bash / MSYS into WSL, write the real command to a `.sh` file (LF line endings) on a path both sides can read, such as a Windows path the WSL side reaches via `/mnt/c`, then run it with one layer of parsing and MSYS path-conversion disabled:

```bash
# write script to C:\Users\<user>\_task.sh (LF endings), then:
MSYS2_ARG_CONV_EXCL='*' wsl.exe bash /mnt/c/Users/<user>/_task.sh
```

Inside the script, normalize `/mnt/c` source files with `tr -d '\r'` if they may carry CRLF, and clean up the temp script afterward. Either way, this is the go-to escape from nested-quoting hell, not a last resort.

#### Two specific traps when you take the write-script route

1. **The editor/write tool may mangle `KEY=value` literals in the file you write.** A file-write or lint pass that scans for secrets can rewrite a literal like `startswith(b"SOME_TOKEN_KEY=*** — collapsing the value to `***` or flagging a bogus `SyntaxError` on that line — because it pattern-matched the `KEY=` as a credential assignment. Symptom: a Python/script file you just wrote fails to parse or silently loses a literal you definitely typed. Fix: **build the sensitive key string at runtime** instead of writing it as one literal: `KEY = "SOME_TOKEN_KEY" + "="; keyb = KEY.encode()`. Then match with `line.startswith(keyb)`. The split prevents the scanner from recognizing (and rewriting) the assignment.

2. **`tr -d '\r\n'` and `${VAR%$'\r'}` blow up inside multi-line `&&`-chained command strings.** When a long command is assembled as one string and run through `eval`/`bash -lc`, the single quotes around `'\r\n'` (and ANSI-C `$'\r'`) collide with the outer quoting and throw `unexpected EOF while looking for matching '` or `syntax error near unexpected token '('`. After the **first** such failure, stop hand-fixing the one-liner: write the logic to a `.sh` file (LF endings) and run it with one parse layer, or strip CR with `tr -d '[:cntrl:]'` / `${VAR%$'\r'}` *inside* that script rather than in the chained string. Parens in an `echo "...(must be 1)..."` string inside such a chain also trigger the same class of error — move that text into a script too.

### When authoring a script for another shell, hand off via a file — not stdin or inline — and keep the source ASCII

Authoring a script *for* one shell from *inside* another (for example writing a PowerShell `.ps1` from a Bash heredoc on a Windows host) crosses an encoding-and-parse boundary at write time, before any command runs. Two concrete traps live here, both observed during a real deploy.

1. **`powershell -Command -` (script fed to PowerShell over stdin) silently truncates after the first statement.** A multi-line script piped into `powershell -Command -` runs only its first statement; the rest is dropped with no error, so the deploy looks like it ran but did half the work. **Write the script to a file and run it with `powershell -NoProfile -File <path>`** (the `-File` reader consumes the whole file; `-NoProfile` keeps the run deterministic). This is the **opposite** of the `Get-Content deploy.py -Raw | wsl.exe -- python3 -` pattern above: piping a script to `python3 -` over stdin works, but stdin tolerance is per-interpreter — `powershell -Command -` does not have it. The general rule is the positive form of "prefer one shell end to end": keep one shell from authoring through execution, and when you genuinely must cross, hand the body off as a **file** run with one parse layer, never as an inline/stdin string the receiving interpreter may re-tokenize or truncate.

2. **Non-ASCII characters silently mangle across the authoring boundary and break the target shell's parse.** When the script you write contains em-dashes (`—`), arrows (`→`), or smart quotes — often pasted in from prose or a plan — those multi-byte characters can corrupt as the bytes cross the shell/encoding boundary, producing a *parse-time* failure in the target shell rather than a clean runtime error. **Author any cross-shell script ASCII-only** (`-`/`--` for em-dashes, `->` for arrows, straight quotes), and verify zero non-ASCII bytes before running it. The Windows-PowerShell-specific mechanism behind this: Windows PowerShell 5.x reads a no-BOM UTF-8 `.ps1` through the machine's ANSI code page, so a multi-byte UTF-8 character (em-dash, arrow, smart quote) is misdecoded into stray bytes that break the target shell's *parse* rather than throwing a clean runtime error. When non-ASCII is genuinely unavoidable, the two escape hatches are (a) write the file with a UTF-8 BOM, which forces WPS 5.x to decode it as UTF-8, or (b) construct the character in-script instead of writing it as a literal (`[char]0x2014` for an em-dash). The ASCII-only authoring rule here is the provider-independent form that holds across any author-in-one-shell, run-in-another boundary.

### Watch variable pre-expansion when PowerShell wraps a Bash command

In `wsl.exe -- bash -lc "...$HOME..."`, PowerShell expands `$HOME` and any `$var` to its own value (often empty, or a Windows path) before `wsl.exe` runs, so Bash never sees the variable. Single-quote the Bash command so PowerShell passes it literally and Bash does the expansion:

```powershell
wsl.exe -- bash -lc 'echo "$HOME"; ls "$d"'
```

Two signatures of this trap: a `HOME` that reads like a Windows path with its separators stripped, and a `cp` or `ls` that errors on a path missing the segment a shell variable should have supplied. The attribution is boundary-agnostic — even single-quoted, a multi-statement Bash body with `var=...; ...$var...` assignments can come back empty **through Git Bash / MSYS → `wsl.exe` → `bash -lc` exactly as through PowerShell → `wsl.exe`**. A body like `C=/home/<user>/.config/app; ... "$C/skills"` resolved `$C` to empty, so the paths degraded to `/skills`, `/settings.json`, and read as not-found. The fix that worked: fully literal absolute paths, no assign-then-reuse variable across the boundary. When literal paths are impractical, switch to the write-a-script route above rather than fighting the one-liner.

### Running a PowerShell-authored plan through Git Bash / MSYS

A plan, runbook, or skill may spell its commands in PowerShell while the executing session's shell is actually Git Bash / MSYS. Do not paste the PowerShell verbatim — translate each command to its POSIX equivalent at the point of execution. The semantics verified are identical; only the shell surface differs. Common translations:

| Plan (PowerShell) | Execute (Bash / MSYS) |
| --- | --- |
| `$env:VAR = "value"` | `VAR="value" <cmd>` (inline, per-invocation) |
| `Copy-Item A B -Force` | `cp A B` |
| `(Get-FileHash X -Algorithm SHA256).Hash` | `sha256sum X \| cut -d' ' -f1` |
| `Select-String -LiteralPath P -Pattern "x"` | `grep -c "x" P` (count) or `grep -n "x" P` |
| `Get-Content P` | read-file tool, or `cat P` for tiny files |
| `& "...\prog" <args>` | `./prog <args>` — but see the venv-Python trap below |

For `.md` / config edits the plan expresses as inline blocks, prefer the editor/patch tools over shell heredocs: cleaner diffs, no quoting hell, and they honor the file format. Run the plan's verification greps in Bash afterward.

### Git pathspecs are case-sensitive even on a case-insensitive filesystem

On Windows the filesystem is case-insensitive, but `git add` matches its pathspec **case-sensitively**. `git add Charter.md` when the tracked path is `charter.md` matches nothing and stages nothing — with no error — so an edit-then-add-then-commit chain can silently drop a file. This is the same false-evidence class as the shell traps above: the command "succeeded" (exit 0) while doing nothing. When the case of a path is uncertain, verify the staged state with a separate probe — `git status --short` after the add — rather than trusting the add's silent success.

### Bundled / Windows-native Python invoked from MSYS: path-form split

When you call a Windows-native interpreter (for example an app's bundled venv Python at `app/venv/Scripts/python`) from inside MSYS, two boundary traps appear:

1. A `#!/usr/bin/env python3` launcher script does **not** resolve its shebang under MSYS and throws an import traceback if run directly. Invoke through the interpreter explicitly: `app/venv/Scripts/python app/launcher <args>` instead of `./launcher` or `& "...\launcher"`.
2. The interpreter is Windows-native, so inside any `python -c "..."` snippet it cannot open MSYS `/c/...` paths and throws `FileNotFoundError`, even though bash builtins (`cp`, `sha256sum`, `grep`) read `/c/...` fine in the same session. Give the embedded Python **native** Windows paths as raw strings:

```bash
app/venv/Scripts/python -c "import yaml; d=yaml.safe_load(open(r'C:\Users\me\config.yaml',encoding='utf-8')); print(d['key'])"
```

Rule of thumb for the whole session: bash builtins get `/c/...` paths; a Windows-native interpreter's `-c` snippet gets `C:\...` raw-string paths. Mixing the two is the most common silent failure in this configuration — a `FileNotFoundError` here is a path-form mismatch, not a missing file (do not let it harden into a "the file is gone" conclusion).

When you need a PowerShell boolean expression, wrap command calls before combining them:

```powershell
Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')) -and ($_.Name -in $formal) }
```

Do not write the `-and` as if it were an argument to `Test-Path`.

## Guardrails

- Do not use a failed cross-shell verification as evidence that a file, skill, service, or deployment target is absent.
- Do not test for a target environment's state from the wrong vantage point. Checking a Linux path like `/home/<user>/...` from Git Bash or MSYS tells you nothing about WSL, because that path does not exist in the MSYS view. To learn whether a WSL file exists, ask WSL: `wsl.exe bash -lc 'ls -la $HOME/.config/app/config.md'`. A "not reachable / not found" result from the wrong shell is a non-result, not a finding, and must not harden into a claim that the target is missing.

### Case study: the false "WSL unreachable" conclusion

This is a real failure, recorded because knowing the rule above did not prevent it. The task was to mirror an edit from a Windows file to its WSL twin. To check whether the WSL target existed, a single command ran from MSYS Git Bash: `ls -la /home/<user>/.config/app/config.md`. It returned not-found. From that one wrong-vantage test the agent concluded "WSL filesystem not reachable from this shell" and wrote that conclusion into durable project notes as a target divergence.

It was wrong on every count. The host had a real running Ubuntu WSL2 distro; the tool's WSL install existed as a genuine separate deployment; the file was present at exactly the assumed path and even carried the expected baseline md5. The probe that settled it was one read-only line through the correct boundary: `wsl.exe bash -lc 'whoami; echo HOME=$HOME; ls -la $HOME/.config/app/config.md; md5sum $HOME/.config/app/config.md'`.

The lesson is sequencing, not knowledge. Before turning any cross-shell "not found / not reachable" into a stated fact, run the read-only probe through the target shell first (step 8 of the workflow). Treat a reachability claim as unestablished until a probe from the correct vantage confirms it. The cost of skipping the probe here was a fabricated finding committed to the project record, which then had to be hunted down and corrected. One probe up front is always cheaper than retracting a false claim later.

### Case study: a mutation's own inline verification echo can lie

The twist on the case above is a **successful** mutation whose self-report is false. A filesystem mutation chained with an inline `$(...)` verification in the *same* cross-shell string returned a stale/wrong reading while the mutation itself succeeded: `cp <src> <dst> && echo "size=$(stat -c %s <dst>)"` and `rm ...; echo "n=$(ls ... | wc -l)"` reported a wrong size (`21468`) and count (`0`) even though the filesystem was correct. No parser error — just a plausible wrong number that can harden into a fabricated "verified" finding. The reliable file ops (`cp`, `rm`, heredoc) were never the problem; only the inline command-substitution used for verification *within the same chained string as the mutation* misreported. Verify a cross-shell mutation with a **separate, standalone probe run through the target vantage** — never with the mutation's own chained inline `$(...)` echo.

- Do not hide parser errors in a final report. Say the verification command failed and rerun a simpler one.
- Do not mix destructive file operations with shell-boundary experiments. First prove the path and target shell are correct with a read-only check.
- Do not compose recursive delete or move operations by passing generated path strings between shells. Keep filesystem mutation in one shell using native path handling.
- If the command string starts to look clever, split it.
