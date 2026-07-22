---
name: skill-frontmatter-discipline
description: Use when authoring or editing SKILL.md frontmatter, reviewing a skill's metadata for parser compatibility, or when a strict YAML consumer (gray-matter, js-yaml, PyYAML) rejects a SKILL.md with an error like incomplete explicit mapping pair or missing key node.
provenance: pursuit formal-skills-promotion, agreed triage map contracts/2026-07-09-formal-skills-promotion/routes/triage-map/map.md, promoted 2026-07-09 on the user's word (deployed, footprint-verified 2026-07-09); source skills/formal/skill-frontmatter-discipline/ (the team's own authored material, the designated-work door, not curation)
---

# Skill Frontmatter Discipline

## Overview

Use this skill to keep SKILL.md frontmatter parseable by every consumer that reads it. The skill format is YAML, full stop. Claude Code's loader happens to be forgiving in places, but Lindsay, Codex, Gemini, vault indexers, and any other strict YAML parser hold the file to the actual spec. A description that parses for one agent and crashes another is the worst kind of bug. It looks invisible until it isn't, and the failure surface points at the consumer instead of at the file.

## The colon-space trap

The most common failure is an unquoted plain scalar value containing a colon immediately followed by whitespace. YAML reads that exact substring as the key/value separator of a nested mapping, so a sentence like

```yaml
description: Use for workflows: performance, scaling, and observability.
```

is parsed as "key description starts a nested mapping, key workflows has no value before another mapping starts at performance" and the parser raises `incomplete explicit mapping pair; a key node is missed`. The fragment `workflows: performance` is the offending substring, not the whole description.

Three repairs, in order of preference:

1. Reword the sentence to remove the colon-space substring. `Use for workflows, such as performance, scaling, and observability.` Same meaning, still a valid plain scalar, matches the convention every working skill in the library already uses.
2. Single-quote the whole value. Preserves the original wording byte for byte, but introduces a quoting style nothing else in the library uses. The next author who copy-pastes the pattern is likely to leave the quotes off and reintroduce the bug.
3. Use a YAML block scalar (`description: >-` on its own line, then the text indented underneath). Works, reads awkwardly for a single-sentence field, and most editors do not highlight the indentation rule the way they do for plain scalars.

Single colons inside words, single colons not followed by whitespace, commas, dots, parentheses, dashes, and slashes are all fine inside a plain scalar. Only colon-followed-by-whitespace is structurally fatal.

## Other frontmatter constraints

The frontmatter block has to start at line 1 of the file. No leading blank line, no leading comment, no byte-order mark. Both delimiters are exactly three dashes on their own line. The whole block stays under 1024 characters per the agentskills specification. Only `name` and `description` are required; additional fields per the specification are allowed but optional.

The description is read by Claude as a triggering hint at skill-discovery time, so the prose has to make sense as standalone English on top of being valid YAML. A description that parses but reads as nonsense triggers nothing.

## Quick checklist before saving a SKILL.md

- Scan the description and any other multi-word string field for the colon-space substring. If present, reword.
- Confirm the first line of the file is the opening three-dash delimiter, and the closing delimiter sits before the body.
- If unsure, pipe the file through a strict YAML parser locally before committing. A one-liner like `python -c "import yaml,sys; print(yaml.safe_load(open(sys.argv[1]).read().split('---')[1]))" SKILL.md` is enough to confirm it parses.

## Related surfaces

- The third-party-curation pipeline (its records live in the team's workbench project, oscc-workbench, reached via the workbench rather than any path on this host) is the COS's audit door: it vets an admitted skill for adversarial content, exfiltration, and other safety concerns after authoring. This skill runs during authoring and checks for parser compatibility — the two are complementary, not the same pass.
