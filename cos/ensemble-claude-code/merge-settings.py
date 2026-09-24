#!/usr/bin/env python3
# merge-settings.py: the ONE settings merge both deploy scripts call.
#
# ASCII-ONLY FILE with LF line endings, deliberately: it is read and executed on
# both deploy paths, and the PowerShell 5.1 pipeline that carries it is
# ANSI-sensitive. Keep it pure ASCII, LF-only.
#
# THE PRINCIPLE. The factory ships defaults, not locks. The installed
# settings.json belongs to the user, who edits it directly. An update brings the
# factory's new items in without taking the user's out.
#
# THE MODEL. A path is a dotted key sequence down to a leaf of source
# settings.json: a scalar, a list, null, or an empty object. permissions.deny is
# one path, and so is modelSettings.claude-opus-5.effortLevel. The installed
# file is the base. On a deploy:
#
#   * A SINGLE VALUE the factory defines is written from the factory. A single
#     value the factory does not define is left alone.
#   * A LIST merges by adding. The installed items stay, in their order. Each
#     factory item the list does not already hold is appended at the end. A
#     factory item named in settings.optout.json is never added. An item the
#     factory shipped at the last deploy and has since retired is removed,
#     wherever it sits (THE SNAPSHOT, below). Nothing else in the list is
#     touched.
#   * A PATH the factory no longer declares is PRUNED when the snapshot shows
#     the last deploy shipped it, or settings-shipped.txt lists it. A retired
#     list path loses only the retired factory items; the host's own items
#     stay, and the key goes only if nothing is left in it.
#   * Every other key is left exactly as it stands.
#
# THE SAME ITEM. Two list items are the same only if they are equal as parsed
# JSON. Object key order and spacing do not matter. Strings compare exactly and
# case-sensitively, so entries differing only in case are different items. true
# is never 1, and 1 equals 1.0, JSON having one number type. Keys whose names
# begin with _provenance are left out of the comparison at any depth, so an
# annotated factory item and the same item without notes count as one. That
# prefix is factory-reserved by this rule: a host key borrowing it is ignored
# when items are compared. The retired PowerShell Merge-Json compared objects as
# text and collapsed two different hooks.PreToolUse entries into one, dropping
# the path guard. This test cannot do that. An installed item that equals a
# factory item is kept as the host has it, notes included; the factory's copy is
# not added beside it.
#
# THE SNAPSHOT. Removing a retired item needs to know what the factory shipped
# before. Each deploy saves the factory settings it applied, source
# settings.json as it stood, to factory-settings.last-deploy.json in the
# installed home. The next deploy reads it: the retired items of a list are the
# items in the snapshot's list that the current factory list lacks. An item
# that was in neither is never touched, so a home that skipped releases is
# measured against what it last received, not against releases it never saw.
# Claude Code does not read the file: the settings files it reads are managed
# settings, --settings, a project's .claude/settings.json and
# .claude/settings.local.json, and settings.json in the config home, and the
# launcher's --setting-sources user narrows that to the last one. The same holds
# for settings.optout.json. One edge is accepted by decision: a user item
# identical to a retired factory item is removed too, because from the file
# alone the two cannot be told apart.
#
#   * NO SNAPSHOT (the first deploy under this mechanism, or a new home): nothing
#     is removed as retired. The factory's items are added, the snapshot is
#     written, and the run says so in one line.
#   * AN UNREADABLE SNAPSHOT is treated the same way, with a warning, and
#     replaced by this deploy's.
#   * The snapshot is written only after settings.json is written and has passed
#     its verification. A failed deploy leaves the previous snapshot in place,
#     so the retry measures against what the home actually received.
#
# The retirement logic asks one question, through RetirementBasis: which items
# did the factory ship here last time? Nothing else in the merge knows where the
# answer comes from.
#
# settings-shipped.txt KEEPS ITS PATH-LEVEL ROLE and only that: the append-only
# list of every leaf path this COS has ever declared. It is what prunes a
# retired path on a home that has no snapshot yet, a home last deployed before
# snapshots existed. It lists paths, never list items.
#
# THE OPT-OUT FILE. settings.optout.json in the installed home, next to
# settings.json, shaped like the settings. Under a single-value path the key's
# presence is what counts (its value can be anything; true reads plainly): the
# installed value stays, even when the factory ships a new one, and stays absent
# if the host has none. Under a list path a list names the factory items to
# skip: never added, never removed as retired, and an installed copy is left
# where it is. An entry that matches nothing the factory ships now is reported
# on every run so it gets noticed. An opt-out file that exists but cannot be
# read stops the settings merge with settings.json untouched (exit 5), since
# ignoring it would overwrite the very values it protects.
#
# MIGRATION FROM settings.local.json. An earlier design kept host values in a
# companion file beside the deploy scripts. When --legacy-companion names one
# that exists, its contents move into the installed settings.json once, as if
# the user had written them there: its list items are added to the installed
# lists, and its single values are set, except a single value the factory
# defines, which the factory writes (the run names each such value, and says
# how to keep it). A single value on a path this run prunes as retired, or
# beneath one, is not migrated either: the prune would take it straight out
# again. Earlier releases shipped an example companion carrying _provenance,
# a path the factory has since retired, so a companion copied from it holds
# one. The run names each such value in one line. List
# items on a retired list path still migrate, since the prune takes only the
# factory's retired items from such a list and leaves the host's own. After
# the write verifies, the companion is renamed to
# settings.local.json.retired-<timestamp> beside itself, never deleted, and the
# run says so. A companion that cannot be parsed is neither merged nor renamed.
#
# EVERY LOSS IS NAMED BEFORE THE WRITE. One line per list item added, removed as
# retired, or skipped by opt-out; one per single value replaced; one per path
# pruned; one per host value that is not the shape the factory needs there.
#
# THE WRITE IS READ-MODIFY-WRITE, and nothing locks the host file between the
# two. A harness or an editor writing settings.json after this script reads it
# and before os.replace moves the merged text into place loses that write
# silently: last writer wins, and this script is the last writer. Deploy while
# no session is running. The deploy scripts' closing "restart any open session"
# notice is about a running session reading stale settings after the deploy,
# not about one writing during it.
#
# GRACEFUL DEGRADATION, on the skills-shipped.txt precedent. A missing manifest
# disables the manifest's prunes and touches nothing else. A manifest LINE that
# is a strict ancestor of a path the factory declares disables that one prune
# loudly. A retired list path whose earlier items are unknown (no snapshot) is
# kept whole, with a warning, rather than taking the host's own items with it.
# A host settings.json that is missing, unreadable, not valid JSON, or valid
# JSON that is not an object degrades to a wholesale write of the factory
# settings with a loud warning, never a throw that leaves a half-deployed home.
#
# PYTHON 3 IS A PREREQUISITE OF THE DEPLOY. The deploy scripts hold that line,
# not this file: without Python 3 they leave an existing host settings.json
# untouched and say so, every run. This script is what they cannot run there.
#
# KEY ORDER. Factory paths are emitted first, in source order, then whatever
# else the host carries, in host order. Inside a list the order is the merge's
# own: installed items first, new factory items after.
#
# USAGE
#   merge-settings.py merge  --source S --target T [--manifest M] [--optout O]
#                            [--snapshot P] [--legacy-companion C]
#   merge-settings.py verify --source S --target T [--manifest M] [--optout O]
#                            [--snapshot P]
#
# merge writes T, verifies it, then writes the snapshot P and retires C. verify
# only re-reads T and asserts: every factory single value not opted out equals
# source; every factory list item not opted out is present; no retired item and
# no pruned path is present. A standalone verify reads the snapshot from disk,
# so right after a deploy (the snapshot now equal to source) it finds no retired
# items to check; the merge's own verification, run before the snapshot is
# replaced, is the one that checks the removals.
#
# EXIT CODES: 0 fine (warnings may have been printed), 2 usage error,
# 3 verification failed, 4 the target could not be written, 5 the opt-out file
# could not be read (nothing was written).

