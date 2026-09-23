#!/usr/bin/env python3
# run-fixture.py - the golden fixture for merge-settings.py.
#
# ASCII-ONLY, LF line endings, like everything else in this deploy set.
#
# Run it from anywhere:   python3 run-fixture.py
# Exit 0 PASS, exit 1 FAIL. It writes nothing outside a temp directory it
# removes on the way out, and it never touches a deployed home.
#
# CASE 1, THE GOLDEN CASE. It copies host.json to a scratch file, runs
# ../../merge-settings.py over the (host, source, companion, manifest)
# quadruple, and compares the written text BYTE FOR BYTE against expected.json -
# text, not parsed structure, because key order is part of what the merge
# promises. Then it runs the script's own verify mode over the result. Six
# claims ride on that one comparison:
#
#   1. THE MOTIVATING CASE. Host keys the factory never declares survive an
#      update: agentPushNotifEnabled, enabledPlugins, permissions.allow, the
#      host's own hooks.SessionEnd, and modelSettings.claude-fable-5-1 - which
#      lives INSIDE a factory-declared object and would die under top-level-key
#      granularity. A factory path the host lacks (remoteControlAtStartup)
#      arrives.
#   2. THE PRUNE. _provenance_retired is listed in the manifest, absent from
#      source, present on the host, and gone from the output.
#   3. THE COMPANION IS NOT A RESURRECTION CHANNEL. The host carries a
#      third additionalDirectories entry that the companion no longer lists. The
#      companion's array replaces the host's whole, so the stale entry goes. The
#      old merge concatenated, and the entry would have been immortal.
#   4. THE OBJECT-ARRAY CASE. Source's hooks.PreToolUse holds two distinct
#      objects. Both land. The retired PowerShell merge collapsed such an array
#      through Select-Object -Unique, which returns ONE entry for two distinct
#      PSCustomObjects - measured on the real source file, PowerShell 5.1: the
#      Edit|Write path guard was the entry lost.
#   5. KEY ORDER, at every depth. Declared paths first in source order, then the
#      companion's own, then the host's remaining keys in host order. This is
#      what the byte-for-byte compare buys over a parsed-structure compare, and
#      it is a promise in its own right: without it the deployed file's order
#      becomes host order and anyone diffing a host against source for drift
#      gets noise on every host.
#   6. NO BOM. The deployed file is UTF-8 without one, checked explicitly.
#
# Case 1 cannot reach the drop report's equivalence rule, and knowing why is
# part of reading it: its host hook entry is byte-equal to the factory's, so the
# report takes the "every host entry is in the factory's list too" branch and
# without_provenance() never decides anything. Case 7 exists for that rule.
#
# CASES 2 TO 6, THE DEGRADATION PATHS. Each builds its own scratch inputs and
# asserts on the exit code, the warning, and what the written file carries.
# These are the paths the golden case cannot reach and the paths a real host
# most easily falls into:
#
#   2. A MISSING MANIFEST disables pruning and touches nothing else. The retired
#      path survives on the host, and the run still succeeds.
#   3. NO COMPANION. Companion-only host paths are left exactly as they stand:
#      nothing declares them, so nothing rewrites them.
#   4. A CORRUPT HOST FILE (not valid JSON) degrades to a wholesale write with a
#      loud warning, never a throw.
#   5. A NON-OBJECT HOST FILE (valid JSON, top level an array) does the same,
#      and says so in those words rather than calling valid JSON invalid.
#   6. AN INCOHERENT MANIFEST LINE - one that is a strict ancestor of a declared
#      path - disables THAT prune, by name, and executes the rest. The host's
#      permissions.allow survives, which is the whole point: executing that line
#      would delete the subtree and then no verification could ever pass again.
#
# CASE 7, THE EQUIVALENCE RULE, on its own scratch inputs. The drop report
# compares effect rather than raw text, so a host entry the factory ships an
# annotated copy of is reported as replaced, not lost. Case 7 forces both sides
# of that rule in one run, on two declared paths: a host hook entry differing
# from the factory's only by a _provenance_* key, which must be reported as
# replaced-not-lost in those words, and a host permissions.deny entry differing
# by its content, which must still be named by name. A rule that called
# everything equivalent would pass the first assertion and fail the second.
#
# Also in case 1's output, by design rather than by accident: the host's
# hand-added permissions.deny entry is dropped, because the factory owns every
# path it declares and settings.local.json is the door for host values. The run
# prints that drop by name, which is the deploy's own before-the-write report.

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.normpath(os.path.join(HERE, "..", "..", "merge-settings.py"))
SOURCE = os.path.join(HERE, "source.json")
COMPANION = os.path.join(HERE, "companion.json")
MANIFEST = os.path.join(HERE, "manifest.txt")
HOST = os.path.join(HERE, "host.json")

