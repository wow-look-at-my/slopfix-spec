# counts/inventory-list: an enumeration of what the code holds

An enumeration states the members of a set the code defines: its commands, flags, rule IDs, categories, files, guards, word classes, fields. The code is the only source of truth for that set. A copy in prose is incorrect the moment a member is added, renamed or removed, and keeping it right is work. That buys the reader nothing the program does not already tell them. `counts/inventory-list` reports every enumeration and its repair deletes it. It is a `RuleCounts` rule, the same family as `counts/inventory-count`: a stated count goes stale.

A stated membership goes stale the same way.

This example is a finding. It is the rule's hardest case in its `Cases`:

```
The commands are `check`, `hook`, `lsp`, `ratchet`, `version`, `completion` and `help`.
```

A reader who needs the members asks the program (`slopfix help`, `--help`, a `list` subcommand) or reads the data file the code loads. Prose names the set and says what it is for. It never lists what is in it.

## The guarantee

- No text slopfix reads may hold an enumeration after `slopfix fix`. `slopfix check` reports every one as an error.
- There is no exemption of any kind. No path, file type, region, heading, marker, flag, option, environment variable, `.gitattributes` entry or allowlist turns the rule off or narrows it. An index, a table of contents, a rule table, a command table, a word list and a spec page are all enumerations. The spec page are all reported. A rule that needs a list keeps it in a data file the code loads, and prose points at the file by name.
- The rule is never `ReportOnly`, not `registerExempt`, and its `Repairable` is true. Its fixer repairs every finding its detector reports. Every item of CLAUDE.slopfix-guarantee.md's forbidden list applies to this rule by name.
- A finding is never a "false positive" because the list is accurate today. This is because the reader finds it handy, or because a test or CI step demands it. A check that demands an enumeration is itself the defect, and the fix removes that check.
- The `write` hook guard runs this rule on every Write, Edit and MultiEdit, so an enumeration is repaired before it lands. The `.github/ratchet` gate runs master's `check` on a branch's `fix` output, so a branch that weakens this rule fails.

## What is read

Every surface slopfix reads, with no carve-out:

- A document: prose blocks, list items, headings, tables and fenced blocks. A fence and a table are verbatim for the other prose rules. However, they are read here, because a catalog of commands in a `sh` fence or a rule table is the same enumeration in another shape.
- A comment in source, through the `commentfix` tree, in every language that package parses.
- A comment in a workflow or action manifest.
- A closing message under `check --message`.
- A commit message the `rustfmt` and `no-work-loss` guards see is not read, because no rule reads it.

## Detection

A member is any of:

- an inline code span.
- a link whose target is a path in the repository, a URL anchor or a symbol.
- a token shaped like a name in code: it holds `_`, `/`, `::`, a `.` between letters, a `-` between letters, or an internal capital. This also covers a leading `--` or `-`, or a trailing `()`.
- under a complete-set frame (below), any noun phrase.

An enumeration is any of these. The thresholds are the constants `MinMembers = 3` and `MinFramedMembers = 2` in `counts/inventory_list.go`.

- **A coordinated run.** `MinMembers` or more members in one sentence, joined by commas, semicolons, slashes, `and`, `or`, `nor`, `as well as` or `plus`. Words between members do not break the run. Only a sentence end does. A parenthesized or `such as` / `like` / `including` / `e.g.` list is a run too.
- **A complete-set frame.** A set noun, then a word of the `complete-set` class in `rules/inventory-list.xml` (a copula, `is one of`, `include`, `consist of`, `hold`, `contain`, `cover`, `list`, `comprise`, or a colon after the set noun), then a coordinated run of `MinFramedMembers` or more members. `The categories are tombstones and counts.` is a finding.
- **A list block.** A markdown list in which `MinMembers` or more items each open with a member.
- **A table.** A table in which `MinMembers` or more rows hold a member in the same column.
- **A catalog fence.** A fenced block in which `MinMembers` or more lines that are not comments share. A leading word and differ in the word after it, as in a fence of `slopfix check`, `slopfix hook`, `slopfix lsp`. A line's comment does not change the verdict.
- **A split enumeration.** Consecutive sentences or list items that each name a member of the same set, by the same frame, reaching `MinMembers` between them. Splitting a list across sentences to stay under the threshold is the same enumeration.

The detector reads the text after `markdown.Split`, `blankInlineCode` and the comment gates, but it reads code spans as members, not as blanks. A member is counted once however frequently it repeats.

## Repair

The repair deletes. It writes no replacement sentence, because there is no true sentence about a set's members that does not go stale.

- A run or a framed list inside a sentence: the whole sentence goes.
- A sentence that is a whole paragraph or list item: the block goes.
- A list block, a table or a catalog fence. The block goes, with the lead-in sentence that introduces it when that sentence ends in a colon.
- A split enumeration: every sentence or item that carries a member goes.
- A heading whose section is empty after the repair goes too.
- A comment that holds nothing after the repair goes whole, its markers included. A closing message loses the sentence.

Every edit goes through `edit.Edit` with `Cut` set, and through the same document, comment and workflow gates the other repairs use. The fixer is registered in `init` in `counts/inventory_list.go` with `Place` set to `19`, ahead of `counts/inventory-count`. A count inside a deleted enumeration is never reworded first.

## Tests

- The rule's `Cases` hold the example above as the hardest case, and a case for each shape under Detection: a run, a frame. A list block, a table, a catalog fence, a split enumeration, a comment and a closing message.
- `ruleharness_test.go` drives each case through the common test. `allfix_test.go` requires a clean `check` after `fix` over the tree of hardest cases.
- `selfrepair_test.go` runs the rule over this repository, its `AGENTS.md`, its `README.md` and the `spec` submodule included. A hand-kept enumeration anywhere in the tree fails the build.
