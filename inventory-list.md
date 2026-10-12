# counts/inventory-list: an enumeration of what the code holds

An enumeration states the members of a set the code defines. The code is the only source of truth for that set. A copy in prose goes incorrect the moment a member is added, renamed or removed. Keeping it right is work that buys the reader nothing the program does not already tell them. `counts/inventory-list` reports every enumeration, and its repair deletes it. It belongs to the `RuleCounts` family beside `counts/inventory-count`.

A stated membership goes stale the same way a stated count does.

The rule's hardest case in its `Cases` is the sentence that listed every slopfix command by name in the old `commands.md`.

A reader who needs the members asks the program for them, or reads the data file the code loads. Prose names the set and says what it is for. It never lists what is in it.

## The guarantee

- No text slopfix reads may hold an enumeration after `slopfix fix`. `slopfix check` reports every one as an error.
- There is no exemption of any kind. Nothing a file, a path, a region, a marker, a flag, an environment variable or a list of names can say turns the rule. Off or narrows it.
- An index or a table of contents is an enumeration and is reported. So is a rule table, a command table, a word list and a spec page that lists. A rule that needs a list keeps it in a data file the code loads, and prose points at the file by name.
- The rule is never report-only and never exempt from registration. Its fixer repairs every finding its detector reports. Every item of the forbidden list in CLAUDE.slopfix-guarantee.md applies to this rule by name.
- A finding is never a false positive. That the list is accurate today does not excuse it. Neither does a reader who finds it handy. A test or CI step that demands an enumeration is itself the defect, and the fix removes that check.
- The `write` hook guard runs this rule on every Write, Edit and MultiEdit, so an enumeration is repaired before it lands. The ratchet gate runs master's check on a branch's fix output, so a branch that weakens this rule fails.

## What is read

Every surface slopfix reads, with no carve-out:

- A document: prose blocks, list items, headings, tables and fenced blocks. A fence and a table are verbatim for the other prose rules. However, they are read here, because a catalog of commands in a `sh` fence or a rule table is the same enumeration in another shape.
- A comment in source, through the `commentfix` tree, in every language that package parses.
- A comment in a workflow or action manifest.
- A closing message under `check --message`.

## Detection

The word lists the detector reads live in `rules/inventory-list.xml`. This page names their classes only.

A member is a name from the code. An inline code span is a member. So is a link whose target is a path or a symbol in the repository, and a token whose shape the `name-shape` class matches. Under a complete-set frame, any noun phrase is a member.

A list is a stretch of one sentence that the `joiner` class divides into elements, or the stretch after a word of the `lead-in` class. A parenthesis that holds such a stretch is a list too. An element is the phrase from one joiner to the next. An element that holds a member counts once toward the list, however frequently the member repeats.

The thresholds are the constants `MinMembers` and `MinFramedMembers` in `counts/inventory_list.go`, with the values `3` and `2`. An enumeration is any of these shapes:

- **A coordinated run.** A list with at least `MinMembers` elements that hold a member.
- **A complete-set frame.** A set noun, then a word of the `complete-set` class or a colon, then a list with at least `MinFramedMembers` elements. The frame states that the list is the whole set. A pair is enough.
- **A list block.** A markdown list in which at least `MinMembers` items each open with a member.
- **A table.** A table in which at least `MinMembers` rows hold a member in the same column.
- **A catalog fence.** A fenced block in which at least `MinMembers` lines that are not comments open with the same word and differ in the word after it. That is a usage block that walks through a program's subcommands. A comment on a line does not change the verdict.
- **A split enumeration.** Consecutive sentences or list items that each name a member of the same set with the same frame, reaching `MinMembers` between them. A list cut across sentences to stay under the threshold is the same enumeration.

The detector reads code spans as members, not as blanks.

## Repair

The repair deletes. It writes no replacement sentence, because there is no true sentence about a set's members that does not go stale.

- A run or a framed list inside a sentence: the whole sentence goes.
- A sentence that is a whole paragraph or list item: the block goes.
- A list block, a table or a catalog fence: the block goes. A sentence that ends in a colon and introduces the block goes with it.
- A split enumeration: every sentence or item that carries a member goes.
- A heading whose section is empty after the repair goes too.
- A comment that holds nothing after the repair goes whole, its markers included. A closing message loses the sentence.

Every edit goes through `edit.Edit` with `Cut` set, and through the same document, comment and workflow gates the other repairs use. The fixer is registered in `init` in `counts/inventory_list.go` with `Place` set to `19`, ahead of `counts/inventory-count`. A count inside a deleted enumeration is never reworded first.

## Tests

- The rule's `Cases` hold the commands sentence as the hardest case. They hold a case for each shape under Detection, and a case in a comment and in a closing message.
- `ruleharness_test.go` drives each case through the common test. `allfix_test.go` requires a clean `check` after `fix` over the tree of hardest cases.
- `selfrepair_test.go` runs the rule over the whole repository, the spec submodule included. A hand-kept enumeration anywhere in the tree fails the build.