FAILURES = []


def fail(case, msg):
    print("FAIL (%s): %s" % (case, msg))
    FAILURES.append(case)
    return 1


def run(mode, target, source=SOURCE, companion=COMPANION, manifest=MANIFEST,
        echo=False):
    args = [sys.executable, SCRIPT, mode, "--source", source,
            "--target", target]
    if companion:
        args += ["--companion", companion]
    if manifest:
        args += ["--manifest", manifest]
    r = subprocess.run(args, capture_output=True, text=True)
    if echo:
        print("--- %s ---" % mode)
        sys.stdout.write(r.stdout)
        sys.stderr.write(r.stderr)
    return r


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


# --- case 1: the golden case ------------------------------------------------


def case_golden(tmp):
    name = "case 1, golden"
    target = os.path.join(tmp, "golden.json")
    shutil.copyfile(HOST, target)
    for mode in ("merge", "verify"):
        r = run(mode, target, echo=True)
        if r.returncode != 0:
            return fail(name, "%s exited %d" % (mode, r.returncode))
    with open(target, "rb") as f:
        got = f.read()
    with open(os.path.join(HERE, "expected.json"), "rb") as f:
        want = f.read().replace(b"\r\n", b"\n")
    if got.startswith(b"\xef\xbb\xbf"):
        return fail(name, "the deployed file carries a UTF-8 BOM; it must not.")
    if got != want:
        gl = got.decode("utf-8").splitlines()
        wl = want.decode("utf-8").splitlines()
        for i in range(max(len(gl), len(wl))):
            g = gl[i] if i < len(gl) else "<no line>"
            w = wl[i] if i < len(wl) else "<no line>"
            if g != w:
                return fail(name, "line %d differs.\n  expected: %s\n  got:      %s"
                            % (i + 1, w, g))
        return fail(name, "output differs from expected.json in trailing bytes.")
    print("PASS (%s): merged output is byte-identical to expected.json, and the "
          "script's own verification passed over it." % name)
    return 0


# --- cases 2 to 6: the degradation paths ------------------------------------


def case_missing_manifest(tmp):
    name = "case 2, missing manifest"
    target = os.path.join(tmp, "no-manifest.json")
    shutil.copyfile(HOST, target)
    absent = os.path.join(tmp, "there-is-no-such-manifest.txt")
    r = run("merge", target, manifest=absent)
    if r.returncode != 0:
        return fail(name, "merge exited %d; a missing manifest must not fail "
                          "the deploy.\n%s" % (r.returncode, r.stderr))
    if "prune disabled" not in r.stderr:
        return fail(name, "no 'prune disabled' warning.\n%s" % r.stderr)
    out = load(target)
    if "_provenance_retired" not in out:
        return fail(name, "the retired path was pruned with no manifest to "
                          "gate it; the prune must be disabled entirely.")
    if out.get("model") != "opus":
        return fail(name, "declared paths did not land.")
    v = run("verify", target, manifest=absent)
    if v.returncode != 0:
        return fail(name, "verify exited %d.\n%s" % (v.returncode, v.stderr))
    print("PASS (%s): prune disabled with one warning, the retired path left on "
          "the host, everything else merged and verified." % name)
    return 0


