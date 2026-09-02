---
name: pass-discipline
description: Use at both ends of a pass — when starting work on a route (pickup) and when the pass ends (the stop). Carries the binding pickup read, the opening of the iteration record, and the stop duties that keep the route's notebook true and the pass's record frozen. Also carries the version-control boundary duties — branch placement at pickup, commit and branch disposition at the stop.
---

# Pass discipline — the two ends of a pass

An iteration is one pickup-to-stop push along a route, and its record file is the pass's own notebook: born at pickup, frozen at the stop. This runbook carries both ends. (Capture during the pass needs no runbook — the menu scan in the always-on rules carries it.)

## At pickup

1. **The binding read, before any work:** the route's `Handoff.md` (the thin designation at its head, then the current state and the pickup point), then `Gaps.md` (what is open in this route's scope), then recent iteration records latest-first, only as far as the handoff points. Pending ports staged on these surfaces resurface here — every pickup, until executed. A `LITTER-FLAG.md` in the route folder means a previous pass ended without its stop duties: settle that first (run the stop duties for the litter, remove the flag), then pick up.
2. **Branch placement, in a version-controlled tree:** before the first edit, judge on your own initiative whether this pass belongs on the branch currently checked out or warrants its own, and state the call you took with the pass's opening — the cut is bounded, reversible, and ungated, so it is yours to make and the human's to see, never a standing question put to him. Where the isolation wanted is a parallel working surface rather than a branch, the moment is a lane moment: read `operational-lane-discipline`.
3. **Open the book:** create `iterations/iteration-NN.md` (next number) the moment the pass begins, with the thin designation at its head — identity (pass number, date), aim (the pickup point taken), placement (the containing route), notebook (this record), bounds (one pickup-to-stop push) — and `status: open` in its frontmatter. The record is opened now, not written after the fact.

## During the pass

The always-on duties run: capture at scan moments, retrieve on the recall triggers. The record must not hold the route's current truth — that belongs in `Handoff.md` — and any effect meant to guide future work lands in a maintained surface, with the record naming where.

## At the stop

The stop is a fact — context exhausted, milestone landed, session ending — not an achievement. When it comes:

1. **Complete the record:** what the bounded pass did; **effects kept**, each named with the notebook surface it landed in, pending ports named; **verdict and stop-state** — where the route now stands, the next pickup point; **spawns linked** — any pursuit or tending the pass uncovered beyond its bounds. An empty-handed pass is still recorded.
2. **Evidence:** mint `iterations/iteration-NN-evidence/` only when proof cannot reasonably inline (command transcripts, hash checks, screenshots). Additive only; nothing converts or migrates.
3. **Update and prune the handoff:** `Handoff.md` reflects the new truth; what the pass resolved is pruned, not struck through. Same for `Gaps.md` entries the pass closed (with evidence) or opened.
4. **Try reachable ports:** execute pending ports whose destinations are reachable now; leave the rest named and visible on the maintained surfaces.
5. **Freeze:** flip the record's frontmatter to `status: frozen`. The record and its evidence are preserved evidence from this moment — never maintained again, never deleted.
6. **Commit and branch boundaries:** in a version-controlled tree, a coherent stop is a commit boundary; propose or make the commit per the project's gates. When the stop also ends the line of work the branch in play was cut for, put that branch's disposition to the human before the next work opens — merge it, keep it for slices still meant for it, park it, abandon it: which one holds turns on intent only he has, and a branch left undiscussed is work left in limbo.

Reusable tooling the pass produced belongs to the route or the body's home, never to a closed pass; one-shot pass tooling persists only as evidence of what ran.
