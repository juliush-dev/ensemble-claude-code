# Method Reference

## Why multi-view modeling works

A topic commonly contains several forms of structure at once. The entities that exist are not the same as the events that occur. Authority is not the same as responsibility. A deployment boundary is not a chronological phase. A threat is not a normal workflow step. One diagram that attempts to express all of these dimensions usually becomes unreadable or semantically ambiguous.

The multi-view method separates these dimensions while preserving a shared ontology. Each diagram answers one question, and the prose explains how the answer connects to the other views.

## The three layers of a strong learning document

### 1. Evidence layer

This layer establishes what can responsibly be said. It contains source provenance, freshness, conflicts, uncertainty, and the distinction between direct evidence and synthesis.

### 2. Model layer

This layer identifies entities, processes, relations, boundaries, states, and rules. It provides the common vocabulary used by every diagram.

### 3. Teaching layer

This layer orders the views so that each one prepares the learner for the next. It controls progressive depth, interpretation, examples, misconceptions, and final consolidation.

A document can be visually polished and still fail if any one of these layers is weak.

## View-selection reference

### Landscape and terminology

Use when the subject is surrounded by adjacent, historical, colloquial, or frequently confused concepts. Show inclusion, specialization, succession, equivalence, and distinction.

### Problem and purpose

Use when the learner needs to understand why the subject exists. A before/after contrast often works better than an abstract feature list.

### Context or ecosystem

Use to establish actors, organizations, systems, environments, artifacts, and boundaries. Keep chronology out of this view.

### Authority and responsibility

Use when governance matters. Separate who owns, authorizes, regulates, validates, performs, supports, and remains accountable.

### Structure, composition, and lineage

Use for parts, containment, derivation, custody, transformations, dependencies, and data or artifact lineage.

### Interaction sequence

Use for a concrete runtime, administrative, biological, institutional, or communication process in which order and participants matter.

### State and lifecycle

Use when the subject persists across states such as proposed, approved, active, suspended, renewed, failed, replaced, or retired.

### Deployment and boundary

Use to show where elements reside, where protection or responsibility starts and ends, and what crosses boundaries.

### Threats, failures, and controls

Use to show adversaries, error sources, preconditions, failure modes, consequences, mitigations, detection, and response. Do not imply that every control eliminates a threat completely.

### Comparison and alternatives

Prefer separate small views or a comparison table when alternatives have different structures. Avoid overlaying several systems into one graph unless the shared and differing elements remain obvious.

### Causal and historical development

Use directed causal relations for influences and ordered timelines for dated events. Distinguish correlation, contribution, trigger, and sufficient cause.

## Cross-view ontology rules

A named element should retain the same meaning everywhere. Do not use one label for both an organization and its portal, or for both an artifact and the process that creates it.

Maintain a term registry containing:

- canonical term;
- aliases;
- semantic category;
- definition;
- source;
- views in which it appears.

When a term must change meaning by context, qualify it explicitly.

## Relationship-writing rules

A diagram becomes much easier to inspect when each edge can be read as a sentence.

Good:

> Regulator — issues → binding rule

> Runtime process — reads → configuration

> Evidence — supports → conclusion

Weak:

> Regulator → rule

> Runtime process → configuration

> Evidence → conclusion

Use a named relationship node when the relation itself is important or when endpoint roles differ:

> Institution — delegates → request authority — is exercised by → administrator

## Visual grammar notes

### Flowcharts

Best general-purpose grammar for context, responsibility, composition, boundaries, causal relations, threats, and decisions. Use subgraphs for meaningful environments or responsibility zones.

### Sequence diagrams

Use when order and communication are primary. Lifelines should represent participants capable of sending, receiving, or processing events. Put payloads and artifacts in message labels.

### State diagrams

Use for durable states and labeled transitions. Do not use a state diagram merely to list sequential tasks when the subject does not persist in states.

### Class diagrams

Use for stable conceptual types, attributes, inheritance, association, and composition. Avoid forcing operational workflow into class relations.

### ER diagrams

Use for data entities and cardinality. They are especially useful when understanding records, ownership, and references is central.

## Recommended document progression

A broad domain document often benefits from this progression:

1. Orient the learner with terminology and scope.
2. Establish the problem, purpose, or motivating question.
3. Introduce the ecosystem and boundaries.
4. Explain structure and important artifacts or concepts.
5. Walk through the main mechanism or interaction.
6. Show operation, deployment, or concrete variants.
7. Explain lifecycle or evolution.
8. Expose threats, limits, and non-goals.
9. Consolidate the mental model.

Reorder when the domain demands it. Mathematics may begin with dependencies and examples; history may begin with chronology and actors; law may begin with authority and scope; biology may begin with structure and process.

## Research adequacy rules

A source set is usually inadequate when:

- all sources repeat the same secondary account;
- a time-sensitive fact lacks a current authoritative source;
- the central mechanism is inferred from marketing material;
- implementation behavior is generalized from one product;
- a disputed claim is presented from only one side;
- user-provided material is copied without verification;
- the document cites references that were never inspected.

For consequential claims, use source triangulation: one primary authority plus an independent high-quality source where available.

## Uncertainty design

Uncertainty should appear in the model at the point where it matters.

Use:

- an orange warning node for conditional behavior;
- an `opt` or `alt` branch in sequence diagrams;
- a callout immediately below the relevant diagram;
- wording such as “may,” “depends on,” “under policy X,” or “the evidence does not establish.”

Do not convert an unknown into a definite arrow for visual neatness.

## Pedagogical interpretation

An interpretation section should answer:

- What is the main pattern visible here?
- Which relation is easiest to misunderstand?
- What boundary or condition matters?
- How does this view prepare the next one?

It should not mechanically restate every node and edge.

## Obsidian syntax and renderer compatibility

The output target is an Obsidian note, not generic Markdown that merely happens to open in Obsidian. Apply the full compliance contract in `SKILL.md`. For ordinary Obsidian use:

- prefer standard Mermaid syntax;
- avoid experimental grammar unless necessary;
- keep initialization blocks modest;
- quote complex labels;
- avoid oversized diagrams;
- split dense graphs into panels;
- verify diagrams in an Obsidian-compatible Mermaid renderer before delivery when tooling permits;
- use native Obsidian callouts, valid YAML properties, balanced fences, portable links, and valid pipe tables;
- exclude chat-native citation markers, UI references, temporary download links, and unsupported Markdown extensions;
- avoid plugin, CSS, Dataview, or theme dependencies unless the user requested and receives documentation for them.
