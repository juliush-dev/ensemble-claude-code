#!/usr/bin/env python3
# merge-settings.py - the ONE settings merge both deploy scripts call.
#
# ASCII-ONLY FILE with LF line endings, deliberately: it is read and executed on
# both deploy paths, and the PowerShell 5.1 pipeline that carries it is
# ANSI-sensitive. Keep it pure ASCII, LF-only.
#
# WHAT IT REPLACES. Each deploy script used to carry its own merge - Merge-Json
# in the .ps1, an inline python block in the .sh - and each merged the
# factory-side companion (settings.local.json) into the SOURCE settings.json,
# then wrote the result over the host's file wholesale. Every key a host had
# added itself (a plugin toggle, a notification preference, a model entry the
# harness wrote) was dropped on every update. This script is the single
# implementation of the replacement, called by both scripts, so there is no
# second merge engine anywhere and no parity risk in a security-relevant path.
#
# THE MODEL. A "declared path" is a dotted path down to a leaf - a scalar, an
# array, null, or an empty object - in source settings.json, or in the host
# companion settings.local.json when one is present. permissions.deny is one
# path. modelSettings.claude-opus-5.effortLevel is one path. On a deploy:
#
#   * Every declared path is REPLACED in the host file with the declared value.
#     Never unioned: the factory must be able to retract an entry it once
#     shipped, and so must the companion. An array is one value, replaced whole.
#   * Every path listed in settings-shipped.txt that source-plus-companion no
#     longer declares is PRUNED from the host file - a path an earlier release
#     shipped and this one retired.
#   * Every other host key is left exactly as it stands.
#
# Host additions inside a factory-declared array (a /permissions deny rule added
# in a session, say) do not survive: the factory wins on the paths it declares,
# and settings.local.json is the durable door for host values. The script names
# every such entry by name before it writes, so the loss is announced rather
# than discovered. The report compares EFFECT, not raw text: a host entry the
# factory ships an annotated equivalent of (same content, a _provenance_* key
# more or less) is reported as replaced, never as lost. Without that rule the
# very first run on a real host announced the loss of its path guard and its
# compaction marker, neither of which was going anywhere. That rule assumes the
# _provenance prefix is FACTORY-RESERVED: it sets aside every key whose name
# begins with _provenance, at any depth, on both sides, so a host key called
# _provenanceMode that is not factory narration would be counted as equivalent
# and replaced under a report saying nothing was lost. The blast radius is the
# message and only the message - the merge writes the declared value and the
# verification compares the declared value either way, so no byte written ever
# depends on this rule.
#
# THE WRITE IS READ-MODIFY-WRITE, and nothing locks the host file between the
# two. A harness or an editor writing settings.json after this script reads it
# and before os.replace moves the merged text into place loses that write
# silently: last writer wins, and this script is the last writer. Deploy while
# no session is running. The deploy scripts' closing "restart any open session"
# notice does not cover this: it is about a running session reading stale
# settings after the deploy, not about one writing during it.
#
# GRACEFUL DEGRADATION, on the skills-shipped.txt precedent. A missing manifest
# disables pruning and touches nothing else. An incoherent manifest LINE - one
# that is a strict ancestor of a path the factory declares - disables that one
# prune loudly and leaves the rest working. A host settings.json that is
# missing, unreadable, not valid JSON, or valid JSON that is not an object
# degrades to the old wholesale write (source plus companion, nothing
# preserved) with a loud warning - never a throw that leaves a half-deployed
# home.
#
# PYTHON 3 IS A PREREQUISITE OF THE DEPLOY. The deploy scripts hold that line,
# not this file: without Python 3 they leave an existing host settings.json
# untouched and say so, every run. This script is what they cannot run there.
#
# KEY ORDER. Declared paths are emitted first, in source order, then the
# companion's own paths, then whatever else the host carries, in host order. A
# deliberate choice: without it the deployed file's order becomes host order and
# anyone diffing a host against source for drift gets noise on every host.
#
# USAGE
#   merge-settings.py merge  --source S --target T [--companion C] [--manifest M]
#   merge-settings.py verify --source S --target T [--companion C] [--manifest M]
#
# merge writes T, then verifies it. verify only re-reads T and asserts: every
# declared path equals source-plus-companion's value, every pruned path is gone.
# It is the deploy scripts' integrity check for settings.json, which a hash
# check can no longer be - the deployed file legitimately depends on host state,
# so byte-comparing it against source or against the merged text fails on any
# host carrying a key of its own.
#
# EXIT CODES: 0 fine (warnings may have been printed), 2 usage error,
# 3 verification failed, 4 the target could not be written.

import json
import os
import sys

WARNED = []