import json
import os
import sys
import time

WARNED = []


def warn(msg):
    # Said once per run: a merge run computes its plan and then verifies, and a
    # warning printed twice reads as a second fault.
    if msg in WARNED:
        return
    WARNED.append(msg)
    sys.stderr.write("WARNING: " + msg + "\n")


def say(msg):
    sys.stdout.write(msg + "\n")


# --- the path primitive -----------------------------------------------------
# One get/set/delete by leaf path. Paths are dotted key sequences; a key
# containing a literal dot is ambiguous under this spelling and is warned about
# where the factory's paths are enumerated (no current key has one).

MISSING = object()


def path_get(node, parts):
    for p in parts:
        if not isinstance(node, dict) or p not in node:
            return MISSING
        node = node[p]
    return node


def path_set(node, parts, value):
    for p in parts[:-1]:
        nxt = node.get(p)
        if not isinstance(nxt, dict):
            nxt = {}
            node[p] = nxt
        node = nxt
    node[parts[-1]] = value


def path_delete(node, parts):
    # Delete the leaf, then every parent the deletion left empty.
    chain = []
    cur = node
    for p in parts[:-1]:
        if not isinstance(cur, dict) or p not in cur:
            return False
        chain.append((cur, p))
        cur = cur[p]
    if not isinstance(cur, dict) or parts[-1] not in cur:
        return False
    del cur[parts[-1]]
    for parent, key in reversed(chain):
        if isinstance(parent[key], dict) and not parent[key]:
            del parent[key]
        else:
            break
    return True


