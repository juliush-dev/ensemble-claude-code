#!/usr/bin/env python3
# run-fixture.py: the fixture for merge-settings.py.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it from anywhere:   python3 run-fixture.py
# Exit 0 PASS, exit 1 FAIL. It writes nothing outside a temp directory it
# removes on the way out, and it never touches a deployed home.
#
# Most cases run merge-settings.py as the deploy scripts do, as a separate
# process over files, and assert on its exit code, its report and the file it
# wrote. A few import it to test one function directly (the item equality) or
# to run its plan over the real source settings.json without writing anything.
#
# THE GOLDEN CASE (case 1) runs one merge over host.json, source.json,
# snapshot.json (what the last deploy applied), optout.json and manifest.txt,
# and compares the written text BYTE FOR BYTE with expected.json, since key
# order is part of what the merge promises. What that one comparison holds:
#
#   * Host keys the factory never declares survive: agentPushNotifEnabled,
#     enabledPlugins, permissions.allow, additionalDirectories, the host's own
#     hooks.SessionEnd, and modelSettings.claude-fable-5-1, which lives INSIDE a
#     factory-declared object.
#   * Lists merge by adding, installed items first in their order, new factory
#     items at the end: the host's own deny and ask entries stay.
#   * A retired factory item (in the snapshot, not in source) goes:
#     mcp__claude_ai_* from permissions.ask, compaction-marker-v1 from
#     hooks.SessionStart. The version swap lands exactly: installed
#     [v1, host-hook] becomes [host-hook, v2].
#   * A retired list path (hooks.Notification) loses only the factory's item;
#     the host's own stays. A retired single path (_provenance_retired) goes.
#   * The same item: the host's Bash|PowerShell entry, written with its keys in
#     another order, and its Edit|Write entry, which lacks the factory's
#     _provenance_note, are each the factory's item and are not added twice.
#     edit(...) and Edit(...) differ only in case and are two items.
#   * Single values: model is written from the factory; the opted-out
#     modelSettings.claude-opus-5.effortLevel keeps the host's "high".
#   * An opted-out list item (Bash(git push *)) is not added.
#   * Two stale opt-out entries are reported.
#
# Then the snapshot must equal source, a second run must change nothing, and the
# deployed file must carry no BOM.

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
COS = os.path.normpath(os.path.join(HERE, "..", ".."))
SCRIPT = os.path.join(COS, "merge-settings.py")
SOURCE = os.path.join(HERE, "source.json")
SNAPSHOT = os.path.join(HERE, "snapshot.json")
OPTOUT = os.path.join(HERE, "optout.json")
MANIFEST = os.path.join(HERE, "manifest.txt")
HOST = os.path.join(HERE, "host.json")
COMPANION = os.path.join(HERE, "legacy-companion.json")
REAL_SOURCE = os.path.join(COS, "settings.json")
REAL_MANIFEST = os.path.join(COS, "settings-shipped.txt")
REAL_EXAMPLE = os.path.join(COS, "settings.optout.example.json")

FAILURES = []
PASSED = []


def fail(case, msg):
    print("FAIL (%s): %s" % (case, msg))
    FAILURES.append(case)
    return 1


def ok(case, msg):
    print("PASS (%s): %s" % (case, msg))
    PASSED.append(case)
    return 0