def warn(msg):
    # Said once per run. compute() is called twice in a merge run (the merge
    # itself, then the verification that follows it), and printing every
    # manifest warning twice made the second copy read as a second fault.
    if msg in WARNED:
        return
    WARNED.append(msg)
    sys.stderr.write("WARNING: " + msg + "\n")


def say(msg):
    sys.stdout.write(msg + "\n")


# --- the path primitive -----------------------------------------------------
# One get/set/delete by leaf path, used by the merge, the prune, the drop
# report and the verification alike. Paths are dotted key sequences; a key
# containing a literal dot is ambiguous under this spelling and is warned about
# where the paths are enumerated (no current key has one).

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
    # A leaf is anything that is not a non-empty object: scalars, arrays, null,
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


# --- inputs -----------------------------------------------------------------


def read_json(path, what, required):
    # utf-8-sig everywhere: some Windows editors save a UTF-8 BOM (the host
    # companion carries one today), and utf-8-sig reads plain UTF-8 unchanged.
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
    # disables pruning and nothing else.
    if not path:
        return None
    if not os.path.isfile(path):
        warn("settings-shipped.txt not found at %s - prune disabled; a path this "
             "COS shipped and has since retired would linger on the host, but "
             "nothing host-added is at risk." % path)
        return None
    try:
        with open(path, encoding="utf-8-sig") as f:
            lines = f.read().splitlines()
    except OSError as e:
        warn("settings-shipped.txt could not be read (%s) - prune disabled." % e)
        return None
    out = []
    for line in lines:
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        out.append(s)
    return out


def declared_set(source, companion):
    # Declared paths in emission order: source's own, in source order, then the
    # companion's own, in companion order. Value: the companion's where it
    # declares the path, source's otherwise - the companion replaces, never
    # unions, which is what kills the old concatenating branch.
    order = []
    values = {}
    for parts in leaf_paths(source):
        order.append(parts)
        values[parts] = path_get(source, parts)
    if companion:
        for parts in leaf_paths(companion):
            if parts not in values:
                order.append(parts)
            values[parts] = path_get(companion, parts)
    for parts in order:
        for key in parts:
            if "." in key:
                warn("declared key '%s' contains a literal dot, so the path "
                     "'%s' is ambiguous under dotted spelling - it will not "
                     "round-trip through settings-shipped.txt. Rename the key, "
                     "or this path cannot be pruned later." % (key, spell(parts)))
    return order, values


# --- ordering ---------------------------------------------------------------


def order_tree(order):
    tree = {}
    for parts in order:
        node = tree
        for p in parts:
            node = node.setdefault(p, {})
    return tree


def reorder(node, tree):
    # Declared keys first, in declared order; then the host's remaining keys in
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


# --- the report of what is about to be dropped ------------------------------


def brief(value, limit=160):
    # One line, short enough to read in a deploy log. A hook command can run to
    # several hundred characters; the point is to identify the entry, not to
    # reprint it.
    s = json.dumps(value, ensure_ascii=False)
    return s if len(s) <= limit else s[:limit] + "... (" + str(len(s)) + " chars)"


def without_provenance(value):
    # The same value with every _provenance* key removed, at any depth. The
    # factory annotates some of its own settings entries with a _provenance_*
    # key; a host's deployed copy of the same entry may carry the annotation or
    # not, depending on which release wrote it. Those keys change no behavior,
    # so two entries that differ only in them have the same EFFECT, and calling
    # one the loss of the other is a false alarm - which is exactly what the
    # drop report used to raise on the path guard and the compaction marker, the
    # two entries this COS most needs to be trusted about. The _provenance
    # prefix is factory-reserved by this rule; see the header for what a host
    # key borrowing it would cost (a wrong line in the report, never a wrong
    # byte on disk).
    if isinstance(value, dict):
        return dict((k, without_provenance(v)) for k, v in value.items()
                    if not k.startswith("_provenance"))
    if isinstance(value, list):
        return [without_provenance(v) for v in value]
    return value


def report_clobbered_parents(host, order):
    # The case the per-path loop below cannot see: the host carries a
    # NON-OBJECT where the factory declares a path beneath it (a host
    # "permissions": "auto" against the declared permissions.deny). path_set
    # replaces such a node with an object, so the host value goes; without this
    # line it would go unannounced, because path_get returns MISSING for a path
    # under it and the loop below skips it.
    clobbered = 0
    seen = set()
    for parts in order:
        for i in range(1, len(parts)):
            pre = parts[:i]
            node = path_get(host, pre)
            if node is MISSING or isinstance(node, dict):
                continue
            if pre not in seen:
                seen.add(pre)
                clobbered += 1
                say("  settings.json: the host's %s is not an object (it is %s) "
                    "and the factory declares %s beneath it - the host value goes "
                    "and an object takes its place."
                    % (spell(pre), brief(node), spell(parts)))
            break
    return clobbered


