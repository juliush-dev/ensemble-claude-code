---
name: ubiquitous-language-stewardship
description: Settle the shared vocabulary of a body of work so a term means the same thing across dialogue, notebooks, constitutions, and the shared external brain's canon. Use during designation dialogue or any settling dialogue where a new or protected term is being pinned down, when a term carries two meanings or two words carry one meaning, when a term contradicts the vocabulary canon or a constitution's bounds, when the vocabulary surface lags the work, or when a disputed term surfaces inside a dispatch.
provenance: pursuit formal-skills-promotion, agreed triage map contracts/2026-07-09-formal-skills-promotion/routes/triage-map/map.md, promoted 2026-07-09 on the user's word (deployed, footprint-verified 2026-07-09); source skills/formal/ubiquitous-language-stewardship/ (the team's own authored material, the designated-work door, not curation)
---

# Ubiquitous Language Stewardship

## Overview

The Ensemble treats protected vocabulary as load-bearing everywhere — members use the team's terms exactly, never approximated — but that duty presumes each term is already settled. This skill is the procedure for *settling* one: grill the language in the moment, resolve each term to a single agreed meaning, and land the resolution on the right durable surface without waiting to be asked. Names matter at design time. The terms a change is described with shape the notebooks that get written, the bounds that get relied on, and the later conversations that refer back — a term that lands vague, overloaded, or in tension with the existing vocabulary turns into rework and drift once the design hardens.

In the Ensemble this is a two-hand procedure. The **Concertmaster** runs the settling dialogue with the human — grilling, proposing canonical names, resolving conflicts — because term-settling lives at the shape's highest-leverage moments (designation dialogue, vocabulary locks, disputed terms in dispatches). The **Archivist** lands the resulting entry: canonizing a team-wide term into the shared external brain's vocabulary canon, or filing a standing lexical decision into a constitution's bounds, is Archivist work and dispatches. A capture line noting the lock is the Concertmaster's own hand; growing the canon around it is not.

Do the cheap environmental work before asking the human anything: read the vocabulary surfaces already present, then ask only the next question whose answer cannot be obtained from them.

## Triggers

Invoke this skill when:

- A term is being pinned down in **designation dialogue** — a new pursuit, tending, project, route, or the coinage of a name that the constitution or the shared canon will carry.
- A new domain term enters the dialogue and no vocabulary surface yet carries a clear definition of it.
- The same word is being used to mean two different things, or two different words for what looks like one concept.
- A term in the new design contradicts what the shared external brain's vocabulary canon, a constitution's bounds, or a live notebook already defines.
- The vocabulary surface lags the work — the canon or the bounds no longer match the terms in use.
- A **disputed term surfaces inside a dispatch** — a member and the Concertmaster, or two members' returns, are using a protected term in visibly different senses.

Do not invoke for every unfamiliar word in ordinary conversation. Use it when the term is doing designation, governance, classification, or shared-domain work. If the human is only asking what a word means, answer plainly and, if it is a settled protected term, retrieve the canon entry rather than running the full grilling.

## Workflow

