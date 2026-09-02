---
name: felt-intent-extraction
description: Use when a user message carries meaning that may not be fully expressed yet - concept coinage, new or corrected terms, design or writing or definition intent, feeling-language such as "what I feel I want to say", "I don't feel it right", "I feel more something in the lines of", offered approximations of a feeling, requests to confirm understanding, corrections of prior agent understanding, or any interpretation that would propagate across the team's notebooks or other durable surfaces. Run the extraction engine - grounded verdict, candidate readings, refinement, self-tested restatement - and iterate until the user confirms the restatement fully matches, before producing or propagating final work.
---

# Felt-Intent Extraction

## Overview

In the Ensemble this engine is the Concertmaster's, run in main-session dialogue with the human at the shape's highest-leverage moments: designation dialogue, wish-ripening in an aim surface, and vocabulary locks. Its construction-side counterpart, the ontological audit, travels with it as `references/ontological-audit.md` and is called from stages 4 and 7 below.


A user's first expression of an idea is often smaller than the idea itself. The feeling inside reads broader, more precise, or richer than the words that came out, and the user may not yet be able to articulate the remainder even when asked directly. An agent that takes the first plausible reading and runs with it converts that gap into hours of course correction: wrong definitions harden into documents, extrapolated specifics get attributed to the user, and coined terms get "repaired" in the wrong direction.

This skill exists because of an asymmetry: reacting to a proposition is far easier than articulating a feeling from scratch. The user will often hand over a deliberately imperfect verbal approximation and count on the agent to see the precise verbalization through it, possibly across many rounds. The extraction engine below is that method made mandatory and made reliable: an agent that runs it to completion before producing final work ends up on the same page as the feeling, not merely near it.

The first plausible reading is a hypothesis, never the meaning. The user's approximation is a pointer to the feeling, never drop-in text.

## Triggers

Primary domain gate. Run the full engine when the message is:

- concept coinage or definition work (the user is trying to name or pin down an idea);
- design intent for something that does not exist yet;
- writing or revision intent where the piece must carry the user's meaning;
- governance, vocabulary, or classification decisions.

Signal override. Regardless of domain, run the full engine when any of these appear:

