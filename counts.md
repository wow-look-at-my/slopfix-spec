# counts: a count in a document

Rules judge a markdown document for a figure that goes stale. `counts/inventory-count` reports a stated count of what the document's subject holds. `counts/section-number` reports a section cited by its number. Both are `RuleCounts` rules in the `counts` family. Each reads only the prose blocks of a document and repairs each finding. The code is in `counts/` (`counts.go`, `reword.go`, `label.go`, `sections.go`), with the rule registrations in `rule_counts_inventory.go` and `rule_counts_section.go`.

## What is read

`proseLines` in `counts/counts.go` returns the lines that `markdown.Split` marks as `markdown.Prose`, each with its line number and byte offset. A fence, a table, a heading and an indented block are verbatim, and no rule reads them. `blankInlineCode` replaces each backtick span with spaces of the same length. A span is data and every offset stays valid. Both rules apply to a `fixer.Document` file only.

Which number is a count is decided in the `cardinal` package. This package supplies the document: which lines to read, and how to cut the number out. The `cardinal.Substrate` values it uses are `cardinal.Prose` for `counts/inventory-count` and `cardinal.Gate` for the merge gate's `ste/count`. `Check` is `find` over `cardinal.Prose` with `blankInlineCode` as the mask. `Gate` is `find` over `cardinal.Gate` with `ste.Masked` as the mask. Both return `Hit` values, each holding the phrase, the trimmed line, the 1-based `LineNo` and the byte `Start` and `End` in the whole document.

## counts/inventory-count

The ID is the constant `ID` in `counts/counts.go`, with the value `counts/inventory-count`. The finding text is set in `inventoryFindings` in `rule_counts_inventory.go`. The rule is `a stated count goes stale when the set changes`. The detail is the phrase. The fix text is `Describe what is there and let the reader count.`

### Detection

`cardinal.Prose` has `Shape` set to `cardinal.Quantity` and `Frame` set to true. A quantity is a cardinal that governs a plural noun. The cardinal is one to multiple digits (`\d{1,4}`) or a word of the `prose` class in `rules/numbers-cardinal.xml`. `two` to `twenty`, then `thirty` to `ninety` in tens, and `dozen`. `one` is absent on purpose, because it reads as an article more frequently than as a count. A bounded number of words may sit between the cardinal and the noun.

The noun has a few letters and ends in `s` (`proseQuantity` in `cardinal/quantity.go`).

A quantity is reported only inside a frame (`cardinal/frame.go`). There are frames, read in this order, and a phrase is reported once, by the first frame that matches it.

- `possessiveFrame`: `this`, `these`, `our` or `the`, then a bounded number of words ending in a possessive, then the quantity. An example it reports is `This repo's 15 plugins ride in the payload.`
- `havingFrame`: a word of the `framing` class, or a `durative` word before a `duration` word, or an `existential` word before an `existence` word. Then an optional `hedge` word, then the quantity. Examples it reports are `It ships two hooks.` and `There are three sections.` A measurement is a count here: `The read has 20 seconds.` and `The step takes about 90 seconds.` are findings.
- `deicticFrame`: `the`, `these` or `those`, then the quantity, then a bounded number of words, then a `deictic` word. An example it reports is `The four rules below decide it.`

A quantity with no frame is ordinary prose and is not reported. The sentence `Split it into three parts if that reads better.` is left alone.

### Exemptions

`cardinal.Prose` lists these exemptions in `Exempt`. A quantity that any of them accepts is not reported.

- `ContinuesANumber`: the match follows a `.` or a digit, so a version such as `2.1.205` is not a count.
- `InExpression`: the match follows one of `- + / * = . , _` or a digit, or sits in a clause that holds ` = `. Arithmetic and ranges are not counts.
- `FunctionWordGap`: a function word sits between the cardinal and the noun, as in `it has 2 of the format drops`. The word list is `gapStopWords`.
- `StatusCode`. An HTTP status code from the `status-code` class that heads a reply noun, follows the word `status`, or sits in a list with another code.
- `Labeled`: the word before the number is in the `label` class (`http`, `migration`, `rfc`, `pr`, `issue`, `version`, `release`, `port`, `revision` and their plurals where the file lists them).
- `SectionCite`: the number follows a section sign. Section citations belong to `counts/section-number`.
- `IssueNumber`: the text before the number ends in `issue #`.
- `GPUName`: the text before the number ends in `vega `.
- `WordSize`: the quantity is `8 bits`, `16 bits`, `32 bits` or `64 bits`.
- `Measure`: the word after the quantity is a singular verb from `singularVerbs` (`is`, `was`, `has`, `does`, `fits`, `equals`), as in `43 cols is less than the cap`.