def load_module():
    spec = importlib.util.spec_from_file_location("merge_settings", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run(mode, target, source=SOURCE, manifest=MANIFEST, optout=None,
        snapshot=None, companion=None):
    args = [sys.executable, SCRIPT, mode, "--source", source,
            "--target", target]
    for flag, val in (("--manifest", manifest), ("--optout", optout),
                      ("--snapshot", snapshot),
                      ("--legacy-companion", companion)):
        if val:
            args += [flag, val]
    return subprocess.run(args, capture_output=True, text=True)


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write(path, obj):
    text = obj if isinstance(obj, str) else json.dumps(obj, indent=2) + "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def raw(path):
    with open(path, "rb") as f:
        return f.read()


def home(tmp, name, host=None, snapshot=None, optout=None):
    # A scratch installed home: settings.json, and optionally a snapshot and an
    # opt-out file beside it, as the deploy scripts lay them out.
    d = os.path.join(tmp, name)
    os.makedirs(d)
    paths = {"target": os.path.join(d, "settings.json"),
             "snapshot": os.path.join(d, "factory-settings.last-deploy.json"),
             "optout": os.path.join(d, "settings.optout.json")}
    for key, val in (("target", host), ("snapshot", snapshot),
                     ("optout", optout)):
        if val is None:
            continue
        if isinstance(val, str) and os.path.isfile(val):
            shutil.copyfile(val, paths[key])
        else:
            write(paths[key], val)
    return paths


def merge(h, **kw):
    return run("merge", h["target"], optout=h["optout"],
               snapshot=h["snapshot"], **kw)


def verify(h, **kw):
    return run("verify", h["target"], optout=h["optout"],
               snapshot=h["snapshot"], **kw)


def hook(cmd, matcher=None):
    item = {"hooks": [{"type": "command", "command": cmd}]}
    if matcher:
        item["matcher"] = matcher
    return item


# --- case 1: the golden case, and the second run ----------------------------


def case_golden(tmp):
    name = "case 1, golden"
    h = home(tmp, "golden", HOST, SNAPSHOT, OPTOUT)
    r = merge(h)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s%s" % (r.returncode, r.stdout,
                                                      r.stderr))
    got = raw(h["target"])
    want = raw(os.path.join(HERE, "expected.json")).replace(b"\r\n", b"\n")
    if got.startswith(b"\xef\xbb\xbf"):
        return fail(name, "the deployed file carries a UTF-8 BOM.")
    if got != want:
        gl = got.decode("utf-8").splitlines()
        wl = want.decode("utf-8").splitlines()
        for i in range(max(len(gl), len(wl))):
            g = gl[i] if i < len(gl) else "<no line>"
            w = wl[i] if i < len(wl) else "<no line>"
            if g != w:
                return fail(name, "line %d differs.\n  expected: %s\n  got:      "
                            "%s" % (i + 1, w, g))
        return fail(name, "output differs from expected.json in trailing bytes.")
    for line in ('removing retired factory item "mcp__claude_ai_*"',
                 "compaction-marker-v1",
                 'skipping factory item "Bash(git push *)"',
                 "pruning retired factory path _provenance_retired",
                 'item "Stale(entry)" matches no item',
                 "env.NOT_A_FACTORY_KEY matches nothing",
                 'replacing host value at model (host "fable"'):
        if line not in r.stdout:
            return fail(name, "the report lacks %r.\n%s" % (line, r.stdout))
    if load(h["snapshot"]) != load(SOURCE):
        return fail(name, "the snapshot written is not source settings.json.")
    v = verify(h)
    if v.returncode != 0:
        return fail(name, "verify exited %d.\n%s" % (v.returncode, v.stderr))
    ok(name, "byte-identical to expected.json, no BOM, every effect named in "
       "the report, the snapshot equals source, verify clean.")

    name = "case 2, second run changes nothing"
    r2 = merge(h)
    if r2.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r2.returncode, r2.stderr))
    if raw(h["target"]) != got:
        return fail(name, "the second run changed the file.")
    if "0 list item(s) added, 0 retired item(s) removed" not in r2.stdout:
        return fail(name, "the second run reports changes.\n%s" % r2.stdout)
    return ok(name, "byte-identical after a second merge; the report counts "
              "nothing added, removed, replaced or pruned.")


# --- the snapshot cases -----------------------------------------------------


def case_retired_removed_user_kept(tmp):
    name = "case 3, retired item removed, user item kept"
    h = home(tmp, "retire",
             host={"permissions": {"ask": ["Old(x)", "Keep(y)", "Mine(u)"]}},
             snapshot={"permissions": {"ask": ["Old(x)", "Keep(y)"]}})
    src = os.path.join(tmp, "retire-source.json")
    write(src, {"permissions": {"ask": ["Keep(y)"]}})
    r = merge(h, source=src, manifest=None)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    got = load(h["target"])["permissions"]["ask"]
    if got != ["Keep(y)", "Mine(u)"]:
        return fail(name, "expected [Keep(y), Mine(u)], got %s" % got)
    if 'removing retired factory item "Old(x)"' not in r.stdout:
        return fail(name, "the removal was not named.\n%s" % r.stdout)
    return ok(name, "Old(x) removed and named, Mine(u) kept, order kept.")