def leaf_paths(obj, prefix=()):
    # A leaf is anything that is not a non-empty object: scalars, lists, null,
    # and {} itself. Recursion stops there, which is what makes permissions.deny
    # one path rather than twelve.
    out = []
    if isinstance(obj, dict) and obj:
        for k, v in obj.items():
            out.extend(leaf_paths(v, prefix + (k,)))
    elif prefix:
        out.append(prefix)
    return out


def spell(parts):
    return ".".join(parts)


def without_notes(value):
    if isinstance(value, dict):
        return dict((k, without_notes(v)) for k, v in value.items()
                    if not is_note(k))
    if isinstance(value, list):
        return [without_notes(v) for v in value]
    return value


def brief(value, limit=160):
    # One line, short enough to read in a deploy log. A hook command can run to
    # several hundred characters; the point is to identify the entry. The
    # _provenance* notes inside an object are left out: they come first in the
    # factory's hook entries, would fill the line before the matcher and the
    # command, and play no part in which item it is.
    if value is MISSING:
        return "absent"
    s = json.dumps(without_notes(value), ensure_ascii=False)
    return s if len(s) <= limit else s[:limit] + "... (" + str(len(s)) + " chars)"


# --- the same item ----------------------------------------------------------


def is_note(key):
    return key.startswith("_provenance")


def same(a, b, notes_count=False):
    # Parsed-JSON equality. With notes_count False (the list-item test) every
    # _provenance* key is set aside at any depth.
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a == b
    if isinstance(a, str) and isinstance(b, str):
        return a == b
    if a is None or b is None:
        return a is None and b is None
    if isinstance(a, dict) and isinstance(b, dict):
        ka = set(k for k in a if notes_count or not is_note(k))
        kb = set(k for k in b if notes_count or not is_note(k))
        return ka == kb and all(same(a[k], b[k], notes_count) for k in ka)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(
            same(x, y, notes_count) for x, y in zip(a, b))
    return False


def holds(items, item):
    return any(same(x, item) for x in items)


# --- inputs -----------------------------------------------------------------


def read_json(path, what, required):
    # utf-8-sig everywhere: some Windows editors save a UTF-8 BOM, and
    # utf-8-sig reads plain UTF-8 unchanged.
    if not os.path.isfile(path):
        if required:
            sys.stderr.write("ERROR: %s not found at %s\n" % (what, path))
            sys.exit(2)
        return None, "absent"
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f), "ok"
    except (ValueError, OSError) as e:
        return None, str(e)


def read_manifest(path):
    # Same filter as skills-shipped.txt's readers: drop comment lines and
    # blanks, trim surrounding whitespace. A missing or unreadable manifest
    # disables its prunes and nothing else.
    if not path:
        return None
    if not os.path.isfile(path):
        warn("settings-shipped.txt not found at %s, so its prunes are disabled; "
             "a path this COS shipped and has since retired could linger on "
             "the host, but nothing host-added is at risk." % path)
        return None
    try:
        with open(path, encoding="utf-8-sig") as f:
            lines = f.read().splitlines()
    except OSError as e:
        warn("settings-shipped.txt could not be read (%s), so its prunes are "
             "disabled." % e)
        return None
    out = []
    for line in lines:
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        out.append(s)
    return out


def read_optout(path):
    # Absent: no opt-outs. Present but unusable: stop before writing anything,
    # because ignoring the file would overwrite exactly what it protects.
    if not path:
        return {}
    doc, st = read_json(path, "settings.optout.json", False)
    if st == "absent":
        return {}
    if doc is None or not isinstance(doc, dict):
        why = st if doc is None else "its top level is not a JSON object"
        sys.stderr.write(
            "ERROR: settings.optout.json at %s could not be used (%s). "
            "settings.json was NOT written: it is left exactly as it was, "
            "because applying the factory's settings without the opt-outs "
            "would overwrite the values they keep. Fix the file, or remove "
            "it, and run the deploy again.\n" % (path, why))
        sys.exit(5)
    return doc


# --- the retirement basis ---------------------------------------------------


