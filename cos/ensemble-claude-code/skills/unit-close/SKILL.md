---
name: unit-close
description: Use when a work unit ends — a pursuit discharges, a tending retires, a route retires or ends with its pursuit, a project dissolves. Carries the sweep rule (no unit closes with silent open gaps), the closing stamps, the registry update, and the freeze.
provenance: pursuit claude-code-cos-realization (contracts/2026-07-07-claude-code-cos-realization/)
---

# Unit close — nothing ends silently

When a unit ends, its notebook freezes into preserved evidence. This runbook is what must happen before that freeze, so nothing alive gets buried with it.

## The sweep rule — no unit closes with silent open gaps

Every still-open `Gaps.md` entry in the closing unit's scope must resolve, one of exactly four ways:

- **Closed with evidence** — the gap was handled; link the evidence.
- **Graduated** — it became its own work unit; name where it went (the designation and registry line).
- **Accepted** — a deliberate won't-fix; record the reason.
- **Ported** — it belongs to another project's aim or surface; execute the port or stage it as a named pending port on a surface that stays maintained (never inside the freezing notebook).

An open entry in a frozen notebook is a wish buried alive. The sweep is not optional triage; it is what closing means.

## The closing stamps

- **A pursuit closing stamps its still-live routes:** one line at the head of each such route's `Handoff.md` — "ended with the pursuit, DATE" — so a later reader of the tree learns it is over without visiting the pursuit. A route retired by decision while its pursuit continues gets its status flipped to `retired (reason)` instead.
- **Scoped tendings retire with their host:** a tending scoped to the closing unit retires automatically; record the retirement in its charter (status, reason: host closed). Spawned units live on — check the composition relation before assuming either way.

## The registry line

Update the unit's registry line in the parent's notebook: status (discharged / retired / dissolved), date, and — for a pursuit — the acceptance verdict with its evidence. Discharge claims rest on evidence, not assertion: if the acceptance was not verified, the honest status is not "discharged."

## The freeze

Last act: the unit's notebook freezes — never maintained again, never deleted. Iteration records flip to `status: frozen` if any were left open. From here the notebook is preserved evidence, feeding the parent's sharpening.