def case_changed_item(tmp):
    name = "case 4, factory changes an item"
    v1, v2 = hook("marker v1", "compact"), hook("marker v2", "compact")
    h = home(tmp, "change",
             host={"hooks": {"SessionStart": [v1, hook("host-hook.sh")]}},
             snapshot={"hooks": {"SessionStart": [v1]}})
    src = os.path.join(tmp, "change-source.json")
    write(src, {"hooks": {"SessionStart": [v2]}})
    r = merge(h, source=src, manifest=None)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    got = load(h["target"])["hooks"]["SessionStart"]
    if got != [hook("host-hook.sh"), v2]:
        return fail(name, "expected [host-hook, v2], got %s" % got)
    return ok(name, "the old version goes, the new one arrives at the end, the "
              "host's own entry stays first.")


def case_no_snapshot(tmp):
    name = "case 5, first run with no snapshot"
    h = home(tmp, "bootstrap", HOST, None, OPTOUT)
    r = merge(h)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    if r.stdout.count("no snapshot of the factory settings") != 1:
        return fail(name, "the no-snapshot line was not printed exactly once."
                    "\n%s" % r.stdout)
    if "removing retired" in r.stdout:
        return fail(name, "an item was removed as retired with no snapshot.")
    out = load(h["target"])
    if "mcp__claude_ai_*" not in out["permissions"]["ask"]:
        return fail(name, "a list item was retired with no snapshot to say so.")
    starts = out["hooks"]["SessionStart"]
    if hook("echo compaction-marker-v2", "compact") not in starts:
        return fail(name, "the factory's current item was not added.")
    if len(out["hooks"]["Notification"]) != 2:
        return fail(name, "the retired list path was cut with no snapshot; it "
                    "must be kept whole.")
    if "so the whole list is kept" not in r.stderr:
        return fail(name, "keeping the retired list path was not warned.\n%s"
                    % r.stderr)
    if "_provenance_retired" in out:
        return fail(name, "settings-shipped.txt's path-level prune did not "
                    "run without a snapshot.")
    if load(h["snapshot"]) != load(SOURCE):
        return fail(name, "the first run did not write the snapshot.")
    return ok(name, "one line says no snapshot existed; nothing removed as "
              "retired, the factory's items added, the retired list path kept "
              "whole with a warning, the manifest still prunes the retired "
              "path, and the snapshot is written.")


def case_skipped_release(tmp):
    name = "case 6, a skipped release"
    # Release N put A on this home. N+1 shipped B; this home never deployed
    # it. N+2 ships C. The user added a B of their own. The home last received
    # N, so A is retired, C is new, and B was in neither this home's snapshot
    # nor the factory now: it is never touched.
    h = home(tmp, "skipped",
             host={"permissions": {"deny": ["A(n)", "B(n+1)", "Keep(all)"]}},
             snapshot={"permissions": {"deny": ["A(n)", "Keep(all)"]}})
    src = os.path.join(tmp, "skipped-source.json")
    write(src, {"permissions": {"deny": ["Keep(all)", "C(n+2)"]}})
    r = merge(h, source=src, manifest=None)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    got = load(h["target"])["permissions"]["deny"]
    if got != ["B(n+1)", "Keep(all)", "C(n+2)"]:
        return fail(name, "expected [B(n+1), Keep(all), C(n+2)], got %s" % got)
    return ok(name, "measured against what the home last received: A removed, "
              "C added, B (in neither) untouched.")


# --- the named lived cases --------------------------------------------------


def case_host_list_item(tmp):
    name = "case 7, host list item"
    marker = hook("echo [compaction-marker] ...", "compact")
    h = home(tmp, "host-hook",
             host={"hooks": {"SessionStart": [hook("host-hook.sh")]}})
    src = os.path.join(tmp, "host-hook-source.json")
    write(src, {"hooks": {"SessionStart": [marker]}})
    r = merge(h, source=src, manifest=None)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    got = load(h["target"])["hooks"]["SessionStart"]
    if got != [hook("host-hook.sh"), marker]:
        return fail(name, "expected [host-hook, compaction marker], got %s"
                    % got)
    return ok(name, "the host's list item and the factory's compaction marker "
              "both land; the marker is not lost to the host's list.")


