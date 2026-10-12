# counts: a count in a document

Rules judge a markdown document for a figure that goes stale. `counts/inventory-count` reports a stated count of what the document's subject holds. `counts/section-number` reports a section cited by its number. Both are `RuleCounts` rules in the `counts` family. Each reads only the prose blocks of a document and repairs each finding.

## What is read

`proseLines` in `counts/counts.go` returns the lines that `markdown.Split` marks as `markdown.Prose`, each with its line number and byte offset. A fence, a table, a heading and an indented block are verbatim, and no rule reads them. `blankInlineCode` replaces each backtick span with spaces of the same length. A span is data and every offset stays valid. Both rules apply to a `fixer.Document` file only.

Which number is a count is decided in the `cardinal` package. This package supplies the document: which lines to read, and how to cut the number out. The `cardinal.Substrate` values it uses are `cardinal.Prose` for `counts/inventory-count` and `cardinal.Gate` for the merge gate's `ste/count`. `Check` is `find` over `cardinal.Prose` with `blankInlineCode` as the mask. `Gate` is `find` over `cardinal.Gate` with `ste.Masked` as the mask. Both return `Hit` values, each holding the phrase, the trimmed line, the 1-based `LineNo` and the byte `Start` and `End` in the whole document.

## counts/inventory-count

The ID is the constant `ID` in `counts/counts.go`, with the value `counts/inventory-count`. The finding text is set in `inventoryFindings` in `rule_counts_inventory.go`. The rule is `a stated count goes stale when the set changes`. The detail is the phrase. The fix text is `Describe what is there and let the reader count.`

### Detection

`cardinal.Prose` has `Shape` set to `cardinal.Quantity` and `Frame` set to true. A quantity is a cardinal that governs a plural noun. The cardinal is one to multiple digits (`\d{1,4}`) or a word of the `prose` class in `rules/numbers-cardinal.xml`. `two` to `twenty`, then `thirty` to `ninety` in tens, and `dozen`. `one` is absent on purpose, because it reads as an article more frequently than as a count. A bounded number of words may sit between the cardinal and the noun.

The noun has a few letters and ends in `s` (`proseQuantity` in `cardinal/quantity.go`).

A quantity is reported only inside a frame (`cardinal/frame.go`). There are frames, read in this order, and a phrase is reported once, by the first frame that matches it.

A quantity with no frame is ordinary prose and is not reported. The sentence `Split it into three parts if that reads better.` is left alone.

### Exemptions

`cardinal.Prose` lists these exemptions in `Exempt`. A quantity that any of them accepts is not reported.

`Check` does not report a count that sits in a fence, a table, a heading, an indented block or a backtick span.

### The merge gate's twin: ste/count

`Gate` reads the same document with `cardinal.Gate`: no frame and the `gate` word class (`two` to `twelve`). Its rule ID is `ste.IDStaleCount`, and `ste/ste-simplified-technical-english.md` holds its detection. This file covers its repair, because the repair is shared. In `Check` in `slopfix.go`, a gate finding with the same detail as an inventory finding in the same block is dropped. One phrase is reported once.

### Repair order

Fixers are registered in `init` in `counts/counts.go`:

- `counts/inventory-count`: `Place` is `20`. It runs before the paragraph join. The edits are `Edits(f.Text(), Check(f.Text()))`.
- `ste/count`: `Place` is `40`. It runs after the join, because a hand wrap hides the frame the gate reads. The edits are `Edits(f.Text(), Gate(f.Text()))`.

`Strip` and `StripGate` apply the same edits through `markdown.Apply` with an empty `edit.Scope` and return the text and the hits that were cut.

### Edits

`Edits` answers one `edit.Edit` per hit, and every edit records the cut text in `Cut`. For each hit it tries these in order and stops at the first that answers:

1. `LabelAt`: the digits name an item or set a point (see below).
2. `reword`: the cardinal is cut, or replaced with words that state no figure. When it answers, `elided` is also tried for a later bare number in the same clause.

A hit whose span lies outside the content is skipped. `TestNoReportedCountGoesUnrepaired` in `counts/counts_test.go` requires that `Edits` answers one edit for every hit that `Check` or `Gate` returns.

### reword

`reword` in `counts/reword.go` finds the leading cardinal of the phrase with `cardinal.Leading`. A `~` before the number goes with it. The words before the number, back to the last clause break, choose what replaces it. The first case that matches wins:

- A cap from behind: the text after the phrase matches `ceilingAfter` (`or fewer` or `or less`). The text becomes `a bounded number of ` plus the noun. The cap words are removed. `It keeps 500 lines or less.` becomes `It keeps a bounded number of lines.`
- Zero, when the phrase is no measurement: the text is `no `.
- A measurement (`measures`: the second word of the phrase is a unit and the phrase has a few words): the number and the unit after it go, as in `64 MiB chunks`.
- A preposition from `prepositionFloors` (`over`, `above`): the preposition stays and the number becomes `vague(n)`.
- A floor `more than` from `floorsAbove`: the words go and the text is `vague(n + 1)`.
- A determiner or possessive already governs the noun (`determined`, with `same` and `other` skipped as `comparatives`): the number goes and nothing replaces it.
- The noun is a unit (`cardinal.IsUnit`): the text is `vague(n)`.
- The word before is a preposition, or `followsANoun` is true: the text is `multiple `.
- Otherwise the number goes and nothing replaces it.

`vague(n)` returns `a couple of ` for 2 or less, `a few ` up to 5, `several ` up to 20, and `many ` above that. `value` reads a cardinal as an integer from `numberWords`, which ends in `dozen` as 12. A digit string is read with its commas removed, and a number too large to parse is `1 << 30`.