def case_no_companion(tmp):
    name = "case 3, no companion"
    target = os.path.join(tmp, "no-companion.json")
    shutil.copyfile(HOST, target)
    r = run("merge", target, companion=None)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    out = load(target)
    host = load(HOST)
    got = out.get("permissions", {}).get("additionalDirectories")
    want = host["permissions"]["additionalDirectories"]
    if got != want:
        return fail(name, "a companion-only host path was rewritten with no "
                          "companion present.\n  expected: %s\n  got:      %s"
                          % (want, got))
    if out.get("model") != "opus":
        return fail(name, "declared paths did not land.")
    v = run("verify", target, companion=None)
    if v.returncode != 0:
        return fail(name, "verify exited %d.\n%s" % (v.returncode, v.stderr))
    print("PASS (%s): the host's own additionalDirectories survived untouched, "
          "the factory's paths landed and verified." % name)
    return 0


def _assert_wholesale(name, target):
    out = load(target)
    if "agentPushNotifEnabled" in out:
        return fail(name, "a host-only key survived a wholesale write; the "
                          "unreadable host file has no keys to preserve.")
    if out.get("model") != "opus":
        return fail(name, "declared paths did not land.")
    if out.get("permissions", {}).get("additionalDirectories") is None:
        return fail(name, "the companion's paths did not land.")
    return 0


def case_corrupt_host(tmp):
    name = "case 4, corrupt host file"
    target = os.path.join(tmp, "corrupt.json")
    write(target, "{ this is not json at all\n")
    r = run("merge", target)
    if r.returncode != 0:
        return fail(name, "merge exited %d; a corrupt host file must degrade, "
                          "not throw.\n%s" % (r.returncode, r.stderr))
    if "not valid JSON" not in r.stderr:
        return fail(name, "no 'not valid JSON' warning.\n%s" % r.stderr)
    if "(ok)" in r.stderr:
        return fail(name, "the warning interpolated the read status as '(ok)'.")
    if _assert_wholesale(name, target):
        return 1
    v = run("verify", target)
    if v.returncode != 0:
        return fail(name, "verify exited %d.\n%s" % (v.returncode, v.stderr))
    print("PASS (%s): degraded to a wholesale write with one warning, and the "
          "result verifies." % name)
    return 0


def case_non_object_host(tmp):
    name = "case 5, non-object host file"
    target = os.path.join(tmp, "non-object.json")
    write(target, "[1, 2, 3]\n")
    r = run("merge", target)
    if r.returncode != 0:
        return fail(name, "merge exited %d; a non-object host file must "
                          "degrade, not throw.\n%s" % (r.returncode, r.stderr))
    if "not a JSON object" not in r.stderr:
        return fail(name, "the warning does not name the real fault (valid "
                          "JSON, wrong shape).\n%s" % r.stderr)
    if "(ok)" in r.stderr:
        return fail(name, "the warning interpolated the read status as '(ok)'.")
    if _assert_wholesale(name, target):
        return 1
    v = run("verify", target)
    if v.returncode != 0:
        return fail(name, "verify exited %d.\n%s" % (v.returncode, v.stderr))
    print("PASS (%s): named as valid JSON of the wrong shape, degraded to a "
          "wholesale write, and the result verifies." % name)
    return 0


def case_ancestor_manifest_line(tmp):
    name = "case 6, incoherent manifest line"
    target = os.path.join(tmp, "ancestor.json")
    shutil.copyfile(HOST, target)
    bad = os.path.join(tmp, "manifest-with-ancestor.txt")
    with open(MANIFEST, encoding="utf-8") as f:
        write(bad, f.read().rstrip("\n") + "\npermissions\n")
    r = run("merge", target, manifest=bad)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    if "permissions" not in r.stderr or "Skipping that prune" not in r.stderr:
        return fail(name, "the ancestor line was not warned about by name.\n%s"
                    % r.stderr)
    out = load(target)
    if out.get("permissions", {}).get("allow") != ["Bash(ls)"]:
        return fail(name, "the host's permissions.allow did not survive; the "
                          "ancestor line was executed.")
    if "_provenance_retired" in out:
        return fail(name, "the coherent prune lines stopped working; one bad "
                          "line must disable only itself.")
    v = run("verify", target, manifest=bad)
    if v.returncode != 0:
        return fail(name, "verify exited %d - the state this guard exists to "
                          "prevent, where every later deploy fails.\n%s"
                    % (v.returncode, v.stderr))
    print("PASS (%s): the ancestor line warned by name and skipped, the host's "
          "subtree intact, the other prunes still working, verify clean." % name)
    return 0


