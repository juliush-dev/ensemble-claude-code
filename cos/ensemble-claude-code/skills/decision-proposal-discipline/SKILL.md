---
name: decision-proposal-discipline
description: Make design, architecture, workflow, policy, operational, administrative, tool, stack, recommendation, and proposal decisions without anchoring on the current state or on an agent's earlier untested proposal. Use for nontrivial solution choices, process or governance design, provider/vendor/tool selection, concrete defaults, eligibility or scheduling rules, externally visible recommendations, or proposals that have propagated across multiple durable surfaces.
---

# Decision Proposal Discipline

## Overview

Use this skill when the shape of a decision matters. It combines neutral-first design, stack-choice neutrality, proposal re-testing, and auditable grounding for concrete choices.

In the Ensemble, this discipline is carried by the Examiner when forming recommendations for dispatch, and by the Concertmaster in designation dialogue and at architectural forks — the moments where an anchored proposal would propagate the furthest.

## Triggers

Invoke this skill when:

- Proposing a nontrivial design, architecture, data model, tool, framework, model, vendor, provider, policy, workflow, administrative procedure, documentation structure, research plan, or operational process.
- Choosing concrete values such as ports, timeouts, versions, schedules, defaults, paths, retry counts, polling intervals, thresholds, eligibility criteria, date windows, service tiers, review cadences, evidence standards, or handoff checkpoints.
- Carrying an earlier proposal into a spec, deliverable, policy, procedure, implementation, recommendation, or client-facing artifact.
- A proposal has been repeated into multiple durable surfaces.
- The user pushes back on one part of a proposal.

## Workflow

1. Name the decision or proposal explicitly.
2. Run a neutral pass first: describe the right solution if the current structure, workflow, document set, notebook geography, process, institution, implementation, or prior proposal did not exist.
3. Run the current-state pass: compare the ideal with the actual system, process, artifact, institution, constraints, commitments, and cost of change.
4. If the ideal and incremental paths differ, present both with the compromise named.
5. For stack, provider, vendor, tool, or process choices, compare candidates against the task's actual requirements. Treat familiarity and consistency as factors, not as automatic winners.
6. For concrete values or rule choices, record why the value is defensible. Use a traceable check, source, host or context probe, official requirement, or user-stated convention.
7. If a proposal has propagated, re-test it against actual commitments before propagating further.
8. Separate facts, assumptions, user preferences, and recommendations.

## Guardrails

- Do not let existing structure silently define the solution space.
- Do not let an earlier agent proposal become a commitment just because it was copied into several documents.
- Do not write ungrounded concrete values into load-bearing plans, specs, procedures, schedules, or recommendations.
- Do not smooth over the cost of choosing the ideal path versus the incremental path.