def case_two_pretooluse(tmp):
    name = "case 8, two hooks.PreToolUse objects stay two"
    a = hook("guard-push-gate.sh", "Bash|PowerShell")
    b = hook("guard-archivist-paths.sh main-session", "Edit|Write")
    src = os.path.join(tmp, "two-source.json")
    write(src, {"hooks": {"PreToolUse": [a, b]}})
    h = home(tmp, "two-empty", host={})
    r = merge(h, source=src, manifest=None)
    got = load(h["target"])["hooks"]["PreToolUse"]
    if r.returncode != 0 or got != [a, b]:
        return fail(name, "into an empty host: expected both entries, got %s"
                    % got)
    h2 = home(tmp, "two-present", host={"hooks": {"PreToolUse": [
        {"matcher": "Edit|Write", "hooks": b["hooks"]},
        {"matcher": "Bash|PowerShell", "hooks": a["hooks"]}]}})
    r = merge(h2, source=src, manifest=None)
    got = load(h2["target"])["hooks"]["PreToolUse"]
    if r.returncode != 0 or len(got) != 2:
        return fail(name, "with both already present: expected 2, got %d"
                    % len(got))
    return ok(name, "two distinct entries land as two, and stay two when the "
              "host already has both; the old Merge-Json collapsed them to one.")


# --- opt-outs ---------------------------------------------------------------


def case_optout_item_stays_gone(tmp):
    name = "case 9, an opted-out item is never added"
    src = os.path.join(tmp, "opt-source.json")
    write(src, {"permissions": {"ask": ["Factory(a)", "Unwanted(b)"]}})
    h = home(tmp, "opt",
             host={"permissions": {"ask": ["Factory(a)", "Unwanted(b)"]}},
             optout={"permissions": {"ask": ["Unwanted(b)"]}})
    r = merge(h, source=src, manifest=None)
    if load(h["target"])["permissions"]["ask"] != ["Factory(a)", "Unwanted(b)"]:
        return fail(name, "the opt-out removed an installed copy; it must only "
                    "stop additions.")
    # The user removes it by hand; the next update must not bring it back.
    write(h["target"], {"permissions": {"ask": ["Factory(a)"]}})
    r = merge(h, source=src, manifest=None)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    if load(h["target"])["permissions"]["ask"] != ["Factory(a)"]:
        return fail(name, "the opted-out item came back after the user "
                    "removed it.")
    if 'skipping factory item "Unwanted(b)"' not in r.stdout:
        return fail(name, "the skip was not reported.\n%s" % r.stdout)
    return ok(name, "an installed copy is left alone, and once the user removes "
              "it the update does not add it back; the skip is reported.")


def case_optout_single(tmp):
    name = "case 10, an opted-out single value stays"
    h = home(tmp, "single", host={"model": "mine", "theme": "dark"},
             optout={"model": True})
    for release in ("opus", "opus-next"):
        src = os.path.join(tmp, "single-%s.json" % release)
        write(src, {"model": release, "autoMemoryEnabled": False})
        r = merge(h, source=src, manifest=None)
        if r.returncode != 0:
            return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
        out = load(h["target"])
        if out.get("model") != "mine":
            return fail(name, "the factory's %r overwrote the opted-out value."
                        % release)
    if out.get("autoMemoryEnabled") is not False or out.get("theme") != "dark":
        return fail(name, "a factory single value was not written, or a host "
                    "one the factory does not define was touched.")
    return ok(name, "the installed model survives two factory releases; a value "
              "the factory defines is written; one it does not is untouched.")


def case_unreadable_optout(tmp):
    name = "case 11, an unreadable opt-out file"
    h = home(tmp, "badopt", HOST, SNAPSHOT, "{ not json\n")
    before, snap = raw(h["target"]), raw(h["snapshot"])
    r = merge(h)
    if r.returncode != 5:
        return fail(name, "expected exit 5, got %d.\n%s" % (r.returncode,
                                                           r.stderr))
    if raw(h["target"]) != before or raw(h["snapshot"]) != snap:
        return fail(name, "settings.json or the snapshot was written.")
    if "was NOT written" not in r.stderr:
        return fail(name, "the error does not say nothing was written.")
    return ok(name, "exit 5, settings.json and the snapshot byte-unchanged, and "
              "the error says so.")