class RetirementBasis(object):
    # What the factory shipped to this home at the last deploy, read from the
    # snapshot. doc is None when there is no usable snapshot: then nothing is
    # known to have been shipped before, and nothing is removed as retired.

    def __init__(self, doc):
        self.doc = doc

    def known(self):
        return self.doc is not None

    def previous_items(self, parts):
        # The items the last deploy's factory list held at this path. None
        # means unknown (no snapshot). A path the snapshot lacks, or held as a
        # single value, shipped no items: [].
        if self.doc is None:
            return None
        v = path_get(self.doc, parts)
        return v if isinstance(v, list) else []

    def previous_paths(self):
        return [] if self.doc is None else leaf_paths(self.doc)


def read_snapshot(path, quiet=False):
    if not path:
        return RetirementBasis(None)
    doc, st = read_json(path, "factory-settings.last-deploy.json", False)
    if st == "absent":
        if not quiet:
            say("settings.json: no snapshot of the factory settings an earlier "
                "deploy applied (%s), so nothing is removed as retired this "
                "run; this deploy writes one, and the next deploy measures "
                "against it." % os.path.basename(path))
        return RetirementBasis(None)
    if doc is None or not isinstance(doc, dict):
        warn("the snapshot %s could not be used (%s), so nothing is removed as "
             "retired this run. This deploy replaces it with the factory "
             "settings it applies." % (path, st if doc is None
                                       else "not a JSON object"))
        return RetirementBasis(None)
    return RetirementBasis(doc)


# --- what the factory declares, and what it retired -------------------------


def declared(source):
    order = leaf_paths(source)
    for parts in order:
        for key in parts:
            if "." in key:
                warn("declared key '%s' contains a literal dot, so the path "
                     "'%s' is ambiguous under dotted spelling and will not "
                     "round-trip through settings-shipped.txt. Rename the key, "
                     "or this path cannot be pruned later." % (key, spell(parts)))
    return order


def retired_paths(order, manifest, basis):
    # Paths the factory no longer declares that an earlier release did: from
    # the snapshot (the last deploy shipped it) and from the manifest (some
    # release ever shipped it). A candidate that is a strict ancestor of a
    # declared path is not a retired leaf at all; pruning it would delete the
    # host's whole subtree beneath it, so it is refused by name.
    declared_set = set(order)
    out = []
    candidates = [(p, "the snapshot") for p in basis.previous_paths()]
    if manifest is not None:
        candidates += [(tuple(l.split(".")), "settings-shipped.txt")
                       for l in manifest]
    for parts, where in candidates:
        if parts in declared_set or parts in out:
            continue
        below = [spell(d) for d in order
                 if len(d) > len(parts) and d[:len(parts)] == parts]
        if below:
            if where == "settings-shipped.txt":
                warn("settings-shipped.txt lists '%s', but the factory "
                     "declares %s beneath it. That line is not a retired leaf "
                     "path, and pruning it would delete the host's whole '%s' "
                     "subtree. Skipping that prune; list the leaf path instead."
                     % (spell(parts), ", ".join(below), spell(parts)))
            continue
        out.append(parts)
    if manifest is not None:
        # Self-policing, mirroring skills-shipped.txt: a declared path missing
        # from the manifest could not be pruned from a home without a snapshot
        # after a future retirement.
        listed = set(tuple(l.split(".")) for l in manifest)
        for parts in order:
            if parts not in listed:
                warn("settings-shipped.txt does not list '%s'; add it, or a "
                     "future retirement of that path cannot be pruned from a "
                     "home that has no snapshot." % spell(parts))
    return out


def optout_items(optout, parts):
    # The factory items an opt-out list names at a list path. None when the
    # entry is there but is not a list (reported by the stale pass).
    v = path_get(optout, parts)
    if v is MISSING:
        return []
    return v if isinstance(v, list) else None


# --- ordering ---------------------------------------------------------------


def order_tree(order):
    tree = {}
    for parts in order:
        node = tree
        for p in parts:
            node = node.setdefault(p, {})
    return tree


def reorder(node, tree):
    # Factory keys first, in source order; then the host's remaining keys in
    # the order the host file had them.
    if not isinstance(node, dict):
        return node
    out = {}
    for k, sub in tree.items():
        if k in node:
            out[k] = reorder(node[k], sub) if sub else node[k]
    for k, v in node.items():
        if k not in out:
            out[k] = v
    return out


# --- the plan ---------------------------------------------------------------


def pruned_at(parts, prunes, optout):
    # The retired path this run prunes at or above parts, or None. A retired
    # path the opt-out file names is kept, so it prunes nothing.
    for q in prunes:
        if parts[:len(q)] == q and path_get(optout, q) is MISSING:
            return q
    return None