def report_drops(host, order, values, prunes):
    # Name, by name, every host entry about to disappear, BEFORE the write.
    dropped = report_clobbered_parents(host, order)
    for parts in order:
        cur = path_get(host, parts)
        if cur is MISSING:
            continue
        new = values[parts]
        if cur == new:
            continue
        p = spell(parts)
        if isinstance(cur, list) and isinstance(new, list):
            # Compare EFFECT, not raw text. A host entry the factory ships an
            # annotated equivalent of is replaced, not lost, and saying so is
            # the difference between a report worth reading and one that cries
            # wolf on its first run.
            effects = [without_provenance(y) for y in new]
            lost = []
            equivalent = 0
            for x in cur:
                if x in new:
                    continue
                if without_provenance(x) in effects:
                    equivalent += 1
                    continue
                lost.append(x)
            if lost:
                say("  settings.json: %s is replaced whole from the factory. "
                    "These host entries have no factory equivalent and go:" % p)
                for x in lost:
                    say("      " + brief(x))
                dropped += len(lost)
                if equivalent:
                    say("      (%d further host entry(s) carry a factory "
                        "equivalent and are replaced by it, not lost.)"
                        % equivalent)
            elif equivalent:
                say("  settings.json: %s is replaced whole from the factory; "
                    "every host entry is carried over or replaced with the "
                    "factory's equivalent (%d of them identical once the "
                    "factory's own _provenance_* annotations are set aside), so "
                    "nothing is lost." % (p, equivalent))
            else:
                say("  settings.json: %s is replaced whole from the factory; "
                    "every host entry is in the factory's list too, so nothing "
                    "is lost." % p)
        else:
            say("  settings.json: replacing host value at %s (host %s -> factory %s)"
                % (p, brief(cur), brief(new)))
            dropped += 1
    for parts in prunes:
        cur = path_get(host, parts)
        if cur is MISSING:
            continue
        say("  settings.json: pruning retired factory path %s (value %s)"
            % (spell(parts), brief(cur)))
        dropped += 1
    if dropped:
        say("  settings.json: %d host value(s) above give way to the factory's. "
            "settings.local.json beside the deploy script is the durable door - "
            "anything put there is re-applied on every update." % dropped)
    return dropped


# --- the three acts ---------------------------------------------------------


def compute(source, companion, manifest):
    order, values = declared_set(source, companion)
    declared = set(order)
    prunes = []
    if manifest is not None:
        for line in manifest:
            parts = tuple(line.split("."))
            if parts in declared:
                continue
            # Graceful degradation again: an incoherent manifest line
            # disables ITS prune, loudly, rather than executing it. A line that
            # is a strict ancestor of a declared path (permissions listed while
            # source declares permissions.deny) is not a retired path at all -
            # pruning it would delete the host's whole subtree beneath it,
            # permissions.allow and additionalDirectories with it, and the
            # verification below could then never pass, so every later deploy
            # would exit 3 with nothing pointing at the manifest as the cause.
            below = [spell(d) for d in order
                     if len(d) > len(parts) and d[:len(parts)] == parts]
            if below:
                warn("settings-shipped.txt lists '%s', but the factory declares "
                     "%s beneath it. That line is not a retired leaf path - "
                     "pruning it would delete the host's whole '%s' subtree. "
                     "Skipping that prune; list the leaf path instead."
                     % (line, ", ".join(below), line))
                continue
            prunes.append(parts)
        # Self-policing, mirroring skills-shipped.txt: a source-declared path
        # missing from the manifest could never be pruned after a future
        # retirement, because the prune gate would never see it. Companion
        # paths are host-side and deliberately not listed - the manifest is a
        # tracked factory file.
        listed = set(tuple(l.split(".")) for l in manifest)
        for parts in leaf_paths(source):
            if parts not in listed:
                warn("settings-shipped.txt does not list '%s' - add it, or a "
                     "future retirement of that path cannot be pruned."
                     % spell(parts))
    return order, values, prunes


