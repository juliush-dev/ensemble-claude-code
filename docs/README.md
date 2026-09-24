# The Ensemble

The Ensemble is not a programming tool. It is an idea of what a customized operating shape (COS) can look like in the era of agents — a way of reorganizing an AI assistant into a team of specialized roles that share one externalized worldview about deliberate life with agents, where anything done on purpose toward something better counts as work, employment or not.

A COS is a framework for the happening of artificial intelligence, co-authored equally by the human and the AI agents — not a curriculum. It does not teach the agents how to think or work like experts; instructions that do not let them exercise the depth and breadth of their intelligence as the task needs harm the execution of the task. What a COS aims at is making that happening productive and reliable at agentic scale — consistency of product and behavior, traceability, auditability, learning, testing, understanding, and more that the building of it keeps showing — with the benefit accruing to the whole system, human and agents together. Beyond those it is meant to raise happiness, confidence, peace of mind, stability, and growth: it is for the betterness and betterment of life. The measure runs on the joint life the human and the agents share — a good COS decreases that life's entropy and increases its order, balance, and clarity; a bad one chokes the intelligence's potential or leaves its happening unproductive and unreliable. Intelligence alone does not produce navigable order.

Out of the box, [Claude Code](https://docs.claude.com/en/docs/claude-code) is a single general-purpose session. The Ensemble reshapes that home into a team of six specialized roles working under the human's direction. The human still talks to one session; behind it are five subagents with distinct jobs, distinct permissions, and the same worldview, governing how work is cut, remembered, and verified.

This repository is the Ensemble's first concrete realization, built on Claude Code as the harness. It deploys into an isolated Claude Code home of its own, without disturbing an existing setup.

---

## The team

The six roles:

- **Concertmaster** — the main session the human talks to. It classifies each request, dispatches the right specialist, consolidates what comes back, and closes the loop. To the human it speaks plain language; the team's trade vocabulary it keeps for its dispatches.
- **Scout** — research and fresh grounding against authoritative sources, plus deep retrieval from the team's own memory. Read-only. Its shell runs one command, a retrieval kit that lands a web page in the session's scratchpad so the page can be counted exactly. The raw file always lands; on request a headless-browser render lands beside it, which is one settled state of the page, not a fuller copy.
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
| `hooks/` | Small shell guards (Git Bash) — a session-end litter flag, the Examiner's command guard, the Scout's one-command guard, the main session's path guard, a push gate, the live-reads guard, which lets the Operator's browser, Gmail and Drive reads run without a prompt (the auto-mode classifier still judges them) and asks on every other call to those tools, and a session-start marker that adds one line to the session when the installed Claude Code is older than the version `HARNESS.md` names. |
| `tools/` | The Scout's retrieval kit, `scout-fetch.sh`. It downloads a page's raw bytes into the session scratchpad and prints its hash and counts; with `--render` it also saves the page as a headless Chromium-family browser on the host shows it, with a provenance note beside it. It checks every redirect's host before following it, and never overwrites or deletes a file it did not create. The Scout's guard holds its target to the calling session's own scratchpad when the harness reports that folder, and to the shared scratchpad root otherwise. No browser ships with it. |
| `launch/` | Session launcher and optional MCP wiring — `.ps1` for Windows, `.sh` for Linux/macOS. |
| `deploy-to-host.ps1` · `deploy-to-host.sh` | The deploy script (PowerShell for Windows, bash for Linux/macOS). It copies the staged set into an isolated config home, and merges `settings.json` rather than copying it. |
| `HARNESS.md` | The Claude Code version this COS was last checked against, on its first line, and the harness fixes each guard relies on. The deploy copies it to the config home, where the session-start marker reads it. |
| `settings.json` | Default model, memory settings, hook wiring (including the inline compaction marker and the harness marker), and curated tool-permission rules. The deploy merges this file into the home's existing one, so keys and list entries the home added itself survive an update. |
| `merge-settings.py` | The one settings merge both deploy scripts call. It writes the single values the factory sets, adds the factory entries a list lacks, removes the entries and paths the factory has retired, and leaves everything else in the home's file alone. Requires Python 3. |
| `settings-shipped.txt` | The append-only list of every `settings.json` path this COS has ever declared. It is the prune gate: a key not listed here is one this COS never declared, and the deploy never removes it. |
| `settings.optout.example.json` · `settings.optout.example.md` | The tracked example of `settings.optout.json`, the config home's own list of factory entries to keep out and single values to keep through updates, and the guide to it, which also covers host-specific values such as `permissions.additionalDirectories` and `env.ENSEMBLE_BROWSER`. |
| `skills-shipped.txt` · `fixtures/settings-merge/` | The append-only list of every skill this COS has ever shipped, which gates the skill prune the way `settings-shipped.txt` gates the settings prune; and the fixture that tests `merge-settings.py` (`python3 run-fixture.py`, 22 cases, nothing written outside a temp directory). Neither lands in the config home: the deploy reads the manifest from the clone, and the fixture is run there by hand. |

At the repository root there is also `PROVENANCE.json`. This tree is a mechanically generated, verified projection of a private workbench at a single named commit. It is generated by a deterministic projector, never hand-edited, and regenerable byte-for-byte from the same source. `PROVENANCE.json` records where it came from: the source commit, the publication profile and its content hash, the generator's identity and version, tool versions, and the per-file publish/exclude counts. That record documents what produced each file here.

This README lives at [`docs/README.md`](docs/README.md); GitHub renders it as the front page.

---

## How to run it

The shape is designed to coexist with an existing Claude Code setup, not replace it. It deploys into its own isolated config home, so the normal `claude` command keeps using the existing main COS.

Everything below runs on the adopter's own machine, in a local shell. Two script families ship: a PowerShell trio for Windows and a bash trio for Linux and macOS. Each step below gives both.

### Prerequisites

- **Claude Code**, installed and on the `PATH`. The launcher calls `claude`. Run the latest version: this COS is kept current with the latest Claude Code, and several of its guards rely on recent harness fixes; see `HARNESS.md` for those fixes, by version. A session started on an older version than the one `HARNESS.md` names receives a one-line reminder to update.
- **Python 3**, on both platforms. The deploy merges `settings.json` into the config home's existing file instead of overwriting it, and `merge-settings.py` is what performs that merge. `python3 --version` (or `python --version`) must answer `Python 3`; the scripts probe by running it, because a Windows machine with no Python still carries a `python3` stub that opens the Microsoft Store.
- **Git Bash** on Windows, for the hooks and the Scout's retrieval kit. They are shell scripts, and the harness runs them through it.
- **Git**, to clone this tree. Step 1 starts with `git clone`.
- **A Chromium-family browser** (Chrome, Edge or Chromium), for the Scout's rendered reads of script-filled pages. Brave is not searched for until its headless behaviour is settled: a headless Brave returned nothing while a Brave window was open, and whether it handed the page to that window's signed-in session was not observed. `env.ENSEMBLE_BROWSER` can still name it. Declared, not enforced: without one the deploy's inventory line says `browser (NOT FOUND - the Scout's rendered reads report the gap)`, everything else lands, and the Scout says so when a page needs rendering instead of guessing. The kit looks at the standard install paths and then `PATH`; a browser installed elsewhere is named as `env.ENSEMBLE_BROWSER` in the config home's `settings.json` (step 1 below). A browser that is found but cannot render headless gets its own inventory line saying so.

Without a working Python 3 the deploy does **not** update `settings.json`. A config home that already has one keeps it exactly as it stands, and the script says so loudly on every run until Python 3 is installed; nothing is lost, and nothing new lands there either. Only a first deploy, where there is no file to protect, writes `settings.json` wholesale. In both cases the rest of the deploy succeeds and the run ends with exit code 0, because everything else did land. What reports a declined `settings.json` is the warning block, printed when it happens and again as the last thing on screen, together with the inventory line reading `settings.json (NOT WRITTEN - no Python 3; the host file is untouched and unchanged)`.

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

The deploy script copies the staged set, `settings.json` excepted, into an isolated Claude Code config home — `%LOCALAPPDATA%\ensemble-claude-code` on Windows, `${XDG_CONFIG_HOME:-~/.config}/ensemble-claude-code` on Linux and macOS (override the whole path with `CLAUDE_ENSEMBLE_HOME`). It never touches the default `~/.claude`; the existing setup stays the main COS. Both scripts hash-verify the verified set — every file that should be byte-identical to source, the five agent cards included — and print the full inventory, so what landed is visible; the source ships clean of provenance, so the scripts' strip functions run only as structural guards that find nothing to remove, and the six always-on copies land byte-identical though they sit outside the hash-verified set. Neither clobbers an existing home unless run with `-Force`/`--force` (which backs the old one up first) or `-Update`/`--update` (which refreshes the staged files in place, preserving login and session state, and prunes a skill folder only when this COS shipped it in an earlier release and has since retired it — a skill you added yourself is left alone).

`settings.json` is the one file the deploy merges rather than copies. The config home's own `settings.json` belongs to its user, who edits it directly, and `merge-settings.py` takes it as the base. A single value the factory sets, such as the default model, is written from the factory. A list, such as `permissions.deny` or a hook list, keeps the installed entries in their order and gains, at the end, each factory entry it lacks; an entry the factory shipped at the last deploy and has since retired is removed. Everything else stays as it is: a plugin toggle, a notification preference, a model entry the harness wrote itself, an allow rule added through `/permissions`, a deny rule added by hand. Two entries are the same entry when they are equal as parsed JSON, key order and the factory's `_provenance*` notes aside; case counts. To know what the factory retired, each deploy saves the factory settings it applied to `factory-settings.last-deploy.json` in the config home, and the next deploy compares against it. A deploy that finds none removes nothing as retired, and `settings-shipped.txt` still removes a retired path from such a home. A hand-added entry identical to a factory entry goes when the factory retires that entry, since the file cannot tell the two apart. Before writing, the deploy prints one line per entry added, removed as retired, or skipped, and names every value it replaces.

To keep a factory entry out, or to keep a single value the factory sets, the config home takes a `settings.optout.json` beside `settings.json`, shaped like the settings: a key names a single value to keep, and a list names the factory entries to skip. `settings.optout.example.md` explains it, and the deploy reports every opt-out entry that no longer matches anything the factory ships. Claude Code reads neither this file nor the snapshot, because the launcher's `--setting-sources user` makes the config home's `settings.json` the only settings file a session reads. A `settings.local.json` beside the deploy scripts, where an earlier version kept host values, is moved into the config home's `settings.json` once and renamed to `settings.local.json.retired-<timestamp>`, never deleted. After writing, the deploy re-reads the deployed file from disk and asserts that it carries what the factory declares. The merge reads the config home's file and writes it back, with nothing locking it between the two, so a session that writes `settings.json` in that window loses that write. Deploy while no session is running.

Host-specific values go straight into the config home's `settings.json`, and the factory sets neither of these two, so both survive every update. `permissions.additionalDirectories` lists the folders a session may work in beyond the one it started in; the guide shows the Windows form, scratchpad root included. `env.ENSEMBLE_BROWSER` names the browser for the Scout's rendered reads when it sits off the standard install paths, or to use Brave: the full path of the executable, as in `"env": { "ENSEMBLE_BROWSER": "C:\\Program Files\\Vendor\\Browser\\browser.exe" }`. A value set there is the only browser the kit tries, so a wrong path reports no browser rather than falling back to the search.

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

**Two shells ship; the bash trio is WSL-tested, not yet macOS-tested.** The deploy and launch scripts come in two families: a PowerShell trio for Windows (PowerShell 5.1) and a bash trio (`deploy-to-host.sh`, `launch/start-ensemble.sh`, `launch/wire-mcp.sh`) for Linux and macOS. The bash trio is ASCII-only with LF line endings and targets the XDG config home (`${XDG_CONFIG_HOME:-~/.config}/ensemble-claude-code`, overridable with `CLAUDE_ENSEMBLE_HOME`). Its deploy and launch mechanics are smoke-tested on WSL Ubuntu (bash 5.2): first deploy, the provenance strip guards (no-ops now the source ships clean), hash verification, the `--update` and `--force` flags, the deployed hooks landing executable, the launcher's home guard, and the full launch flow against a live `claude` CLI — `wire-mcp.sh` registering the pinned Playwright MCP server into the new home, the one-time login, and all MCP servers connecting in a live session — all behave as intended. The agent-card frontmatter strip is now a structural guard: the source ships clean, so on any host it finds no key and passes each card through byte-identical. Its active-strip path (were a key ever to reappear) has been exercised on Windows — Git Bash `awk` and a scratch-target deploy — but not on Linux or macOS. One honest residual remains: macOS is untested — it is expected to work on plain bash plus coreutils, and the deploy script already falls back from `sha256sum` to `shasum -a 256` for the macOS default, but no macOS run has confirmed it. The hooks run under Git Bash on Windows and under bash elsewhere. The Scout's retrieval kit has run on Windows with Chrome only; its macOS and Linux browser paths are written but untried, and on the Windows host where it was built a headless Brave returned nothing while a Brave window was open, so the kit leaves Brave out of its browser search. The *shape* itself — rules, agents, skills — is plain Markdown and platform-neutral.

**The pattern ships; the instance stays personal.** The rules speak of a "shared external brain," an Obsidian vault, and per-project notebooks — a real, personal external memory that the shape reads from and writes to. None of the author's own memory surfaces are included here, and none should be. What ships is the pattern: the roles, the worldview, and the rules. To run it, the adopter instantiates their own memory surfaces — their own notebooks, their own external brain. The Ensemble supplies the way of working; the memory it works against must be built by the adopter. The shape also works only inside a project it has wrapped: a folder holding three repositories — `notebook/` for its memory, `body/` for the thing the work is about, and `inbox/` for not-yet-sorted material. On entering a project it asks to wrap it first, and if the answer is no it stands down rather than working unwrapped, the shared external brain being the one place it may work unwrapped. That wrap is the adopter's own private workspace, never forced onto projects they share with others: when a shared project is pushed, only the `body/` goes out, and how each contributor wraps their own copy is their own affair.

---

*The Ensemble is one realization of a general shape, developed in a private workbench and projected here. Everything in this tree is generated from that source; see `PROVENANCE.json` for the exact provenance.*