def migrate(base, companion, source, optout, prunes, lines):
    # Apply the legacy companion once, as if the user had written it into the
    # installed file. Returns what must be true of the written file for the
    # companion to count as migrated: (parts, "item"|"value", value).
    expect = []
    for parts in leaf_paths(companion):
        v = path_get(companion, parts)
        p = spell(parts)
        cur = path_get(base, parts)
        q = pruned_at(parts, prunes, optout)
        if q is not None and (q != parts or not isinstance(v, list)):
            where = "" if q == parts else ", under %s," % spell(q)
            lines.append("  settings.json: settings.local.json carries %s%s a "
                         "path the factory retired; not migrated, the retired "
                         "companion still holds it." % (p, where or ","))
            continue
        if isinstance(v, list):
            if not isinstance(cur, list):
                if cur is not MISSING:
                    lines.append("  settings.json: the host's %s is not a list "
                                 "(it is %s); settings.local.json's list "
                                 "takes its place." % (p, brief(cur)))
                cur = []
                path_set(base, parts, cur)
            for x in v:
                expect.append((parts, "item", x))
                if not holds(cur, x):
                    cur.append(x)
                    lines.append("  settings.json: %s: adding %s from "
                                 "settings.local.json" % (p, brief(x)))
            continue
        fv = path_get(source, parts)
        if (fv is not MISSING and not isinstance(fv, list)
                and path_get(optout, parts) is MISSING):
            lines.append("  settings.json: settings.local.json sets %s to %s, "
                         "but the factory defines %s and writes its own value "
                         "(%s). To keep yours, set it in settings.json and name "
                         "it in settings.optout.json; the retired companion "
                         "still holds it." % (p, brief(v), p, brief(fv)))
            continue
        expect.append((parts, "value", v))
        if cur is MISSING or not same(cur, v, True):
            path_set(base, parts, v)
            lines.append("  settings.json: %s set to %s from "
                         "settings.local.json" % (p, brief(v)))
    return expect