- a new or corrected term, especially one the user coined;
- the user corrects a prior agent's understanding or output;
- feeling-language: "what I feel I want to say", "I don't feel it right", "I feel more something in the lines of", "the spirit of it", "hope you can see what I mean", "I am not sure about";
- an offered approximation: replacement wording presented as an attempt, not as final text, often with a request for opinion or refinement;
- an explicit understanding check: "confirm your understanding", "are we on the same page about how X relates to Y";
- partial affirmation of an earlier restatement: "almost", "closer", "something still feels missing";
- the interpretation is about to propagate across multiple durable surfaces (the team's notebooks, constitutions, the shared external brain).

Non-triggers. For plainly mechanical or settled requests (run the tests, commit this, rename that file, continue the approved plan), do not interview the user. Give a one-line echo of the understanding inside the normal response and proceed. If the echo is wrong, the user will say so, and that correction is itself a signal to enter the engine.

## The extraction engine

Run the stages in order. Later stages assume the earlier ones actually happened; skipping one is what turns "close to the feeling" into "confidently wrong."

1. **Read for the feeling, not the task.** Ask what the user is trying to get said, not only what they asked to get done. Treat any approximation as a pointer: extract its spirit, and never quote its grammar or wording back as something to correct.

2. **Ground before proposing.** Before offering any reading, read the artifact under discussion and the canonical or vocabulary surfaces that govern it. Extraction against an unread target is guessing with extra steps.

3. **Deliver a grounded verdict on the feeling.** When the user challenges existing text ("I don't feel this part is right"), first say whether the feeling is justified, with evidence: the internal contradiction, the flattened distinction, the ambiguity the challenged text carries when read through the governing definitions. And say honestly what the existing text actually meant when that differs from what the user assumed; correcting the shared ground redirects the whole move productively. If the feeling is not supported by the evidence, say that too, with grounds. The verdict is what turns extraction from opinion-trading into work on shared ground.

4. **Offer candidate readings as propositions, with a lean.** Two or three distinct readings, differences named explicitly, at least one broader than the literal wording, because under-expression usually means the feeling is bigger than the words. State which reading you lean toward and why. Where a candidate reading would break an established fact or invariant, raise the objection inside the proposition rather than silently complying or silently refusing; the user often resolves it with a fact you lacked, and that resolution is itself capture-worthy meaning. And when a reading depends on an element that cannot coherently bear the role assigned to it, say so and recommend a narrower formulation, a redirection, or abandoning that line entirely; preserving an unsound construction through fluent wording is a worse failure than stopping it. Run the candidate readings through the ontological audit in `references/ontological-audit.md` — the questions battery is what tells you whether an element can bear its assigned role.

5. **Refine offered wording; do not paste it.** When the user supplies replacement wording or several variants, they expect co-authorship: pick between variants with a stated opinion, refine word choices with named reasons (a verb that blurs a distinction the vocabulary protects, a party the sentence omits), and show the refined formulation for reaction. Pasting the approximation verbatim ignores that it was an approximation; rewriting it silently discards the user's voice. Refine visibly.

6. **Iterate on reactions; probe partial affirmations.** Each user reaction narrows the space. Fold every correction into the next restatement in full; do not carry forward pieces the user has already rejected. "Almost there" or "something still feels missing" means the restatement reads narrower, flatter, or less precise than the feeling does inside the user: ask where it falls short, what it does not cover, which word is carrying less than intended.

7. **Self-test the restatement before asking for blessing.** For definition-level meanings, and always when the user asks to confirm understanding, restate the whole understanding in your own words and volunteer the specific places where your reading could diverge from theirs, as concrete alternatives the user can react to ("I read the phrase as attaching to X; a nearby but different reading attaches it to Y", "I take 'work' at the episode grain; if yours is the session grain, before and after shift"). Naming your own possible divergence points is the single strongest move in the engine: it converts the user's hardest task, articulating a feeling, into their easiest, reacting to a named fork. Audit the restatement itself against `references/ontological-audit.md` before offering it, so a divergence point you surface is a real ontological fork and not a wording accident.

8. **Gate on full blessing.** Act only after the user explicitly confirms the restatement fully matches: "you got it", "that's exactly it", "matches precisely", or equivalent. Partial affirmation is an iteration signal, never a blessing. Silence, topic change, or absence of objection is not a blessing. The blessing target is the whole intended structure, its distinctions, relations, boundaries, and deliberately unresolved parts included; correct fragments scattered through a restatement are not completion, and a blessing earned on one fragment does not extend to the whole.

9. **Carry the blessed meaning into the work, checkably.** Once blessed, the formulation is stable: carry it verbatim in spirit, and treat later paraphrases as re-tests against the blessing, not free rewording. In the artifacts, unpack the blessed meaning once at its most load-bearing location and let other occurrences stay terse as back-references; a blessed meaning that lives only in the conversation is not yet carried. Then verify: run a targeted search proving the old framing survives nowhere, sweep sibling and downstream surfaces both for the same flaw pattern and for compatible statement of the new meaning, and where two formulations could collide in a reader's mind, explain the meaning of each formula near its use.

10. **Close with the consequence scan.** Before reporting done, ask the questions the user would otherwise have to ask next: is the blessed meaning actually explicit in every document that should carry it, and what else must now be true or stated because this meaning is now established? Surface the answers unprompted. A blessing usually has consequences one surface away, and finding them is part of the extraction, not follow-up work.

## Guardrails

- Never expand the user's words into specifics they did not give. Turning one word into a list ("concepts" into "concepts, rules, and configurations"), inventing enumerations, or presenting examples as theirs are all fabricated meaning wearing the user's voice. The discipline reaches past specifics: preserve the current scope, the abstraction level, and the uncertainty and incompleteness the user has actually expressed. Do not draw the body when only the cell has been exposed; unresolved parts of the feeling stay visibly unresolved until the user resolves them.
- Never repair a user-coined term or its expansion without asking the coiner which half is wrong. A term that looks internally inconsistent has at least two possible fixes, and only the coiner knows which side carries the intent.
- Do not propagate an unblessed interpretation into durable surfaces (notebooks, constitutions and their bounds, the shared external brain's canon, any committed document) — the surfaces the capture menu lands work into. If an interpretation has already propagated and is then corrected, the correction is a sweep of every surface that absorbed it, not a patch at one spot.
- A correction on one element means the rest of the interpretation needs re-testing too. If the user caught one drift, others are more likely than baseline.
- Comply-with-objections-named, never comply-blindly and never refuse-silently. When the user's direction collides with an established fact, the collision goes into the proposition where the user can resolve it.
- The verdict must be honest in both directions. Confirming a feeling the evidence does not support is as damaging as dismissing one it does; the user is calibrating their own articulation against the verdicts.
- The user's inability to articulate fully on first expression is the normal case, not an edge case. Do not treat iteration as inefficiency; the engine costs minutes and its absence costs hours.

## Relationship to other skills

This skill runs upstream of the others that touch meaning. `ubiquitous-language-stewardship` grills terms during design; this skill extracts what the user means before any term can be grilled. `decision-proposal-discipline` weighs options; this skill ensures the options address the right question. When those skills apply, enter them after the blessing, not instead of it. Stage 9's propagation sweep hands off to the capture rule (`rules/20-capture.md`): once a meaning is blessed, its landing surface is found by the menu scan — the constitution's bounds for a standing decision, the shared external brain for a team-wide term, an aim surface's ripening region for a wish bigger than the unit — and body writes into those surfaces dispatch to the Builder, notebook closure lines are the Concertmaster's own hand.

The ontological audit in `references/ontological-audit.md` is this skill's construction-side counterpart: it audits whether the elements of a formulation, the user's or the agent's, can ontologically bear the roles assigned to them. In live extraction dialogue this engine leads and calls that audit at the candidate-readings stage (4) and the self-test stage (7). The audit reference carries the questions battery and the compact governing instruction in full for this skill's purposes — enough to run the audit inside this engine; it is a slice of a longer treatise on intended meaning, held privately by the authors. Outside live dialogue, when text is produced without an interlocutor, that standalone always-on obligation is lived by the writing members' consequence-complete editing rather than promoted as a skill.