# --- case 7: the equivalence rule in the drop report ------------------------


def case_provenance_equivalence(tmp):
    name = "case 7, provenance-only equivalence"
    # The rule under test is without_provenance() in merge-settings.py: the drop
    # report compares EFFECT, not raw text. Case 1 cannot reach it - its host
    # hook entry is byte-equal to the factory's, so every host entry is found in
    # the factory's list and the equivalence branch never runs. This case builds
    # inputs that force both branches at once, on two different declared paths:
    #
    #   hooks.PreToolUse - the host entry differs from the factory's by a
    #   _provenance_note key and nothing else. The report must say nothing is
    #   lost, and say WHY (the annotations set aside), rather than announce the
    #   host's hook as a casualty. This is the real-host false alarm the rule
    #   exists to kill: on the first run against the live home the report named
    #   the path guard and the compaction marker as losses, and neither was
    #   going anywhere.
    #
    #   permissions.deny - the host entry differs by its actual content. The
    #   rule must NOT swallow it: it is named, by name, before the write.
    #
    # Together they pin the rule from both sides. Without the second half a rule
    # that reported everything as equivalent would pass.
    shared_hooks = [{"type": "command", "command": "guard-push-gate.sh"}]
    source = {
        "hooks": {"PreToolUse": [{
            "matcher": "Bash|PowerShell",
            "hooks": shared_hooks,
            "_provenance_note": "factory narration; changes no behavior",
        }]},
        "permissions": {"deny": ["Edit(/agent-memory/**)"]},
    }
    host = {
        "hooks": {"PreToolUse": [{
            "matcher": "Bash|PowerShell",
            "hooks": shared_hooks,
        }]},
        "permissions": {"deny": ["Edit(/agent-memory/**)", "HostAdded(**)"]},
    }
    src = os.path.join(tmp, "equiv-source.json")
    target = os.path.join(tmp, "equiv-host.json")
    man = os.path.join(tmp, "equiv-manifest.txt")
    write(src, json.dumps(source, indent=2) + "\n")
    write(target, json.dumps(host, indent=2) + "\n")
    write(man, "hooks.PreToolUse\npermissions.deny\n")
    r = run("merge", target, source=src, companion=None, manifest=man)
    if r.returncode != 0:
        return fail(name, "merge exited %d.\n%s" % (r.returncode, r.stderr))
    if ("_provenance_* annotations are set aside" not in r.stdout
            or "nothing is lost" not in r.stdout):
        return fail(name, "the equivalence branch did not fire: a host entry "
                          "differing from the factory's only by a _provenance_* "
                          "key was not reported as replaced-not-lost.\n%s"
                    % r.stdout)
    if "HostAdded(**)" not in r.stdout:
        return fail(name, "a host entry with no factory equivalent was not "
                          "named by name; the equivalence rule is swallowing "
                          "real losses.\n%s" % r.stdout)
    out = load(target)
    if out["hooks"]["PreToolUse"] != source["hooks"]["PreToolUse"]:
        return fail(name, "the factory's annotated entry did not land whole.")
    if out["permissions"]["deny"] != ["Edit(/agent-memory/**)"]:
        return fail(name, "permissions.deny was not replaced from the factory.")
    v = run("verify", target, source=src, companion=None, manifest=man)
    if v.returncode != 0:
        return fail(name, "verify exited %d.\n%s" % (v.returncode, v.stderr))
    print("PASS (%s): the provenance-only difference reported as replaced, not "
          "lost; the real host entry still named by name; both paths written "
          "from the factory and verified." % name)
    return 0


CASES = (case_golden, case_missing_manifest, case_no_companion,
         case_corrupt_host, case_non_object_host, case_ancestor_manifest_line,
         case_provenance_equivalence)


def main():
    if not os.path.isfile(SCRIPT):
        return fail("setup", "merge-settings.py not found at %s" % SCRIPT)
    tmp = tempfile.mkdtemp(prefix="settings-merge-fixture-")
    try:
        for case in CASES:
            case(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("")
    if FAILURES:
        print("FAIL: %d of %d cases failed (%s)."
              % (len(FAILURES), len(CASES), ", ".join(FAILURES)))
        return 1
    print("PASS: all %d cases." % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
