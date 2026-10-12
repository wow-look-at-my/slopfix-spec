# cardinal: is this number a count

The `cardinal` package decides whether a number in a piece of text is a stated count. A stated count is true today and incorrect after the next commit. The package holds no rule ID. Each caller brings its own substrate. The substrate is the policy.

## Substrate

A `Substrate` (`cardinal/cardinal.go`) is a kind of text and what a number must do inside it to count.

The substrates are package variables.

`Find(text, s)` returns every stated count under a substrate, as a list of `Token` values. A `Token` holds `Offset`, the byte where the count starts, and `Text`. `Find` picks the finder from the substrate. A `Quantity` shape without `Frame` goes to `quantities`.

## Vocabularies

The vocabularies are classes in `rules/numbers-cardinal.xml` (`for="numbers"`). They stay separate, because widening one moves the verdict on text nobody edited.

In a document they are ordinary English.

Digits count in every substrate. Prose reads `\d{1,4}`. The gate reads `[0-9]+`. A comment reads any digit run that `digitNumber` accepts.

## The quantity finder

The document substrates match a cardinal followed by a plural noun. Their patterns are separate and are not derived from one another. A merge of them will move verdicts.

- Prose, `proseQuantity`: a cardinal (`\d{1,4}` or a word of the `prose` class at a word boundary), whitespace, up to a few lazy words of the form `[a-z][a-z-]*` (the group is `{0,3}?`), then a plural noun `[a-z][a-z-]{2,}s\b`.
- Gate, `gateQuantity`: case-insensitive. A cardinal (a word of the `gate` class, or `[0-9]+`), whitespace, an optional measure of the form number, number-and-unit word, a gap of up to `{0,2}?` words of `[a-z-]+`. Then a plural noun `[a-z]+s\b`.

The noun is the last word of the match, lowercased. `Exemption` is `func(text string, q Match) bool`. `exemptQuantity` skips a match when any exemption in the list is true.

### Frames

The `Prose` substrate finds a quantity only inside a frame, in `cardinal/frame.go`. A document carries numbers that count nothing, such as a version, a port or an example. The sentence must claim that the things belong here. `framed` runs the frames in turn and reports a phrase once, where it matches earliest. A `seen` set holds the phrases already reported.

A quantity with no frame is ordinary technical prose and is not reported. The singular is not flagged, because a lone `one` is overwhelmingly a pronoun.

## Exemptions on a quantity

Each exemption is an exported function in `cardinal/quantity.go`. A match that any exemption of its substrate accepts is dropped.

### Points and items

`APoint(text, at)` answers the preposition before digits that set a point on a scale. For `to`, the point is not a point when the word before is `up`. A unit after the digits cancels the point, so a unit still takes a vague amount. The counts rule uses this to avoid writing `at multiple cols`.

`NamesAnItem(text, at)` reports digits right after a singular noun, such as `branch 3 sees` or `the Section 4 pins`. The digits name one item. It treats a noun tagged `VBZ` or `JJ` without a plural ending as a noun. A sentence opener names an item only in lower case or before a finite verb. A capital there opens an instruction.

It does not name an item.

## Exemptions on a token

The `Comment` substrate reads tokens, not quantities. `tokensIn` splits a line into runs of name characters, so a URL, an import path and a version each stay whole. A name character is a letter, a digit, or one of the markers in `nameMarkers` (`._/:`) or `-`.

`walk` runs over the tokens. A token is exempt when any function in `ExemptToken` accepts it. A `TokenExemption` is `func(text string, toks []Token, i int) bool`.

`tokenNumber` then decides whether a surviving token carries a number.

- A token with `://` is a URL, and its digits are part of it.
- A qualified name (`isQualifiedName`) holds a marker from `nameMarkers` between word characters, such as `net/http`. It carries no number, whether the name has letters or not, once digits fail. The check order is: a qualified name with a letter yields nothing, then `digitNumber`, then a qualified name yields nothing, then `wordNumber`.
- `digitNumber` takes the first digit run.
- `wordNumber` takes the first whole word in `s.Words`. A hyphen binds a number word into a compound that names a shape. A letter on either side of the word, or past a hyphen, rejects it.

## Leading and Find

`Leading` is the pattern `(?i)^(?:\d[\d,]*|<prose words>)\s+`. It matches the cardinal at the front of a quantity, with the blanks after it. The counts repair uses it to cut the cardinal off a `Prose` finding, because a `Prose` finding carries the whole quantity, as in `15 plugins`. `Token.Text` for a `Comment` finding is the number alone.

## Units

`IsUnit(word)` and `InClass(word, class)` read the `numbers` table. A measurement is still a stated count and is still reported. What differs is the repair. The tally rewording of a plural will leave `30 seconds` with no magnitude. A unit takes a vague amount instead. `counts/reword.go` owns that choice.

## Tests

A case with no `found` says the substrate reports nothing, which is how an exemption is written down. A new exemption therefore adds a case to the XML and edits no Go test. `cardinal_test.go` holds the vocabulary difference and the shape of a `Prose` finding.