`Check` does not report a count that sits in a fence, a table, a heading, an indented block or a backtick span.

### The merge gate's twin: ste/count

`Gate` reads the same document with `cardinal.Gate`: no frame and the `gate` word class (`two` to `twelve`). This also covers the pattern `gateQuantity`, and the exemptions `InExpression`, `FunctionWordGap`, `AfterAnArticle`, `ChoiceAmongASet`, `StatusCode`, `Labeled`, `SectionCite`, `IssueNumber`, `GPUName`, `WordSize`, `NoPluralNounAfter` and `Measure`. Its rule ID is `ste.IDStaleCount`, and `ste/ste-simplified-technical-english.md` holds its detection. This file covers its repair, because the repair is shared. In `Check` in `slopfix.go`, a gate finding with the same detail as an inventory finding in the same block is dropped. One phrase is reported once.

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

`reword` in `counts/reword.go` finds the leading cardinal of the phrase with `cardinal.Leading`. A `~` before the number goes with it. Hedges from `approximations` (`about`, `roughly`, `around`, `approximately`, `nearly`, `almost`, `only`, `just`, `exactly`, `some`, `precisely`) in front of the number are dropped with it. The words before the number, back to the last clause break, choose what replaces it. The first case that matches wins:

- A cap from behind: the text after the phrase matches `ceilingAfter` (`or fewer` or `or less`). The text becomes `a bounded number of ` plus the noun. The cap words are removed. `It keeps 500 lines or less.` becomes `It keeps a bounded number of lines.`
- Zero, when the phrase is no measurement: the text is `no `.
- A measurement (`measures`: the second word of the phrase is a unit and the phrase has a few words): the number and the unit after it go, as in `64 MiB chunks`.
- A preposition from `prepositionFloors` (`over`, `above`): the preposition stays and the number becomes `vague(n)`.
- A rate word from `rates` (`every`, `each`, `per`): the rate word is replaced and the text is `every few `.
- A ceiling from `ceilings` (`at most`, `up to`, `no more than`, `fewer than`, `less than`, `not more than`, `under`, `below`, `within`), tested as a few words, then two, then one: the ceiling words go and the text is `a bounded number of `.
- A floor `more than` from `floorsAbove`: the words go and the text is `vague(n + 1)`.
- A floor from `floors` (`at least`, `no fewer than`, `no less than`, `not less than`): the words go and the text is `vague(n)`.
- A determiner or possessive already governs the noun (`determined`, with `same` and `other` skipped as `comparatives`): the number goes and nothing replaces it.
- The noun is a unit (`cardinal.IsUnit`): the text is `vague(n)`.
- The word before is a preposition, or `followsANoun` is true: the text is `multiple `.
- Otherwise the number goes and nothing replaces it.

`vague(n)` returns `a couple of ` for 2 or less, `a few ` up to 5, `several ` up to 20, and `many ` above that. `value` reads a cardinal as an integer from `numberWords`, which ends in `dozen` as 12. A digit string is read with its commas removed, and a number too large to parse is `1 << 30`.

Capitals: when the number opens a sentence (`opensSentence`), the replacement text is capitalized. When the replacement is empty, the next letter is capitalized and absorbed into the edit. An emphatic upper-case number that does not open a sentence passes on no capital.

Examples, from `TestEveryCountIsReworded` and `TestARewordKeepsTheSentenceEnglish`, each as input then output:

```
It polls every 15 minutes.        -> It polls every few minutes.
The step takes about 90 seconds.  -> The step takes many seconds.
It keeps up to 10 entries.        -> It keeps a bounded number of entries.
It needs at least 3 reviewers.    -> It needs a few reviewers.
It carries over 500 lines.        -> It carries over many lines.
It runs in two passes.            -> It runs in multiple passes.
It ships exactly two hooks.       -> It ships hooks.
Done. 15 plugins ride in the payload. -> Done. Plugins ride in the payload.
```

`followsANoun` uses `syntax.Parse` on the line: the word before the cardinal is tagged `NN`-prefixed or `PRP`. It exists because `one call two ways` will otherwise lose its number and read `one call ways`.

### elided

`elided` in `counts/counts.go` handles a second number in the same clause that stands for the same quantity, as in `warns at 500 lines and errors at 750`. The clause runs from the end of the hit to the end of the line, cut at the first of `;`, `:` or `!`. This also covers `?` or a period followed by a space. A bare number qualifies when `elidedNumber` matches it after one of `at to from of by over under than with in and or`, and the text before it holds `and`, `or` or `but` (`clauseCoordinator`). It does not qualify when another hit overlaps it. The edit replaces the bare number with `a higher count`, `a lower count` or `the same count`, by comparing its value with the first hit's.