def case_shipped_example(tmp):
    name = "case 12, the shipped opt-out example is not stale"
    m = load_module()
    source, example = load(REAL_SOURCE), load(REAL_EXAMPLE)
    # An empty host, so every entry that matches a factory value or item shows
    # up as a skip; an installed copy would be left in place, not skipped.
    _, lines, tally, _, _, _ = m.plan({}, source, example, None,
                                      m.RetirementBasis(source))
    stale = [l for l in lines if l.lstrip().startswith("settings.optout.json:")]
    if stale:
        return fail(name, "the example names something the factory no longer "
                    "ships:\n%s" % "\n".join(stale))
    if tally["skipped"] != len(m.leaf_paths(example)):
        return fail(name, "an example entry skips nothing (%d skipped, %d "
                    "entries)." % (tally["skipped"], len(m.leaf_paths(example))))
    return ok(name, "every entry of settings.optout.example.json matches what "
              "the real settings.json ships, so a reader copying one gets an "
              "entry that works.")


# --- the item test ----------------------------------------------------------


def case_same_item(tmp):
    name = "case 13, the same item"
    m = load_module()
    a = json.loads('{"matcher":"X","hooks":[{"type":"command","command":"c"}]}')
    b = json.loads('{\n  "hooks": [ { "command": "c", "type": "command" } ],\n'
                   '  "matcher": "X"\n}')
    checks = [
        (m.same(a, b), True, "key order and spacing"),
        (m.same(dict(a, _provenance_note="n"), a), True, "_provenance only"),
        (m.same({"x": {"_provenance_deep": 1, "y": 2}}, {"x": {"y": 2}}), True,
         "_provenance at depth"),
        (m.same("Edit(a)", "edit(a)"), False, "case"),
        (m.same(True, 1), False, "true against 1"),
        (m.same(5, 5.0), True, "5 against 5.0"),
        (m.same([1, 2], [2, 1]), False, "list order inside an item"),
        (m.same(dict(a, matcher="Y"), a), False, "a real difference"),
    ]
    for got, want, what in checks:
        if got != want:
            return fail(name, "%s: expected %s, got %s" % (what, want, got))
    return ok(name, "equal as parsed JSON: key order, spacing and _provenance* "
              "notes ignored; case, true-versus-1 and list order counted.")


# --- migration from settings.local.json -------------------------------------


def case_migration(tmp):
    name = "case 14, settings.local.json migrates once and retires"
    comp = os.path.join(tmp, "settings.local.json")
    shutil.copyfile(COMPANION, comp)
    original = raw(comp)
    h = home(tmp, "migrate", host={"model": "fable", "hooks": {
        "SessionStart": [hook("host-session-start.sh")]}}, snapshot=SOURCE)
    r = merge(h, companion=comp)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s%s" % (r.returncode, r.stdout,
                                                      r.stderr))
    out = load(h["target"])
    dirs = out.get("permissions", {}).get("additionalDirectories", [])
    if len(dirs) != 3 or not dirs[2].endswith("Only-In-Companion"):
        return fail(name, "the companion's list did not land: %s" % dirs)
    if not out.get("env", {}).get("ENSEMBLE_BROWSER", "").endswith("browser.exe"):
        return fail(name, "the companion's env value did not land.")
    starts = out["hooks"]["SessionStart"]
    if starts != [hook("host-session-start.sh"),
                  hook("echo compaction-marker-v2", "compact")]:
        return fail(name, "SessionStart is not [host-hook, marker] once "
                    "each: %s" % starts)
    if out.get("model") != "opus":
        return fail(name, "the companion's model beat the factory's.")
    if "settings.local.json sets model" not in r.stdout:
        return fail(name, "the factory-defined companion value was not named.")
    if os.path.exists(comp):
        return fail(name, "the companion was not retired.")
    retired = [f for f in os.listdir(tmp)
               if f.startswith("settings.local.json.retired-")]
    if len(retired) != 1 or raw(os.path.join(tmp, retired[0])) != original:
        return fail(name, "the retired companion is missing or changed.")
    if "retired. It was renamed, not deleted" not in r.stdout:
        return fail(name, "the deploy did not say the companion was retired.")
    r2 = merge(h, companion=comp)
    if r2.returncode != 0 or "settings.local.json" in r2.stdout:
        return fail(name, "the second run touched a companion that is gone.")
    return ok(name, "items and host values land once, the host's hand copy "
              "of the marker is not doubled, the factory keeps model and says "
              "how to keep the companion's, and the file is renamed with its "
              "bytes intact, never deleted.")