def plan(host, source, optout, manifest, basis, companion=None):
    # The whole merge as a pure function over parsed inputs. Returns the result
    # tree, the before-the-write report lines, the tallies, what the companion
    # migration must leave behind, and the retired items per list path (for the
    # verification that follows the write).
    lines = []
    tally = {"added": 0, "retired": 0, "skipped": 0, "written": 0,
             "replaced": 0, "pruned": 0}
    base = json.loads(json.dumps(host))  # a copy; leave host as read
    # The prunes come first: the migration must know them, or it would set a
    # companion value the prune below takes out again, and expect it after.
    order = declared(source)
    prunes = retired_paths(order, manifest, basis)
    expect = []
    if companion:
        expect = migrate(base, companion, source, optout, prunes, lines)
    retired_at = {}

    # A host NON-OBJECT where the factory declares a path beneath it (a host
    # "permissions": "auto" against permissions.deny) is replaced by an object
    # when the path is set. Named here, because nothing below would see it.
    seen = set()
    for parts in order:
        for i in range(1, len(parts)):
            pre = parts[:i]
            node = path_get(base, pre)
            if node is MISSING or isinstance(node, dict):
                continue
            if pre not in seen:
                seen.add(pre)
                tally["replaced"] += 1
                lines.append("  settings.json: the host's %s is not an object "
                             "(it is %s) and the factory declares %s beneath "
                             "it; the host value goes and an object takes its "
                             "place." % (spell(pre), brief(node), spell(parts)))
            break

    for parts in order:
        want = path_get(source, parts)
        cur = path_get(base, parts)
        p = spell(parts)
        if isinstance(want, list):
            skip = optout_items(optout, parts) or []
            prev = basis.previous_items(parts)
            retired = ([x for x in prev if not holds(want, x)]
                       if prev is not None else [])
            retired_at[parts] = retired
            if cur is MISSING:
                items = []
            elif isinstance(cur, list):
                items = list(cur)
            else:
                tally["replaced"] += 1
                lines.append("  settings.json: the host's %s is not a list (it "
                             "is %s); the factory ships a list there, so the "
                             "host value goes." % (p, brief(cur)))
                items = []
            kept = []
            for x in items:
                if holds(retired, x) and not holds(skip, x):
                    tally["retired"] += 1
                    lines.append("  settings.json: %s: removing retired factory "
                                 "item %s" % (p, brief(x)))
                else:
                    kept.append(x)
            for f in want:
                if holds(kept, f):
                    continue
                if holds(skip, f):
                    tally["skipped"] += 1
                    lines.append("  settings.json: %s: skipping factory item %s "
                                 "(opted out in settings.optout.json)"
                                 % (p, brief(f)))
                    continue
                kept.append(f)
                tally["added"] += 1
                lines.append("  settings.json: %s: adding factory item %s"
                             % (p, brief(f)))
            if cur is not MISSING or kept:
                path_set(base, parts, kept)
            continue
        if path_get(optout, parts) is not MISSING:
            tally["skipped"] += 1
            lines.append("  settings.json: %s kept as this host has it, %s: "
                         "opted out in settings.optout.json; the factory ships "
                         "%s." % (p, brief(cur), brief(want)))
            continue
        if cur is MISSING:
            tally["written"] += 1
            lines.append("  settings.json: %s set to the factory's %s (new "
                         "here)." % (p, brief(want)))
        elif not same(cur, want, True):
            tally["replaced"] += 1
            lines.append("  settings.json: replacing host value at %s (host %s "
                         "-> factory %s)" % (p, brief(cur), brief(want)))
        path_set(base, parts, want)

    for parts in prunes:
        cur = path_get(base, parts)
        if cur is MISSING:
            continue
        p = spell(parts)
        if isinstance(cur, list):
            prev = basis.previous_items(parts)
            if prev is None:
                warn("%s is a list the factory no longer sets, but which of its "
                     "items the factory shipped here is unknown (no snapshot), "
                     "so the whole list is kept: removing it would take the "
                     "host's own items with it." % p)
                continue
            skip = optout_items(optout, parts) or []
            retired_at[parts] = prev
            kept = []
            for x in cur:
                if holds(prev, x) and not holds(skip, x):
                    tally["retired"] += 1
                    lines.append("  settings.json: %s: removing retired factory "
                                 "item %s" % (p, brief(x)))
                else:
                    kept.append(x)
            if kept:
                path_set(base, parts, kept)
            elif cur:
                path_delete(base, parts)
                tally["pruned"] += 1
                lines.append("  settings.json: %s held only retired factory "
                             "items, so the key goes too." % p)
            continue
        if path_get(optout, parts) is not MISSING:
            continue  # named in the stale pass: the opt-out keeps it
        tally["pruned"] += 1
        lines.append("  settings.json: pruning retired factory path %s (value "
                     "%s)" % (p, brief(cur)))
        path_delete(base, parts)

    lines.extend(stale_optouts(optout, source, order, prunes))
    result = reorder(base, order_tree(order))
    return result, lines, tally, expect, retired_at, prunes


def stale_optouts(optout, source, order, prunes):
    # Every opt-out entry that matches nothing the factory ships now, reported
    # on every run so a stale entry gets noticed.
    out = []
    declared_set = set(order)
    for q in leaf_paths(optout):
        p = spell(q)
        v = path_get(optout, q)
        if q in declared_set:
            want = path_get(source, q)
            if not isinstance(want, list):
                continue
            if not isinstance(v, list):
                out.append("  settings.optout.json: %s is a list setting, but "
                           "the entry is not a list of items (%s), so nothing "
                           "is skipped there. List the factory items to skip."
                           % (p, brief(v)))
                continue
            for x in v:
                if not holds(want, x):
                    out.append("  settings.optout.json: %s item %s matches no "
                               "item the factory ships now. It skips nothing; "
                               "if the factory shipped it before, it keeps this "
                               "host's copy from being removed as retired."
                               % (p, brief(x)))
        elif q in prunes:
            out.append("  settings.optout.json: the factory no longer sets %s. "
                       "The entry keeps this host's value from being removed as "
                       "retired; drop the entry and the next deploy removes the "
                       "key." % p)
        else:
            out.append("  settings.optout.json: %s matches nothing the factory "
                       "sets, so it keeps and skips nothing. Name a single value "
                       "or list the factory sets." % p)
    return out


# --- the check after the write ----------------------------------------------


