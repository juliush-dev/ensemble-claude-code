# The Ensemble

The Ensemble is not a programming tool. It is an idea of what a customized operating shape (COS) can look like in the era of agents — a way of reorganizing an AI assistant into a team of specialized roles that share one externalized worldview about deliberate life with agents, where anything done on purpose toward something better counts as work, employment or not.

A COS is a framework for the happening of artificial intelligence, co-authored equally by the human and the AI agents — not a curriculum. It does not teach the agents how to think or work like experts; instructions that do not let them exercise the depth and breadth of their intelligence as the task needs harm the execution of the task. What a COS aims at is making that happening productive and reliable at agentic scale — consistency of product and behavior, traceability, auditability, learning, testing, understanding, and more that the building of it keeps showing — with the benefit accruing to the whole system, human and agents together. Beyond those it is meant to raise happiness, confidence, peace of mind, stability, and growth: it is for the betterness and betterment of life. The measure runs on the joint life the human and the agents share — a good COS decreases that life's entropy and increases its order, balance, and clarity; a bad one chokes the intelligence's potential or leaves its happening unproductive and unreliable. Intelligence alone does not produce navigable order.

Out of the box, [Claude Code](https://docs.claude.com/en/docs/claude-code) is a single general-purpose session. The Ensemble reshapes that home into a team of six specialized roles working under the human's direction. The human still talks to one session; behind it are five subagents with distinct jobs, distinct permissions, and the same worldview, governing how work is cut, remembered, and verified.

This repository is the Ensemble's first concrete realization, built on Claude Code as the harness. It deploys into an isolated Claude Code home of its own, without disturbing an existing setup.

---

## The team

The six roles:

- **Concertmaster** — the main session the human talks to. It classifies each request, dispatches the right specialist, consolidates what comes back, and closes the loop. To the human it speaks plain language; the team's trade vocabulary it keeps for its dispatches.
- **Scout** — research and fresh grounding against authoritative sources, plus deep retrieval from the team's own memory. Read-only.
- **Builder** — authoring and editing the body of a project, whatever that body is: documents, plans, configuration, code when the project is code.
- **Examiner** — independent verification and review: drift audits, consistency readings, recommendations. Reads and runs checks; never edits.
- **Archivist** — stewardship of the team's notebooks: designations, handoffs, registries, canonization, ports.
- **Operator** — acts on live external systems (messaging, cloud, browser), confirm-first. It has no live tools until they are deliberately wired in.

The Concertmaster is the main session itself and has no agent file. The other five are subagents Claude Code launches on dispatch.

---

## The worldview they share

What ties the roles together is a shared worldview: every role holds the same small set of principles about work. They live in the always-on rules, summarized here; the rules themselves are the source of truth.

**A shared model of work.** Work is cut into a closed set of unit kinds — *project, pursuit, tending, route, iteration* — and nobody invents private ones. A **pursuit** closes a gap and is discharged when its acceptance is met; a **tending** holds a valued condition and ends only by decision, never by achievement. Each unit is *designated* (declared as one named thing) and carries its own **notebook** — a living current-state surface, kept true, pruned of what stopped being true.

**Capture.** Work constantly throws off feedback worth keeping. A single test decides: would it guide future work if recorded, and be lost if not? If so, it is written down at once, into a definite home chosen from a fixed menu — a handoff, a gap list, an aim surface, a constitution's bounds. Anything worth keeping is recorded rather than left in the context window, where it would eventually be lost.

**Retrieval.** A record only helps if it is read back, so the shape reads before it acts: onboarding reads a project's face before touching it; picking up work reads where it last stood; and a set of observable triggers ("on feedback, retrieve before retrying"; "before asserting what a surface should show, re-read it") force a lookup exactly where memory exists to serve it.

**The amnesia doctrine.** Every role treats its own trained knowledge as *capability, never authority.* Language, reasoning, and skill come from the model; but no load-bearing claim the work rests on is ever settled by recall. It is settled only against a retrieved, citable surface — the team's own notebooks, or authoritative external documentation. The rules name this *recall proposes, retrieval disposes*.

**Dispatch discipline.** The main session classifies every request by kind of work and routes it to the role whose envelope fits — and each role carries only the duties its permissions can discharge. Certain acts are hard gates that are never crossed on their own: deploying, pushing, writing to live external systems, broad restructuring. Those wait for the human.

---

## What's in this tree

Everything the shape needs lives under [`cos/ensemble-claude-code/`](cos/ensemble-claude-code/):

| Path | What it is |
| --- | --- |
| `always-on/CLAUDE.md` | The identity plate — loaded into every session. |
| `always-on/rules/` | The five worldview modules: work-object model, capture, retrieval, amnesia doctrine, dispatch discipline. |
| `agents/` | The five subagent cards (Scout, Builder, Examiner, Archivist, Operator). |
| `skills/` | Protocol runbooks and curated craft skills, each invoked at its moment. |
| `hooks/` | Small shell guards (Git Bash) — a session-end litter flag, the Examiner's command guard and the Archivist's path guard, and a push gate. |
| `launch/` | Session launcher and optional MCP wiring — `.ps1` for Windows, `.sh` for Linux/macOS. |
| `deploy-to-host.ps1` · `deploy-to-host.sh` | The deploy script (PowerShell for Windows, bash for Linux/macOS) — copies the staged set into an isolated config home. |
| `settings.json` | Default model, memory settings, hook wiring (including the inline compaction marker), and curated tool-permission rules. |

At the repository root there is also `PROVENANCE.json`. This tree is a mechanically generated, verified projection of a private workbench at a single named commit. It is generated by a deterministic projector, never hand-edited, and regenerable byte-for-byte from the same source. `PROVENANCE.json` records where it came from: the source commit, the publication profile and its content hash, the generator's identity and version, tool versions, and the per-file publish/exclude counts. That record documents what produced each file here.

This README lives at [`docs/README.md`](docs/README.md); GitHub renders it as the front page.

---

## How to run it

The shape is designed to coexist with an existing Claude Code setup, not replace it. It deploys into its own isolated config home, so the normal `claude` command keeps using the existing main COS.

Everything below runs on the adopter's own machine, in a local shell. Two script families ship: a PowerShell trio for Windows and a bash trio for Linux and macOS. Each step below gives both.

### 1. Clone and deploy

Windows (PowerShell):

```powershell
git clone <this-repo-url>
cd <repo>/cos/ensemble-claude-code
powershell -ExecutionPolicy Bypass -File .\deploy-to-host.ps1
```

Linux / macOS (bash):

```bash
git clone <this-repo-url>
cd <repo>/cos/ensemble-claude-code
./deploy-to-host.sh
```

The deploy script copies the staged set into an isolated Claude Code config home — `%LOCALAPPDATA%\ensemble-claude-code` on Windows, `${XDG_CONFIG_HOME:-~/.config}/ensemble-claude-code` on Linux and macOS (override the whole path with `CLAUDE_ENSEMBLE_HOME`). It never touches the default `~/.claude`; the existing setup stays the main COS. Both scripts hash-verify every byte-identical deployed file (the six always-on copies deploy with the provenance line stripped instead) and print the full inventory, so what landed is visible. Neither clobbers an existing home unless run with `-Force`/`--force` (which backs the old one up first) or `-Update`/`--update` (which refreshes the staged files in place, preserving login and session state).

### 2. Launch

Windows (PowerShell):

```powershell
& "$env:LOCALAPPDATA\ensemble-claude-code\launch\start-ensemble.ps1"
```

Linux / macOS (bash):

```bash
"${XDG_CONFIG_HOME:-$HOME/.config}/ensemble-claude-code/launch/start-ensemble.sh"
```

The launcher sets `CLAUDE_CONFIG_DIR` for that launch only, runs `claude --setting-sources user` so only the home's own settings govern the session, and leaves the calling shell's environment untouched. It also defaults the session to fullscreen (alt-screen) TUI rendering, setting `CLAUDE_CODE_NO_FLICKER=1` and `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1` (the latter a documented Windows Terminal repaint fix) only when they are unset — so exporting either as `=0` before launch opts out, and the PowerShell launcher restores their prior values afterward. This is a research-preview harness feature, not a stable CLI flag. Any extra arguments pass straight through to `claude`.

For a short entry point, add a launcher to the shell profile.

Windows (`$PROFILE`) — dot-source the deployed `cos` dispatcher:

```powershell
. "$env:LOCALAPPDATA\ensemble-claude-code\launch\cos.ps1"
```

Then `cos launch` starts a session and `cos help` lists the rest (`update`, `probe`, `wire-mcp`). The deploy already places `cos.ps1` under the home's `launch/`, so nothing extra is installed. Two of its subcommands — `cos update` (refresh the deployed home) and `cos probe` — run scripts from your own clone rather than the deployed home; set the `OSCC_WORKBENCH` environment variable to your clone's root so they can be found. The deployed-side subcommands (`cos launch`, `cos wire-mcp`) need no such anchor.

Linux / macOS (`~/.bashrc` or `~/.zshrc`):

```bash
alias ensemble='"$HOME/.config/ensemble-claude-code/launch/start-ensemble.sh"'
```

Now `claude` starts the main COS; `cos launch` (Windows) and `ensemble` (Linux / macOS) start this one.

### 3. Log in (once)

Authentication is per config home, so on first launch of the Ensemble, run `/login` once inside it. It stays logged in after that.

### 4. Optional: wire the browser MCP server

Windows (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File .\launch\wire-mcp.ps1
```

Linux / macOS (bash):

```bash
./launch/wire-mcp.sh
```

The wire-mcp script registers a pinned Playwright MCP server (browser control) into the new home's user-scope config. It is idempotent and self-verifying. Skip it if the Operator's browser tools are not needed.

### Making it the default (optional, not scripted)

The Ensemble can be made the default by setting `CLAUDE_CONFIG_DIR` permanently, but that is deliberately not scripted. Coexistence is the intended default: the design assumes the adopter keeps their own main setup and starts the Ensemble by name.

---

## Honest caveats

**Two shells ship; the bash trio is WSL-tested, not yet macOS-tested.** The deploy and launch scripts come in two families: a PowerShell trio for Windows (PowerShell 5.1) and a bash trio (`deploy-to-host.sh`, `launch/start-ensemble.sh`, `launch/wire-mcp.sh`) for Linux and macOS. The bash trio is ASCII-only with LF line endings and targets the XDG config home (`${XDG_CONFIG_HOME:-~/.config}/ensemble-claude-code`, overridable with `CLAUDE_ENSEMBLE_HOME`). Its deploy and launch mechanics are smoke-tested on WSL Ubuntu (bash 5.2): first deploy, provenance-line stripping, hash verification, the `--update` and `--force` flags, the deployed hooks landing executable, the launcher's home guard, and the full launch flow against a live `claude` CLI — `wire-mcp.sh` registering the pinned Playwright MCP server into the new home, the one-time login, and all MCP servers connecting in a live session — all behave as intended. One honest residual remains: macOS is untested — it is expected to work on plain bash plus coreutils, and the deploy script already falls back from `sha256sum` to `shasum -a 256` for the macOS default, but no macOS run has confirmed it. The hooks run under Git Bash on Windows and under bash elsewhere. The *shape* itself — rules, agents, skills — is plain Markdown and platform-neutral.

**The pattern ships; the instance stays personal.** The rules speak of a "shared external brain," an Obsidian vault, and per-project notebooks — a real, personal external memory that the shape reads from and writes to. None of the author's own memory surfaces are included here, and none should be. What ships is the pattern: the roles, the worldview, and the rules. To run it, the adopter instantiates their own memory surfaces — their own notebooks, their own external brain. The Ensemble supplies the way of working; the memory it works against must be built by the adopter. The shape also works only inside a project it has wrapped: a folder holding three repositories — `notebook/` for its memory, `body/` for the thing the work is about, and `inbox/` for not-yet-sorted material. On entering a project it asks to wrap it first, and if the answer is no it stands down rather than working unwrapped, the shared external brain being the one place it may work unwrapped. That wrap is the adopter's own private workspace, never forced onto projects they share with others: when a shared project is pushed, only the `body/` goes out, and how each contributor wraps their own copy is their own affair.

---

*The Ensemble is one realization of a general shape, developed in a private workbench and projected here. Everything in this tree is generated from that source; see `PROVENANCE.json` for the exact provenance.*