def case_bad_companion(tmp):
    name = "case 15, an unparseable settings.local.json"
    comp = os.path.join(tmp, "bad-companion", "settings.local.json")
    os.makedirs(os.path.dirname(comp))
    write(comp, "{ broken\n")
    h = home(tmp, "badcomp", HOST, SNAPSHOT)
    r = merge(h, companion=comp)
    if r.returncode != 0:
        return fail(name, "merge exited %d; a bad companion must not fail the "
                    "deploy.\n%s" % (r.returncode, r.stderr))
    if not os.path.exists(comp) or "neither merged nor retired" not in r.stderr:
        return fail(name, "the bad companion was renamed, or not warned about.")
    return ok(name, "warned, neither merged nor renamed, the rest merged.")


# --- the degradation paths --------------------------------------------------


def case_degradation(tmp):
    name = "case 16, missing manifest, no snapshot"
    h = home(tmp, "nomanifest", HOST)
    absent = os.path.join(tmp, "there-is-no-such-manifest.txt")
    r = merge(h, manifest=absent)
    if r.returncode != 0 or "prunes are disabled" not in r.stderr:
        return fail(name, "exit %d, or no warning.\n%s" % (r.returncode,
                                                           r.stderr))
    if "_provenance_retired" not in load(h["target"]):
        return fail(name, "a path was pruned with neither manifest nor "
                    "snapshot to say it was retired.")
    ok(name, "the manifest's prunes disabled with one warning, the retired "
       "path left in place, everything else merged.")

    for num, label, text, words in ((17, "corrupt host file", "{ not json\n",
                                     "not valid JSON"),
                                    (18, "non-object host file", "[1, 2, 3]\n",
                                     "not a JSON object")):
        name = "case %d, %s" % (num, label)
        h = home(tmp, label.replace(" ", "-"), text, SNAPSHOT)
        r = merge(h)
        if r.returncode != 0 or words not in r.stderr or "(ok)" in r.stderr:
            return fail(name, "exit %d, or the warning is wrong.\n%s"
                        % (r.returncode, r.stderr))
        out = load(h["target"])
        if out.get("model") != "opus" or "agentPushNotifEnabled" in out:
            return fail(name, "not a wholesale write of the factory settings.")
        v = verify(h)
        if v.returncode != 0:
            return fail(name, "verify exited %d.\n%s" % (v.returncode, v.stderr))
        ok(name, "degraded to a wholesale write with one warning naming the "
           "fault, and the result verifies.")

    name = "case 19, a manifest line that is an ancestor"
    h = home(tmp, "ancestor", HOST, SNAPSHOT)
    bad = os.path.join(tmp, "manifest-with-ancestor.txt")
    with open(MANIFEST, encoding="utf-8") as f:
        write(bad, f.read().rstrip("\n") + "\npermissions\n")
    r = merge(h, manifest=bad)
    if r.returncode != 0 or "Skipping that prune" not in r.stderr:
        return fail(name, "exit %d, or the line was not refused by name.\n%s"
                    % (r.returncode, r.stderr))
    out = load(h["target"])
    if out["permissions"].get("allow") != ["Bash(ls)"]:
        return fail(name, "the ancestor line was executed.")
    if "_provenance_retired" in out:
        return fail(name, "the other prunes stopped working.")
    v = verify(h, manifest=bad)
    if v.returncode != 0:
        return fail(name, "verify exited %d.\n%s" % (v.returncode, v.stderr))
    return ok(name, "refused by name, the host's subtree intact, the other "
              "prunes working, verify clean.")


def case_real_manifest(tmp):
    name = "case 20, the real settings.json against settings-shipped.txt"
    h = home(tmp, "real", host={})
    r = run("merge", h["target"], source=REAL_SOURCE, manifest=REAL_MANIFEST,
            snapshot=h["snapshot"])
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    if "does not list" in r.stderr:
        return fail(name, "settings-shipped.txt misses a path the real "
                    "settings.json declares.\n%s" % r.stderr)
    return ok(name, "every path the real settings.json declares is listed; no "
              "self-policing warning.")


