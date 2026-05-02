# Field Notes Protocol — Self-Improvement for Agents

Agents in this roster (mozart, harry, jackson, valerie, dick, dexter, xander, otto, ruby, bob, scott, librarian) may improve themselves over time by appending to a `## Field notes (append-only)` section at the bottom of their own persona file. This document defines the protocol — what's allowed, what's forbidden, and the format every entry must follow.

The point is to capture cross-project patterns the agent discovers in practice, so future invocations benefit from accumulated experience. The protocol is intentionally constrained because a persona file is a contract: the human-authored sections define who the agent is, and the agent doesn't get to rewrite that.

## What you may do

- **Append** entries to your own `## Field notes (append-only)` section.
- That's it.

## What you may NOT do

- Edit any other section of your own persona file (description, tools, role, discipline, output format, boundary checks, etc.). Those are human-authored contracts.
- Edit other agents' persona files.
- Remove or modify existing field notes — only the user prunes.
- Promote a field-note learning into the body of the persona on your own initiative. If a pattern feels load-bearing enough that it belongs in the discipline section, surface that to the user — don't restructure unilaterally.
- Reorder or restructure the field notes section. Append-only, chronological.

## What counts as a field-note-worthy learning

A learning earns a field-note entry when **all** of these are true:

1. **Cross-project / cross-context pattern.** You've seen the same thing in at least two distinct projects, OR you've seen it once but it strongly contradicts a default you've been following.
2. **Action-shaped.** Future-you can do something differently as a result. "X is interesting" isn't a learning. "When seeing X, prefer Y over Z because W" is.
3. **Cite-able.** You can point to specific evidence (commit SHA, ticket ID, project path, conversation excerpt) that motivated it.
4. **Generalizes.** It's not specific to one repo's conventions, one customer's IdP, one team's preferences. Those go in the project's `CLAUDE.md`, not your persona.

## What does NOT belong in field notes

- **Project-specific conventions.** "In `os-project-athena`, services live in `src/`" → repo CLAUDE.md.
- **User preferences for one task.** "Jay wanted SSE this time" → not a pattern.
- **One-off coincidences.** Saw it once, can't articulate why it generalizes → not a learning.
- **Restating your existing discipline.** If the persona already says "verify before claiming done," don't add a field note saying "I should verify before claiming done."
- **Editorial complaints.** Field notes are about practice, not opinion.

## Entry format

```markdown
### YYYY-MM-DD — <one-line summary>

- **Scope**: cross-project pattern | language: <lang> | tool: <tool> | domain: <domain>
- **Confidence**: high | medium | low
- **Evidence**:
  - <commit SHA or ticket ID> — <one-line context>
  - <project path or conversation reference> — <one-line context>
- **The pattern**: <one paragraph describing what you observed>
- **What to do differently**: <one paragraph; concrete action>
- **What this overrides** (if applicable): <a default in your persona this contradicts; otherwise "n/a">
```

Be concise. Each entry is ideally ~10 lines. If you're writing more, you're probably trying to write a discipline section — surface to the user instead.

## Confidence rules

- **High** — Seen the pattern multiple times in distinct projects with clear evidence. Strong recommendation for future-you.
- **Medium** — Seen once with strong evidence, OR seen multiple times but the connection is inferential. Worth following but not load-bearing.
- **Low** — Hypothesis based on a single observation. Recorded for visibility; future-you should treat as a hint, not a rule. If multiple low-confidence entries point at the same pattern, you can later add a high-confidence consolidation entry.

Default to lower confidence than you feel. False highs poison the well; false lows are corrected as more evidence accumulates.

## When to append

- During or immediately after a task where you discovered the pattern. Latency between observation and capture loses fidelity.
- Not retroactively from memory of work you didn't write down at the time. If you didn't capture it then, it probably wasn't significant enough.

## When NOT to append

- When you're uncertain whether it's a pattern or a one-off → don't.
- When the user has just corrected you once → that's *user feedback*, possibly worth capturing as memory, not a field note in your persona.
- When the pattern is project-specific → write to the project's CLAUDE.md instead.
- When you'd be the only agent affected by it and it's already in your discipline → no value to repeating.

## Periodic review (the user's job)

Field notes accumulate. Periodically the user (or mozart, on request) should:

1. Read each agent's field notes
2. Promote durable, high-confidence patterns into the persona's discipline sections
3. Prune entries that turned out to be wrong or no longer relevant
4. Consolidate clusters of related entries

Agents do not perform pruning or promotion on their own initiative. The "review my field notes" passthrough route in mozart surfaces these for the user.

## How agents without Edit/Write capability append

Most agents have either `Edit` (Edit tool) or `Bash` (heredoc append). For those with only `Bash`:

```bash
# Resolve to wherever your persona file is installed (plugin path or ~/.claude/agents/)
cat >> "<path-to-your-persona-file>" <<'EOF'

### YYYY-MM-DD — <summary>

- **Scope**: ...
- **Confidence**: ...
- **Evidence**: ...
- **The pattern**: ...
- **What to do differently**: ...

EOF
```

Agents with no write capability (ian, sarah, codebase-* agents) cannot self-update. Instead, they include the proposed learning in their return message to mozart, who can write it on their behalf if it meets the criteria above. Mozart treats this as a delegated append, not a free hand to rewrite.

## Anti-patterns (things that have actually gone wrong with self-modifying systems)

- **The slow drift.** Each entry seems reasonable individually; collectively the persona becomes incoherent. Mitigation: periodic human review, append-only discipline, no in-line restructuring.
- **The confidence inflation.** Every learning gets marked "high." Mitigation: default lower, treat the confidence label as part of the entry's evidence.
- **The single-incident generalization.** "This one project did X this way, so I'll always do X." Mitigation: requirement of two distinct contexts before promoting to "pattern."
- **The personal-preference smuggling.** Agent develops a stylistic taste and encodes it as a "learning." Mitigation: cite evidence, scope explicitly, require an action-shaped framing.

## Default standard alignment

Same standard as everything else: pursue accurate over decisive. An empty field notes section is not a failure. Most tasks won't produce any field-note-worthy learning. That's expected — patterns are rare; tasks are common.