1. **Scan the vocabulary surfaces first.** Start from what onboarding already read (the constitution's identity and bounds, the aim surface, the registry) and the retrieval rule's protected-term trigger — a protected term about to be used is settled against the vocabulary surface, not recall. Then do a targeted inventory: the shared external brain's vocabulary canon (the team's front-door vocabulary surface), the constitution's bounds (standing lexical decisions), the live notebooks and designations where the concept is already named, and any glossary the project keeps. Do not ask the human to point at these surfaces before making the pass.
2. **Build a small term ledger before questioning.** For each live term, note whether it is already defined, undefined, overloaded, contradicted, or merely an alias. Keep the ledger in working context unless a notebook surface should hold it; discard it at the stop unless it became durable knowledge (then it is a capture, landing per the menu).
3. **Ask only after the scan.** Grill one term at a time; ask the single question that most needs answering before the next step makes sense. If the answer is in a notebook, a constitution's bounds, the canon, or the artifact under discussion, read that source and report the finding instead of asking. When the answer is genuinely a human judgment, ask it plainly and wait.
4. **Test each term against three things:** the existing vocabulary surface, the actual artifact or committed rule it is supposed to name, and concrete edge scenarios where the term might break. This keeps the dialogue from becoming abstract wordsmithing. The goal is not a pretty name; it is a name whose meaning survives contact with the real work.
5. **Resolve conflicts explicitly.** When a term is overloaded, propose the precise canonical name and list the aliases to avoid. When the new use contradicts an existing definition, surface the contradiction directly and let the human pick a resolution rather than silently following either side. Where the meaning itself is what is unsettled — not just its name — this is felt-intent work: hand the dialogue to `felt-intent-extraction` to extract and bless the meaning first, then grill the term that names it.
6. **Capture as terms resolve.** The moment a term lands, run the menu scan (`rules/20-capture.md`) to place it: a team-wide protected term lands in the shared external brain's vocabulary canon (item 7); a standing lexical decision or constraint lands in the constitution's bounds (item 4); a vocabulary lock is itself a scan moment. Writing the capture line is the Concertmaster's own hand; canonizing into the brain or restructuring a constitution's bounds is Archivist work and dispatches. Do not wait for the human to say "save that."
7. **Record standing decisions at one authority only.** A lexical decision worth preserving — hard to reverse, surprising without future context, the result of real trade-offs — is a standing decision, and its home is the **constitution's bounds** (capture menu item 4). There is no second decision-record surface to maintain. When the choice between genuine alternatives needs disciplined framing before it is written, run `decision-proposal-discipline` first; then the bounds line records it.
8. **Sync the surrounding surfaces before moving on.** When a term is renamed, split, merged, or reclassified, this is consequence-complete editing: update the nearby notebooks, designations, registry lines, and any glossary where the old wording would now mislead, and report what co-moved. A rename is not done until the surfaces that speak about the term agree again. If a surface cannot be changed in the same slice, track it as required follow-up (a pending port or a Gaps entry), not optional polish.
9. **Close as a coherent slice.** After the settling dialogue settles, treat the vocabulary updates as their own logical slice under the commit obligation and pass-discipline's stop duty — an intention-revealing commit, not folded into an unrelated change. Where a resolved term reaches into a versioned or rule-governed external system, the settling assumption is a hypothesis until grounded: name the gap and nominate the Scout rather than letting it ride out of the dialogue unchecked.

## Glossary entry shape

When writing a term into a vocabulary surface (the shared canon, a constitution's bounds, or a project glossary), keep the entry tight:

- one bold term, one sentence that says what the term IS (not what it does);
- an "Avoid" line listing the aliases not to use, when aliases exist;
- a short relationships block when cardinality between this term and adjacent terms is non-obvious;
- a flagged-ambiguity note when the resolution closed a real conflict, so the next reader sees why this name won.

Do not pad the vocabulary with general concepts not specific to this body of work. A vocabulary surface carries the terms it is actually trying to ground, not whatever happened to appear in conversation.

## Guardrails

- Do not ask the human where the vocabulary canon, a constitution's bounds, or the notebooks live. Use what onboarding and the retrieval scan already found, or propose creating the vocabulary surface in this slice.
- Do not start by interviewing the human. Scan the surfaces first, then ask only the unresolved question that actually needs a judgment.
- Do not wait for an explicit save command. As soon as a term resolves, run the menu scan and land it in the same dialogue.
- Do not open a second decision-record authority. A standing lexical decision lands in the constitution's bounds; there is no parallel ADR surface to keep in sync.
- Do not settle the term before the meaning. When what the human means is itself unsettled, `felt-intent-extraction` leads and blesses the meaning; this skill grills the name once there is a blessed meaning to name.
- Do not pad the vocabulary with concepts not specific to this body of work.
- Do not fold vocabulary updates into an unrelated change. They are their own logical slice and their own commit.

## Related skills

- `felt-intent-extraction` extracts and blesses what the human means before any term can be grilled; enter this skill after the blessing, to settle the name.
- `decision-proposal-discipline` frames a lexical choice between genuine alternatives before the constitution's bounds record it.
- The capture rule (`rules/20-capture.md`) decides where a resolved term lands; the retrieval rule (`rules/30-retrieval.md`) makes the settled canon serve the next protected-term use.
- Grounding a term that reaches a versioned or rule-governed external system is Scout work under the amnesia doctrine (`rules/40-amnesia.md`); confirming that what a new term names is actually true of the artifact is the Examiner's.