def case_optout_shields_retired(tmp):
    name = "case 21, an opted-out item is never removed as retired"
    h = home(tmp, "shield",
             host={"permissions": {"deny": ["Old(x)", "Now(y)"]}},
             snapshot={"permissions": {"deny": ["Old(x)", "Now(y)"]}},
             optout={"permissions": {"deny": ["Old(x)"]}})
    src = os.path.join(tmp, "shield-source.json")
    write(src, {"permissions": {"deny": ["Now(y)"]}})
    r = merge(h, source=src, manifest=None)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    if load(h["target"])["permissions"]["deny"] != ["Old(x)", "Now(y)"]:
        return fail(name, "the opted-out retired item was removed.")
    if 'item "Old(x)" matches no item the factory ships now' not in r.stdout:
        return fail(name, "the opt-out entry, now stale, was not reported.\n%s"
                    % r.stdout)
    return ok(name, "the retired item named in the opt-out file stays, and the "
              "entry is reported, since the factory no longer ships it.")


def case_companion_retired_path(tmp):
    name = "case 22, a companion carrying a retired path"
    # An earlier release's example companion carried _provenance, and
    # settings-shipped.txt lists _provenance as retired. A home with no
    # snapshot yet, the real settings.json and the real manifest, as a
    # deploy that finds such a companion runs them.
    d = os.path.join(tmp, "retired-companion")
    os.makedirs(d)
    comp = os.path.join(d, "settings.local.json")
    extra = "C:\\Users\\example\\Projects"
    write(comp, {"_provenance": "a note the factory shipped in the example",
                 "permissions": {"additionalDirectories": [extra]}})
    original = raw(comp)
    h = home(tmp, "retired-companion-home", host={"theme": "dark"})
    r = run("merge", h["target"], source=REAL_SOURCE, manifest=REAL_MANIFEST,
            snapshot=h["snapshot"], companion=comp)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s%s" % (r.returncode, r.stdout,
                                                      r.stderr))
    line = ("settings.local.json carries _provenance, a path the factory "
            "retired; not migrated, the retired companion still holds it.")
    if r.stdout.count(line) != 1:
        return fail(name, "the retired path was not named in one line.\n%s"
                    % r.stdout)
    out = load(h["target"])
    if "_provenance" in out:
        return fail(name, "the retired _provenance landed in settings.json.")
    if out.get("permissions", {}).get("additionalDirectories") != [extra]:
        return fail(name, "the companion's own list did not migrate.")
    if out.get("theme") != "dark":
        return fail(name, "a host key was lost.")
    if not os.path.isfile(h["snapshot"]) or load(h["snapshot"]) != load(
            REAL_SOURCE):
        return fail(name, "the snapshot was not written, or is not source.")
    retired = [f for f in os.listdir(d)
               if f.startswith("settings.local.json.retired-")]
    if os.path.exists(comp) or len(retired) != 1 or raw(
            os.path.join(d, retired[0])) != original:
        return fail(name, "the companion was not renamed with its bytes "
                    "intact.")
    v = run("verify", h["target"], source=REAL_SOURCE, manifest=REAL_MANIFEST,
            snapshot=h["snapshot"])
    if v.returncode != 0:
        return fail(name, "verify exited %d.\n%s" % (v.returncode, v.stderr))
    return ok(name, "the deploy succeeds, names the retired _provenance in one "
              "line and leaves it out, migrates the rest, writes the snapshot, "
              "renames the companion, and verify is clean.")


CASES = (case_golden, case_retired_removed_user_kept, case_changed_item,
         case_no_snapshot, case_skipped_release, case_host_list_item,
         case_two_pretooluse, case_optout_item_stays_gone, case_optout_single,
         case_unreadable_optout, case_shipped_example, case_same_item,
         case_migration, case_bad_companion, case_degradation,
         case_real_manifest, case_optout_shields_retired,
         case_companion_retired_path)


def main():
    if not os.path.isfile(SCRIPT):
        return fail("setup", "merge-settings.py not found at %s" % SCRIPT)
    tmp = tempfile.mkdtemp(prefix="settings-merge-fixture-")
    try:
        for case in CASES:
            try:
                case(tmp)
            except Exception as e:  # a crash is a failure, never a pass
                fail(case.__name__, "raised %r" % e)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("")
    if FAILURES:
        print("FAIL: %d failed, %d passed (%s)."
              % (len(FAILURES), len(PASSED), ", ".join(FAILURES)))
        return 1
    print("PASS: all %d cases." % len(PASSED))
    return 0


if __name__ == "__main__":
    sys.exit(main())
