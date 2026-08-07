---
name: skill-zipper
description: Compresses a SKILL.md or agent instruction file to the minimum an agent needs — strips prose, human-facing labels, restating comments, and demonstrations of standard commands — then proves functional parity before applying. Use when asked to shorten, tighten, simplify, condense, or cut the token cost of a skill.
---

# skill-zipper

Decision rule: an item survives only if the agent cannot derive it from the command itself, the surrounding code, a referenced file, or general knowledge.

## Delete

| Target | Test |
| --- | --- |
| Abstract or ambiguous wording | Could two agents act differently on it? → replace with a decidable condition |
| Explanation of general knowledge | Would a competent agent already know this? |
| Rules not specific to this skill | Would it apply unchanged to any other skill? |
| Human-facing labels, bold, signposts | Does any cross-reference point at the name? If not, delete |
| Comments restating what a command does | Is it derivable from the command or from line order? |
| Standard commands with no second form | `git commit`, `git tag`, `firebase deploy`, `npm run lint` — demote to a constraint sentence |
| Duplicated rationale across sections | Keep one canonical statement, cross-reference the rest |

## Keep

- Proper nouns, exact flags that change behavior (`--staged`, `--yes`, `--source=. --push`), literal argument values (`'(default)'`)
- Anything this skill invented: its own schemas, its own `resources/*` scripts and their CLI contract, its output format
- Comments answering *when to run*, *what must hold afterward*, *what is forbidden*
- Cross-reference anchors and normative markers (`hard rule, no override`) — these set a rule's override class
- Heading hierarchy and paragraph structure

## Form

- Prefer JSON / Schema / yml / tables / example code over prose
- Example code need not be runnable: one key line plus comments showing the rest
- Code block = must be copied literally. Prose = constraint. Never blur the two
- Lead a rule with its trigger condition, not its topic name

## Baseline

Establish before any edit. Prefer git — it needs no cleanup and cannot be clobbered by a stray write.

| Target file state | Baseline | Rollback |
| --- | --- | --- |
| tracked, clean | `git show HEAD:./<path>` | `git checkout -- <path>` |
| tracked, dirty | ask first, see below | — |
| untracked, or no repo | `cp SKILL.md SKILL.old.md`, never modify it again | the copy |

Uncommitted changes in the target → ask which, never choose silently:

- commit them now → baseline is that commit
- `git switch -c zip/<skill-name>` and commit there → the working branch stays clean, the diff is reviewable as a branch
- leave them → fall back to the `SKILL.old.md` copy, and say that the baseline now includes unreviewed work

## Procedure

1. Enumerate every rule in the baseline as a numbered checklist before editing
2. Run 10 passes, one focus each:

| # | Focus |
| --- | --- |
| 1 | ambiguity → decidable conditions |
| 2 | prose → tables and schemas |
| 3 | drop what `references/*` already covers |
| 4 | restructure rules to lead with their trigger |
| 5 | replace narrated flows with the skill's own schema/examples |
| 6 | escalation and branching → decision ladders |
| 7 | required outputs → fill-in templates |
| 8 | cross-section deduplication |
| 9 | sentence compression, imperative voice |
| 10 | proofread + parity check |

3. Parity check: every checklist item from step 1 must still be findable. Missing → restore it
4. Measure both sides whitespace-normalized — formatters pad table cells, so raw byte counts lie. `git show` needs the path repo-relative, hence the `./`:
   ```bash
   git show HEAD:./skills/x/SKILL.md | tr -s ' ' ' ' | wc -c   # baseline
   tr -s ' ' ' ' < skills/x/SKILL.md | wc -c                   # result
   ```
5. Gate: smaller **and** at parity. Either one fails → report and stop, original untouched
6. Report, then ask the user to confirm. Point them at `git diff` rather than pasting the diff into chat. Write the change only on approval; declined → `git checkout -- <path>`, or restore from the copy
7. Confirmed → delete `SKILL.old.md` if one was made. A git baseline leaves nothing to clean up

A format-on-save markdown formatter also eats the space before inline code and rewrites tables between edits — re-read the file before edits that depend on surrounding lines.

## Report

- Per-pass table: focus → what changed, or "no change"
- Parity: baseline rule count vs found; anything deliberately dropped, and why
- Size: baseline vs result, whitespace-normalized, with the percentage
- Say plainly when passes stop reducing — structural gain ≠ token gain