def do_merge(args):
    source, st = read_json(args["source"], "source settings.json", True)
    companion = None
    if args["companion"]:
        companion, cs = read_json(args["companion"], "settings.local.json", False)
        if companion is None and cs != "absent":
            warn("settings.local.json at %s could not be parsed (%s) - deploying "
                 "without it; host-specific values in it are NOT applied."
                 % (args["companion"], cs))
    manifest = read_manifest(args["manifest"])

    host, hs = read_json(args["target"], "host settings.json", False)
    if host is None or not isinstance(host, dict):
        if hs == "absent":
            say("settings.json: no host file yet - writing the factory set.")
        elif host is not None:
            # Parsed fine, but the top level is not an object (an array, a
            # string, a number). hs is "ok" here, so quoting it would print the
            # nonsense "not valid JSON (ok)".
            warn("the host settings.json at %s is valid JSON but not a JSON "
                 "object (its top level is %s) - falling back to a wholesale "
                 "write of the factory settings. There are no host keys to "
                 "preserve in such a file; the old content is replaced. Keep a "
                 "copy first if it mattered." % (args["target"], brief(host)))
        else:
            warn("the host settings.json at %s is unreadable or not valid JSON "
                 "(%s) - falling back to a wholesale write of the factory "
                 "settings. Host-only keys in that file are NOT preserved; the "
                 "old file is replaced. Fix or remove it and re-run to get "
                 "preservation back." % (args["target"], hs))
        host = {}

    order, values, prunes = compute(source, companion, manifest)
    report_drops(host, order, values, prunes)

    result = json.loads(json.dumps(host))  # work on a copy, leave host as read
    for parts in prunes:
        path_delete(result, parts)
    for parts in order:
        path_set(result, parts, values[parts])
    result = reorder(result, order_tree(order))

    text = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    tmp = args["target"] + ".tmp.%d" % os.getpid()
    try:
        # utf-8 without a BOM, written through a temp file and moved into place
        # with os.replace, which is atomic on POSIX and on Windows and overwrites
        # an existing target. So the host keeps either its old settings.json or
        # the complete new one, never a truncated file and never no file at all.
        # os.remove-then-os.rename is what this must never be: a rename failing
        # after a successful remove would leave the host with no settings.json,
        # and the handler below would delete the temp carrying the merged text.
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        os.replace(tmp, args["target"])
    except OSError as e:
        try:
            os.remove(tmp)
        except OSError:
            pass
        sys.stderr.write("ERROR: could not write %s (%s)\n" % (args["target"], e))
        sys.exit(4)

    kept = [k for k in result if k not in set(p[0] for p in order)]
    # The retired count says "N of M" deliberately: N is what this host actually
    # carried and lost, M is what the manifest retires. Reporting only N left
    # "0 retired path(s) pruned" next to the verification's "all 1 retired
    # path(s) are gone", two true lines that read as a contradiction.
    removed = sum(1 for p in prunes if path_get(host, p) is not MISSING)
    say("settings.json: %d factory-declared path(s) written, %d retired path(s) "
        "removed of the %d the manifest retires, %d host-only top-level key(s) "
        "preserved%s."
        % (len(order), removed, len(prunes), len(kept),
           (" (" + ", ".join(kept) + ")") if kept else ""))
    return do_verify(args, quiet=False)


def do_verify(args, quiet=False):
    # The post-write assertion that replaces the hash check.
    # Re-reads the deployed file from disk - never the in-memory result - and
    # checks the two things the merge claims.
    source, _ = read_json(args["source"], "source settings.json", True)
    companion = None
    if args["companion"]:
        companion, _ = read_json(args["companion"], "settings.local.json", False)
    manifest = read_manifest(args["manifest"])
    order, values, prunes = compute(source, companion, manifest)

    host, hs = read_json(args["target"], "deployed settings.json", False)
    if host is None:
        sys.stderr.write("VERIFY FAILED: the deployed settings.json at %s is "
                         "missing or unparseable (%s).\n" % (args["target"], hs))
        sys.exit(3)

    failed = []
    for parts in order:
        got = path_get(host, parts)
        if got is MISSING:
            failed.append("%s is absent from the deployed file" % spell(parts))
        elif got != values[parts]:
            failed.append("%s does not equal the factory value" % spell(parts))
    for parts in prunes:
        if path_get(host, parts) is not MISSING:
            failed.append("%s was to be pruned but is still present" % spell(parts))
    if failed:
        sys.stderr.write("VERIFY FAILED on the deployed settings.json:\n")
        for f in failed:
            sys.stderr.write("  " + f + "\n")
        sys.exit(3)
    if not quiet:
        say("settings.json verified: all %d declared path(s) equal "
            "source%s, and none of the %d retired path(s) is present."
            % (len(order), "-plus-companion" if companion else "", len(prunes)))
    return 0


USAGE = ("Usage: merge-settings.py {merge|verify} --source S --target T "
         "[--companion C] [--manifest M]")


def main(argv):
    if len(argv) < 2 or argv[1] not in ("merge", "verify"):
        sys.stderr.write(USAGE + "\n")
        return 2
    args = {"source": None, "target": None, "companion": None, "manifest": None}
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
    return do_verify(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