def check(deployed, source, optout, retired_at, prunes, basis):
    failed = []
    for parts in declared(source):
        want = path_get(source, parts)
        got = path_get(deployed, parts)
        p = spell(parts)
        if isinstance(want, list):
            skip = optout_items(optout, parts) or []
            need = [f for f in want if not holds(skip, f)]
            if got is MISSING:
                if need:
                    failed.append("%s is absent from the deployed file" % p)
                continue
            if not isinstance(got, list):
                failed.append("%s is not a list in the deployed file" % p)
                continue
            for f in need:
                if not holds(got, f):
                    failed.append("%s lacks the factory item %s" % (p, brief(f)))
            for x in retired_at.get(parts, []):
                if holds(got, x) and not holds(skip, x):
                    failed.append("%s still holds the retired item %s"
                                  % (p, brief(x)))
            continue
        if path_get(optout, parts) is not MISSING:
            continue
        if got is MISSING:
            failed.append("%s is absent from the deployed file" % p)
        elif not same(got, want, True):
            failed.append("%s does not equal the factory value" % p)
    for parts in prunes:
        got = path_get(deployed, parts)
        if got is MISSING or path_get(optout, parts) is not MISSING:
            continue
        if isinstance(got, list):
            if basis.previous_items(parts) is None:
                continue  # kept whole by design; warned at the merge
            skip = optout_items(optout, parts) or []
            for x in retired_at.get(parts, []):
                if holds(got, x) and not holds(skip, x):
                    failed.append("%s still holds the retired item %s"
                                  % (spell(parts), brief(x)))
            continue
        failed.append("%s was to be pruned but is still present" % spell(parts))
    return failed


def check_migration(deployed, expect, retired_at):
    failed = []
    for parts, kind, v in expect:
        got = path_get(deployed, parts)
        if kind == "item":
            if holds(retired_at.get(parts, []), v):
                continue  # the accepted edge: equal to a retired factory item
            if not isinstance(got, list) or not holds(got, v):
                failed.append("%s lacks %s from settings.local.json"
                              % (spell(parts), brief(v)))
        elif got is MISSING or not same(got, v, True):
            failed.append("%s does not carry settings.local.json's value"
                          % spell(parts))
    return failed


# --- the acts ---------------------------------------------------------------


def write_atomic(path, text):
    # utf-8 without a BOM, written through a temp file and moved into place
    # with os.replace, which is atomic on POSIX and on Windows and overwrites an
    # existing target. The file is either the old one or the complete new one,
    # never truncated and never missing. os.remove-then-os.rename is what this
    # must never be: a rename failing after a successful remove would leave no
    # file at all.
    tmp = path + ".tmp.%d" % os.getpid()
    try:
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        os.replace(tmp, path)
    except OSError:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise


def retire_companion(path):
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = path + ".retired-" + stamp
    n = 1
    while os.path.exists(dest):
        dest = "%s.retired-%s-%d" % (path, stamp, n)
        n += 1
    try:
        os.rename(path, dest)
    except OSError as e:
        warn("settings.local.json was merged into the installed settings.json "
             "but could not be retired (%s). It stays at %s and is merged again "
             "on the next deploy; rename or remove it by hand." % (e, path))
        return
    say("settings.local.json: merged into the installed settings.json once and "
        "retired. It was renamed, not deleted: %s. Host values now live in the "
        "installed settings.json itself; settings.optout.example.md explains "
        "how to keep a value the factory also sets." % dest)


