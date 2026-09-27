weighed: 2.1.283

# The Claude Code fixes this COS relies on

The line above names the Claude Code version this COS was last checked against. Run the latest Claude Code: each guard below holds as described only from the version that fixed it.

- 2.1.211: a PreToolUse hook's `ask` on Bash floors the decision at a prompt in auto mode. `hooks/guard-push-gate.sh` and `hooks/guard-herenow.sh` rely on it.
- 2.1.211: nested `.claude/rules` files stay out of a session whose setting sources exclude project settings. The launcher's `--setting-sources user` isolation relies on it.
- 2.1.214 and 2.1.232: two PowerShell permission-bypass fixes, one for Windows PowerShell 5.1 sessions, one for `$PSDefaultParameterValues`. The `PowerShell(git push)` ask rules rely on them.
- 2.1.216: a resumed background agent session restores the agent's prompt and tool restrictions. A resumed member keeps its card's envelope through it.
- 2.1.257: a `permissions.ask` rule holds in auto mode inside a compound command or subshell. The `git push` ask rules rely on it.
- 2.1.257: hook input carries `scratchpad_dir`. `hooks/guard-scout-bash.sh` anchors to it; without it the guard falls back to the shared scratchpad root.
- 2.1.267: `effort:` frontmatter on subagents applies on models whose default effort is pinned. The Examiner card's `effort:` level relies on it.
- 2.1.269: `Edit()` deny rules and the write-path check cover the file a Bash `tee` writes. The memory-path deny rules rely on it.
- 2.1.280: a write through a symlinked path is judged by where it lands, not by its in-tree spelling. `hooks/guard-archivist-paths.sh` reads paths as written and relies on it for symlinks.
- 2.1.282 (observed there; the version that fixed it is unrecorded): a PreToolUse hook's `ask` on an MCP tool floors the decision at a prompt in auto mode. `hooks/guard-openknowledge.sh` relies on it.
- 2.1.283 (documented there, observed headless; the version that added it is unrecorded): `--append-system-prompt-file` appends a file to the main session's system prompt, interactive or headless, and the text survives compaction; members never receive that prompt. The launchers and `probe-context.ps1` rely on it to give the main session `CONCERTMASTER.md`, the Concertmaster's own rules, and no member.
- 2.1.283 (documented there): SessionStart fires in the main session only; a member gets SubagentStart. `hooks/session-start-cue.sh` relies on it to print `CONCERTMASTER.md` as its fallback into the main session alone.
- 2.1.283 (documented there): a hook's plain stdout is capped at 10,000 characters; above it the model gets a 2,000-character preview and a file path. `fixtures/session-cue/run-fixture.sh` holds the cue's longest print under 9,000.
