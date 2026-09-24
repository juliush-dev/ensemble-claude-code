# Keeping settings through an update: `settings.optout.json`

This is the guidance for `settings.optout.example.json`, the tracked example beside it. It lives in a separate file because JSON has no comments.

## How an update treats the settings

The deploy (`deploy-to-host.ps1` or `deploy-to-host.sh`) merges this folder's `settings.json` into the config home's own `settings.json`, through `merge-settings.py`. The config home's file belongs to its user, who edits it directly. The factory ships defaults, not locks.

- A single value the factory sets, such as the default model or an effort level, is written from the factory on every update. A single value the factory does not set is left alone.
- A list, such as `permissions.deny`, `permissions.ask` or `hooks.SessionStart`, merges by adding. The installed items stay, in their order, and each factory item the list lacks is added at the end. An item the factory shipped at the last deploy and has since retired is removed.
- Every other key stays as it is: `permissions.allow`, `permissions.additionalDirectories`, `env`, a plugin toggle.

Two list items are the same item when they are equal as parsed JSON. Key order and spacing do not matter and `_provenance*` note keys are ignored, but case counts: `Edit(x)` and `edit(x)` are two items.

To know what the factory retired, each deploy saves the factory settings it applied to `factory-settings.last-deploy.json` in the config home, and the next deploy compares against that. A deploy that finds no such file removes nothing as retired, then writes one. One trade is accepted: a hand-added item identical to a factory item is removed when the factory retires that item, because the file cannot tell the two apart.

Claude Code reads neither `settings.optout.json` nor `factory-settings.last-deploy.json`. The settings files it reads are managed settings, `--settings`, a project's `.claude/settings.json` and `.claude/settings.local.json`, and `settings.json` in the config home, and the launcher's `--setting-sources user` narrows that to the last one.

## The opt-out file

`settings.optout.json` sits in the config home next to `settings.json`, shaped like the settings. It is needed only when something should not follow the factory, and it does two things.

- **Keep a single value.** Name its key. The key's presence is what counts, so `true` reads plainly. `{"model": true}` keeps the installed `model` through every update, even when the factory ships a new default. A key the config home does not have stays absent.
- **Keep a factory list item out.** List the item under its setting, in full. The update never adds it, never removes an installed copy of it, and never removes it as retired. Dropping a factory hook for good takes both steps: delete it from `settings.json`, and list it here, or the next update adds it back.

`settings.optout.example.json` shows one of each. It keeps the installed `model`, and it keeps out the session-start harness marker, the hook that adds a line to a session when the installed Claude Code is older than the version `HARNESS.md` names. Every entry in the example takes effect, so only the entries that are wanted belong in a real `settings.optout.json`.

Each update prints one line per list item added, removed as retired, or skipped by opt-out, and one per opted-out single value it kept. An entry that matches nothing the factory ships now is reported on every update, so a stale one gets noticed. An opt-out file that is not valid JSON stops the settings merge: `settings.json` is left exactly as it was, the deploy says so, and the rest of the deploy lands.

## Host-specific values

Machine paths and other host values go straight into the config home's `settings.json`. The factory sets neither of the two below, so they survive every update without an opt-out entry.

The path values use the double-backslash form, because JSON escapes backslashes and a doubled backslash is one literal separator once parsed.

### `permissions.additionalDirectories`

The directories a session may work in without asking, beyond the one it started in. A Windows host typically carries three:

```json
"permissions": {
  "additionalDirectories": [
    "C:\\Users\\<your-username>\\Projects",
    "C:\\Users\\<your-username>\\Shared-External-Brain",
    "C:\\Users\\<your-username>\\AppData\\Local\\Temp\\claude"
  ]
}
```

The third entry is the harness's per-session scratchpad root, so members write there without asking. Whether a dispatched subagent inherits `additionalDirectories` from the parent session is unchecked.

Where the harness advertises that scratchpad in 8.3 short form (a `<your-username>~1` segment, for example `C:\\Users\\<SHORT~1>\\AppData\\Local\\Temp\\claude`), the short-form root belongs in the list as well.

On a Linux host the scratchpad root carries a per-uid segment, so the third entry is `/tmp/claude-<uid>`. That uid segment is inferred from the Windows form, not verified against the harness docs. On macOS it is the `TMPDIR`-based form `${TMPDIR}/claude-<uid>`, unlived: no macOS host has run this.

### `env.ENSEMBLE_BROWSER` (optional)

The Scout's retrieval kit (`tools/scout-fetch.sh`) renders script-filled pages in a Chromium-family browser the host already has. It looks for Chrome, Edge and Chromium at their standard install paths, then on `PATH`. Without `ENSEMBLE_BROWSER`, or with it empty, that search runs.

It is needed only when the browser sits somewhere else, or to use Brave, which the search leaves out until its headless behaviour is settled (the kit's header says why). The value is the full path of the executable, under `env` in the config home's `settings.json`, for example `"env": { "ENSEMBLE_BROWSER": "C:\\Program Files\\Vendor\\Browser\\browser.exe" }`. A non-empty value is the only browser the kit tries: if that path is not an executable file, the kit reports NO BROWSER rather than searching further. That is how the absent-browser case is tested.

The settings `env` key sets variables "for every session and for the subprocesses Claude Code starts from it" (the Claude Code settings reference), which is how the value reaches the Scout's shell; that it does so for a dispatched Scout has not been observed yet.

## Moving from `settings.local.json`

An earlier design kept host values in a `settings.local.json` beside the deploy scripts, merged in on every deploy. The first update under this design moves its contents into the config home's `settings.json` once. Its list items join the installed lists, and its single values are set, except a single value the factory also sets: the factory writes that one, and the update names it, since keeping it takes the value in `settings.json` and its key in `settings.optout.json`. The update then renames the file to `settings.local.json.retired-<timestamp>` beside itself and says so. Nothing is deleted; the retired file stays for reference and can be removed by hand.

Python 3 is a prerequisite of the deploy. Without it an existing `settings.json` is left untouched, on every run until Python 3 is installed, and nothing is migrated.