def do_merge(args):
    source, _ = read_json(args["source"], "source settings.json", True)
    if not isinstance(source, dict):
        sys.stderr.write("ERROR: source settings.json at %s is not a JSON "
                         "object.\n" % args["source"])
        return 2
    optout = read_optout(args["optout"])
    manifest = read_manifest(args["manifest"])
    basis = read_snapshot(args["snapshot"])

    companion = None
    comp_path = args["legacy-companion"]
    if comp_path and os.path.isfile(comp_path):
        companion, cs = read_json(comp_path, "settings.local.json", False)
        if companion is None or not isinstance(companion, dict):
            warn("settings.local.json at %s could not be parsed (%s), so it is "
                 "neither merged nor retired. Fix it and run the deploy again "
                 "to migrate it, or move its values into the installed "
                 "settings.json by hand and remove it."
                 % (comp_path, cs if companion is None else "not an object"))
            companion = None

    host, hs = read_json(args["target"], "host settings.json", False)
    if host is None or not isinstance(host, dict):
        if hs == "absent":
            say("settings.json: no host file yet; writing the factory set.")
        elif host is not None:
            warn("the host settings.json at %s is valid JSON but not a JSON "
                 "object (its top level is %s), so the factory settings are "
                 "written wholesale. There are no host keys to preserve in such "
                 "a file; the old content is replaced. Keep a copy first if it "
                 "mattered." % (args["target"], brief(host)))
        else:
            warn("the host settings.json at %s is unreadable or not valid JSON "
                 "(%s), so the factory settings are written wholesale. Host-only "
                 "keys in that file are NOT preserved; the old file is replaced. "
                 "Fix or remove it and re-run to get preservation back."
                 % (args["target"], hs))
        host = {}

    result, lines, tally, expect, retired_at, prunes = plan(
        host, source, optout, manifest, basis, companion)
    for line in lines:
        say(line)

    text = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    try:
        write_atomic(args["target"], text)
    except OSError as e:
        sys.stderr.write("ERROR: could not write %s (%s)\n" % (args["target"], e))
        return 4

    order = declared(source)
    kept = [k for k in result if k not in set(p[0] for p in order)]
    say("settings.json: %d list item(s) added, %d retired item(s) removed, %d "
        "skipped by opt-out, %d single value(s) newly set, %d host value(s) "
        "replaced, %d retired path(s) pruned, %d host-only top-level key(s) "
        "preserved%s."
        % (tally["added"], tally["retired"], tally["skipped"], tally["written"],
           tally["replaced"], tally["pruned"], len(kept),
           (" (" + ", ".join(kept) + ")") if kept else ""))

    deployed, ds = read_json(args["target"], "deployed settings.json", False)
    if not isinstance(deployed, dict):
        sys.stderr.write("VERIFY FAILED: the deployed settings.json at %s is "
                         "missing or unparseable (%s).\n" % (args["target"], ds))
        return 3
    failed = check(deployed, source, optout, retired_at, prunes, basis)
    if companion:
        failed += check_migration(deployed, expect, retired_at)
    if failed:
        sys.stderr.write("VERIFY FAILED on the deployed settings.json:\n")
        for f in failed:
            sys.stderr.write("  " + f + "\n")
        return 3
    say("settings.json verified: every factory value and item is in place "
        "except those opted out, and no retired item or path remains.")

    if args["snapshot"]:
        try:
            write_atomic(args["snapshot"],
                         json.dumps(source, indent=2, ensure_ascii=False) + "\n")
        except OSError as e:
            warn("the snapshot %s could not be written (%s). settings.json is "
                 "deployed and verified, but the next deploy measures retired "
                 "items against the older snapshot, or none." % (
                     args["snapshot"], e))
    if companion:
        retire_companion(comp_path)
    return 0


def do_verify(args):
    # The post-write assertion that replaces the hash check. Re-reads the
    # deployed file from disk, never an in-memory result.
    source, _ = read_json(args["source"], "source settings.json", True)
    optout = read_optout(args["optout"])
    manifest = read_manifest(args["manifest"])
    basis = read_snapshot(args["snapshot"], quiet=True)
    order = declared(source)
    prunes = retired_paths(order, manifest, basis)
    retired_at = {}
    for parts in order:
        want = path_get(source, parts)
        prev = basis.previous_items(parts)
        if isinstance(want, list) and prev is not None:
            retired_at[parts] = [x for x in prev if not holds(want, x)]
    for parts in prunes:
        prev = basis.previous_items(parts)
        if prev is not None:
            retired_at[parts] = prev
    deployed, ds = read_json(args["target"], "deployed settings.json", False)
    if not isinstance(deployed, dict):
        sys.stderr.write("VERIFY FAILED: the deployed settings.json at %s is "
                         "missing or unparseable (%s).\n" % (args["target"], ds))
        return 3
    failed = check(deployed, source, optout, retired_at, prunes, basis)
    if failed:
        sys.stderr.write("VERIFY FAILED on the deployed settings.json:\n")
        for f in failed:
            sys.stderr.write("  " + f + "\n")
        return 3
    say("settings.json verified: every factory value and item is in place "
        "except those opted out, and none of the %d retired path(s) remains."
        % len(prunes))
    return 0


USAGE = ("Usage: merge-settings.py {merge|verify} --source S --target T "
         "[--manifest M] [--optout O] [--snapshot P] [--legacy-companion C]")


def main(argv):
    if len(argv) < 2 or argv[1] not in ("merge", "verify"):
        sys.stderr.write(USAGE + "\n")
        return 2
    args = {"source": None, "target": None, "manifest": None, "optout": None,
            "snapshot": None, "legacy-companion": None}
    i = 2
    while i < len(argv):
        key = argv[i]
        if key.startswith("--") and key[2:] in args and i + 1 < len(argv):
            args[key[2:]] = argv[i + 1]
            i += 2
            continue
        sys.stderr.write("Unknown or incomplete argument: %s\n%s\n" % (key, USAGE))
        return 2
    if not args["source"] or not args["target"]:
        sys.stderr.write(USAGE + "\n")
        return 2
    if argv[1] == "merge":
        return do_merge(args)
    if args["legacy-companion"]:
        sys.stderr.write("--legacy-companion belongs to merge only.\n" + USAGE
                         + "\n")
        return 2
    return do_verify(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