### Labels and points

`LabelAt` in `counts/label.go` takes the byte offset of digits. It answers false when no digit starts there. It then asks questions of the line.

`cardinal.NamesAnItem` (in `cardinal/quantity.go`) is true when the digits sit straight after a singular noun and name one item, as in `branch 3 sees` or `the Section 4 pins`. A noun that a number, `a`, `an`, `each`, `every`, `one` or `per` governs starts a second phrase, so it is not a label. Words that count or order, such as `first`, `last`, `top` and `most` (`notNames`), are not names. A capitalized first word of a sentence names an item only before a finite verb, because a capital there opens an instruction. The repair in `itemEdit` replaces the noun and digits:

- If the text gives the item words elsewhere, `resolveItem` uses them. It reads `branch (3) the keyless fallback` (a definition, `nameOf` trims the description to between two and six words, keeping a code span only when a bounded number of words precede it) and a heading such as `Keyless fallback (branch 3)`, which gives `the keyless fallback`.
- Otherwise `genericItem` writes `one <noun>` for a value of 1 or less, and `a later <noun>` above that. An all-capitals noun keeps its case.
- When a plural noun follows the label and a finite verb comes before the label, the plural is what the label describes: `It reads rule 6 inputs.` becomes `It reads the inputs of a later rule.`
- A preceding determiner (`the`, `a`, `an`, `this`, `that`, in `determiners`) is replaced along with the label.
- The first letter is capitalized when the edit opens a sentence.

`cardinal.APoint` is true when the digits follow `at`, `by` or `to` and set a point on a scale, as in `at 100 cols`. `to` after `up` is excluded. A hedge in front is looked through, and a unit word after the digits makes it a quantity instead. The repair in `pointEdit`:

- If the caller passed a `Constants` function and it names a constant whose value is the digits, the text is that name in backticks. The `fixer` repairs in this package pass nil.
- Otherwise a hedge before the number is removed with it, and the text is `a set limit` for `to`, `a set value` for `at`, and `a set amount` for `by`. When a plural noun follows (`pluralNoun`: the word after is tagged `NNS` or `NNPS` and either the clause has a finite verb before it or the point opens the sentence), the text is `a set number of`.

Examples, from `TestANumberThatNamesAnItemIsRepaired`:

```
Then branch 3 sees the entry already cleared. -> Then a later branch sees the entry already cleared.
It reads rule 6 inputs.                       -> It reads the inputs of a later rule.
The mock with id 1 completes after a short delay. -> The mock with one id completes after a short delay.
The row wraps at 100 cols in the modal.       -> The row wraps at a set number of cols in the modal.
The preview contributes 0 lines when it is off. -> The preview contributes no lines when it is off.
```

`RewordAt` is the same as `reword` for a caller that holds a phrase and a start offset but no `Hit`.

## counts/section-number

The ID is the constant `IDSection` in `counts/sections.go`, with the value `counts/section-number`. The rule is `a section cited by its number goes stale when a section is inserted above it`. The detail is the cited number. The fix text is `Cite it by the slug of its title, as a link: ` followed by the link. The fixer registered in `init` has `Place` set to `21`. `fix.go` adds the findings when the `RuleCounts` family is wanted and the rule is kept.

### Headings

`Sections` maps each numbered heading in a document to a `section` holding a slug and an anchor. A heading is a verbatim, one-line block that matches `headingLine` (one to six `#`, then the title, with trailing `#` removed). A title is numbered when it matches `numberedTitle`. The title an optional section sign, then digits with dotted parts and an optional lowercase letter, an optional period, whitespace and the rest. The key is the number, such as `9` or `9.2`. A number that headings share keeps the first.

- The anchor is `githubAnchor` of the whole title, made unique as GitHub does by `uniqueAnchor`: `x`, `x-1`, `x-2`. `githubAnchor` removes backticks and asterisks, turns underscores into spaces, lowercases, keeps letters, digits and hyphens, turns spaces into hyphens, drops other characters. It trims hyphens at both ends. The anchor of `## 9. Owning the renderer` is `9-owning-the-renderer`, and that of `### 9.2 The cap` is `92-the-cap`.
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

becomes a text whose citations read `[§owning-renderer](#9-owning-the-renderer)`, `[§cap](#92-the-cap)` and `[§question](#1-the-question)`. The prose rules read the link as the citation it replaced, which carries no number word.

A link written by this rule and a heading with a new slug: `[§old-name](#9-owning-the-renderer)` becomes `[§owning-renderer](#9-owning-the-renderer)`. The anchor stays, and only the slug changes.
