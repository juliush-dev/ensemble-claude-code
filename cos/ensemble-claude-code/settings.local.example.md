# The host companion: `settings.local.json`

This is the guidance for `settings.local.example.json`, the tracked example beside it. It lives in a separate file because JSON has no comments, and because a `_provenance` key holding this text inside the example would be a real settings path: copied to `settings.local.json` it would be declared by the companion, land on the host, and never be prunable again (`settings-shipped.txt` is a tracked factory file and cannot list a companion-only path). The guidance belongs beside the example, not inside it.

## What it is

`settings.json` in this folder is tracked and stays free of usernames and machine paths. Host-specific settings live in `settings.local.json` beside it, which is gitignored and never tracked. The launcher runs `claude --setting-sources user`, so the deployed home's `settings.json` is the only settings file a session reads. That makes the deploy-time merge the one door for host values.

To use it: copy `settings.local.example.json` to `settings.local.json` in the same folder, fill in the real paths, and leave the copy untracked.

## What the deploy does with it

`deploy-to-host.ps1` and `deploy-to-host.sh` call `merge-settings.py`, which merges source plus this companion **into the host's existing `settings.json`**:

- every path source or the companion declares is replaced with the declared value,
- every path `settings-shipped.txt` lists and source no longer declares is pruned,
- every other key the host carries is left alone.

Replaced means replaced. An array is one value, written whole, never unioned. Two consequences follow.

- **Removing an entry from the list below takes effect** on the next update, and a directory some session added to the deployed file by hand does not survive one.
- **Removing the whole `additionalDirectories` key does not take effect.** A path only the companion ever declared is stranded on the host when the companion stops declaring it: the prune gate is a tracked factory file that cannot list a companion-only path, so nothing tells the deploy that the key was ever managed. The way out is to delete the key from the deployed `settings.json` by hand, once. The failure mode is a leftover key, never a deleted one.

Python 3 is a prerequisite of the deploy. Without it the deploy leaves an existing host `settings.json` untouched and says so on every run, and this companion is not merged at all.

## The path values

The values use the double-backslash form because JSON escapes backslashes, so a doubled backslash is the one literal separator once parsed. The merge preserves each value into the deployed `settings.json` exactly as written.

The third `additionalDirectories` entry (`C:\\Users\\<your-username>\\AppData\\Local\\Temp\\claude`, written here in the same escaped form the file itself uses) is the harness's per-session scratchpad root, so members write there without asking. Whether a dispatched subagent inherits `additionalDirectories` from the parent session is unchecked.

Where the harness advertises that scratchpad in 8.3 short form (a `<your-username>~1` segment, for example `C:\\Users\\<SHORT~1>\\AppData\\Local\\Temp\\claude`), add that short-form root as an additional entry too.

On a Linux host the scratchpad root carries a per-uid segment, so the third entry is `/tmp/claude-<uid>`. That uid segment is inferred from the Windows form, not verified against the harness docs. On macOS it is the `TMPDIR`-based form `${TMPDIR}/claude-<uid>`, unlived: no macOS host has run this.