Capitals: when the number opens a sentence (`opensSentence`), the replacement text is capitalized. When the replacement is empty, the next letter is capitalized and absorbed into the edit. An emphatic upper-case number that does not open a sentence passes on no capital.

`followsANoun` uses `syntax.Parse` on the line: the word before the cardinal is tagged `NN`-prefixed or `PRP`. It exists because `one call two ways` will otherwise lose its number and read `one call ways`.

### elided

`elided` in `counts/counts.go` handles a second number in the same clause that stands for the same quantity, as in `warns at 500 lines and errors at 750`. This also covers `?` or a period followed by a space. It does not qualify when another hit overlaps it.

### Labels and points

`LabelAt` in `counts/label.go` takes the byte offset of digits. It answers false when no digit starts there. It then asks questions of the line.

`cardinal.NamesAnItem` (in `cardinal/quantity.go`) is true when the digits sit straight after a singular noun and name one item, as in `branch 3 sees` or `the Section 4 pins`. A capitalized first word of a sentence names an item only before a finite verb, because a capital there opens an instruction. The repair in `itemEdit` replaces the noun and digits:

- If the text gives the item words elsewhere, `resolveItem` uses them. It reads `branch (3) the keyless fallback` (a definition, `nameOf` trims the description to between two and six words, keeping a code span only when a bounded number of words precede it) and a heading such as `Keyless fallback (branch 3)`, which gives `the keyless fallback`.
- Otherwise `genericItem` writes `one <noun>` for a value of 1 or less, and `a later <noun>` above that. An all-capitals noun keeps its case.
- When a plural noun follows the label and a finite verb comes before the label, the plural is what the label describes: `It reads rule 6 inputs.` becomes `It reads the inputs of a later rule.`
- The first letter is capitalized when the edit opens a sentence.

`to` after `up` is excluded. A hedge in front is looked through, and a unit word after the digits makes it a quantity instead. The repair in `pointEdit`:

- If the caller passed a `Constants` function and it names a constant whose value is the digits, the text is that name in backticks. The `fixer` repairs in this package pass nil.
- When a plural noun follows (`pluralNoun`: the word after is tagged `NNS` or `NNPS` and either the clause has a finite verb before it or the point opens the sentence), the text is `a set number of`.

`RewordAt` is the same as `reword` for a caller that holds a phrase and a start offset but no `Hit`.

## counts/section-number

The ID is the constant `IDSection` in `counts/sections.go`, with the value `counts/section-number`. The rule is `a section cited by its number goes stale when a section is inserted above it`. The detail is the cited number. The fix text is `Cite it by the slug of its title, as a link: ` followed by the link. The fixer registered in `init` has `Place` set to `21`. `fix.go` adds the findings when the `RuleCounts` family is wanted and the rule is kept.

### Headings

`Sections` maps each numbered heading in a document to a `section` holding a slug and an anchor. A heading is a verbatim, one-line block that matches `headingLine` (one to six `#`, then the title, with trailing `#` removed). A title is numbered when it matches `numberedTitle`. The title an optional section sign, then digits with dotted parts and an optional lowercase letter, an optional period, whitespace and the rest. The key is the number, such as `9` or `9.2`. A number that headings share keeps the first.

- `githubAnchor` removes backticks and asterisks, turns underscores into spaces, lowercases, keeps letters, digits and hyphens, turns spaces into hyphens, drops other characters. It trims hyphens at both ends. The anchor of `## 9. Owning the renderer` is `9-owning-the-renderer`, and that of `### 9.2 The cap` is `92-the-cap`.
- The slug is `shortSlug` of the title after the number: the first `slugWords` words, which is `3`, of the anchor split on hyphens. That slug skips `slugSkip` words (`a an the of and or to in on for is are by with what how why we it its this that not`). With no word left, the slug is the full anchor. UniqueSlug`: `x numbers a repeated slug`, `x-2`, `x-3`.

### Detection

`CheckSections(path, content)` returns a `SectionHit` for each citation a heading answers. `path` names the document, so a citation of another file resolves beside it. Only prose lines are read, with inline code blanked.

- A citation is `§` followed by a number (`sectionRef`).
- A `[` right before the sign skips it, because it is already a link.
- The file is the document itself, unless a markdown file is named right before the citation, as in `core.md` in backticks or a link. Target ending in `.md` (`fileBefore`), or right after it with `of` (`fileAfter`). The other file is read from the directory of `path`. A file that cannot be read has no sections, so its citations are left alone.
- A citation that no heading answers keeps its number. It has no slug to take.
- A link written earlier (`sectionLinkRef`, of the form `[§slug](file#anchor)`) is reported when the heading with that anchor has a different slug now, so a renamed heading updates the link. A link whose text is the number is covered by this too.

The `§9` in a sentence like `The §9 trigger fires.` is no inventory count: `SectionCite` exempts it from both `Check` and `Gate`.

### Repair

The repair replaces the citation's byte span with the link `[§<slug>](<file><#anchor>)`. For the own document the link target is `#<anchor>`. For another file it is `<file>#<anchor>`. From `TestASectionNumberBecomesALinkNamedByItsTitle`:

```
The §9 trigger fires. §9.2 holds it, and §1 asks it.
```

The prose rules read the link as the citation it replaced, which carries no number word.

A link written by this rule and a heading with a new slug: `[§old-name](#9-owning-the-renderer)` becomes `[§owning-renderer](#9-owning-the-renderer)`. The anchor stays, and only the slug changes.
