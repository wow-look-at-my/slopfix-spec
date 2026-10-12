# cardinal: is this number a count

The `cardinal` package decides whether a number in a piece of text is a stated count. A stated count is true today and incorrect after the next commit. The package holds no rule ID. Rules call it: `counts/inventory-count` (`counts/counts.go`), `ste/count` (`ste/rules.go`) and `comments/number` (`commentfix/commentfix.go`). Each caller brings its own substrate. The substrate is the policy.

## Substrate

A `Substrate` (`cardinal/cardinal.go`) is a kind of text and what a number must do inside it to count. Its fields are `Shape`, `Frame`, `Words`, `Exempt`, `ExemptToken` and an unexported `quantity` pattern.

- `Shape` is `Quantity` or `Number`. `Quantity` is a cardinal that governs a plural noun, as prose writes a tally. `Number` is a number that stands on its own, as a comment writes it.
- `Frame` says a quantity must sit in a sentence that claims the things are here.
- `Words` is the vocabulary of numbers spelled in letters.
- `Exempt` is a list of `Exemption` functions that judge a matched quantity. Only `Quantity` reads it.
- `ExemptToken` is a list of `TokenExemption` functions that judge a token. Only `Number` reads it.

The substrates are package variables.

| | `Prose` | `Gate` | `Comment` |
| --- | --- | --- | --- |
| Rule | `counts/inventory-count` | `ste/count` | `comments/number` |
| `Shape` | `Quantity` | `Quantity` | `Number` |
| `Frame` | `true` | `false` | `false` |
| `Words` | class `prose` | class `gate` | class `comment` |

`Find(text, s)` returns every stated count under a substrate, as a list of `Token` values. A `Token` holds `Offset`, the byte where the count starts, and `Text`. `Find` picks the finder from the substrate. A `Number` shape goes to the token walk. A `Quantity` shape with `Frame` goes to `framed`. A `Quantity` shape without `Frame` goes to `quantities`.

## Vocabularies

The vocabularies are classes in `rules/numbers-cardinal.xml` (`for="numbers"`). They stay separate, because widening one moves the verdict on text nobody edited.

- `prose`: `two` to `twenty`, then `thirty`, `forty`, `fifty`, `sixty`, `seventy`, `eighty`, `ninety` and `dozen`. `one` is absent on purpose, because it reads as an article far more frequently than as a count.
- `gate`: `two` to `twelve`. Past that, a spelled number in a gate message is a version and not a count.
- `comment`: `two` to `twenty`, `thirty` to `ninety`, `hundred`, `thousand`, `million`, `billion`, `trillion` and `dozen`. The words `zero` and `one` name a value, a pronoun or a condition. A repeat count is behavior. An ordinal is an order. A word joined to other letters is a name, so only a whole word counts.

The scales `hundred`, `thousand` and `million` are in `comment` and not in `prose`. In a document they are ordinary English.

Digits count in every substrate. Prose reads `\d{1,4}`. The gate reads `[0-9]+`. A comment reads any digit run that `digitNumber` accepts.

## The quantity finder

The document substrates match a cardinal followed by a plural noun. Their patterns are separate and are not derived from one another. A merge of them will move verdicts.

- Prose, `proseQuantity`: a cardinal (`\d{1,4}` or a word of the `prose` class at a word boundary), whitespace, up to a few lazy words of the form `[a-z][a-z-]*` (the group is `{0,3}?`), then a plural noun `[a-z][a-z-]{2,}s\b`.
- Gate, `gateQuantity`: case-insensitive. A cardinal (a word of the `gate` class, or `[0-9]+`), whitespace, an optional measure of the form number, number-and-unit word, a gap of up to `{0,2}?` words of `[a-z-]+`. Then a plural noun `[a-z]+s\b`.

`quantityAt` builds a `Match` with `At`, `Text` and `Noun`. The noun is the last word of the match, lowercased. `Exemption` is `func(text string, q Match) bool`. `exemptQuantity` skips a match when any exemption in the list is true.

### Frames

The `Prose` substrate finds a quantity only inside a frame, in `cardinal/frame.go`. A document carries numbers that count nothing, such as a version, a port or an example. The sentence must claim that the things belong here. `framed` runs the frames in turn and reports a phrase once, where it matches earliest. A `seen` set holds the phrases already reported. The frames are:

- `possessiveFrame`: `this`, `these`, `our` or `the`, up to a few words, a possessive `'s`, then the quantity. The text `this repo's plugins` is such a frame.
- `havingFrame`: a word of the class `framing` (`has`, `have`, `holds`, `ships`, `carries` and the rest), or a `durative` verb followed by a `duration` word (`in`, `for`), or an `existential` word (`there`). An `existence` word (`are follows that `there``, `were`). An optional `hedge` word may stand before the quantity. These classes are in `rules/english-frames.xml`.
- `deicticFrame`: `the`, `these` or `those`, then the quantity, then up to a few words and a `deictic` word (`below`, `above`, `here`). The count is of what the page shows.

A quantity with no frame is ordinary technical prose and is not reported. The singular is not flagged, because a lone `one` is overwhelmingly a pronoun.

## Exemptions on a quantity

Each exemption is an exported function in `cardinal/quantity.go`. A match that any exemption of its substrate accepts is dropped.

| Exemption | Exempts | `Prose` | `Gate` |
| --- | --- | --- | --- |
| `ContinuesANumber` | A match that is the tail of a longer number. The byte before it is `.` or a digit | yes | no |
| `InExpression` | Arithmetic or a range. The previous rune is `-`, `+`, `/`, `*`, `=`, `.`, `,`, `_` or a digit, or the number sits in a clause with ` = ` | yes | yes |
| `FunctionWordGap` | A match shorter than a cardinal and a noun, or whose middle words include a function word of `gapStopWords` | yes | yes |
| `AfterAnArticle` | A number after `a` or `an` | no | yes |
| `ChoiceAmongASet` | The size of a set that something is picked from, after `of` and one of `one`, `either`, `neither`, `any`, `each`, `none`, `both` or `all` | no | yes |
| `StatusCode` | An HTTP status code | yes | yes |
| `Labeled` | A number after a label word | yes | yes |
| `SectionCite` | A number behind the section sign `§` | yes | yes |
| `IssueNumber` | The digits of the literal shape `issue #` followed by digits | yes | yes |
| `GPUName` | The digits of the literal shape `Vega ` followed by digits | yes | yes |
| `WordSize` | The literal shapes of 8, 16, 32 and 64 followed by `bits` | yes | yes |
| `NoPluralNounAfter` | A match whose last word the tagger does not read as a plural noun | no | yes |
| `Measure` | A quantity that takes a singular verb | yes | yes |

Details:

- `FunctionWordGap` reads only the words between the first and the last. A bare adjective run will otherwise swallow `of the format`. `gapStopWords` holds `of`, `the`, `a`, `an`, `in`, `on`, `to`, `for`, `and`, `or`, `is`, `are`, `was`, `were`, `that`, `this`, `with`, `from`, `by`, `at`, `as` and `but`. GapS also holds `if`, `so`, `than`, `then`, `when`, `while`, `not`, `no`, `it` and `its`.
- `StatusCode` applies when the leading number is in the class `status-code`. It holds when the next word is in the class `status-noun`. This holds when the word before is `status` or another status code. When a status code and a joiner (`or`, `and`, `nor`) come before, or when a joiner and a status code come after. A status is a value, so no edit moves it.
- `Labeled` reads the class `label`: `http`, `migration`, `migrations`, `rfc`, `pr`, `issue`, `version`, `release`, `port` and `revision`. A label word names the item the number identifies.
- `Measure` holds when the next word is in `singularVerbs`: `is`, `was`, `has`, `does`, `fits` and `equals`. It is one measured amount. A cut will leave a plural noun with a singular verb.
- `AfterAnArticle` holds because a tally takes no singular article. The number there is itself the noun.
- `NoPluralNounAfter` parses the text with the `syntax` package. If the number is a point on a scale (`APoint`), it holds only when `governsObject` is false. If the number names an item (`NamesAnItem`), it does not hold. Otherwise it holds when `NotAPluralNoun` finds that the last word is not tagged `NNS` or `NNPS`. A `VBZ` that follows only modifiers after a cardinal counts as a nominal when an earlier verb stands in the sentence. And the word is not an auxiliary (`is`, `has`, `does`, `was`).

### Points and items

`APoint(text, at)` answers the preposition before digits that set a point on a scale. The prepositions are `at`, `by` and `to`. For `to`, the point is not a point when the word before is `up`. A hedge word before the number (`exactly`, `about`, `roughly`, `around`, `approximately`, `nearly`, `almost`, `only`, `just`) is skipped, and the word before the hedge decides. A unit after the digits cancels the point, so a unit still takes a vague amount. The counts rule uses this to avoid writing `at multiple cols`.

`NamesAnItem(text, at)` reports digits right after a singular noun, such as `branch 3 sees` or `the Section 4 pins`. The digits name one item. It uses the tagger and rejects a word in `notNames` (for example `first`, `last`, `top`, `other`, `each`, `all`), a word ending in `most`, a preposition and a function-word tag. It treats a noun tagged `VBZ` or `JJ` without a plural ending as a noun. A sentence opener names an item only in lower case or before a finite verb. A capital there opens an instruction.

A noun that a number or one of `a`, `an`, `each`, `every`, `one` or `per` governs starts a second phrase. It does not name an item.

## Exemptions on a token

The `Comment` substrate reads tokens, not quantities. `tokensIn` splits a line into runs of name characters, so a URL, an import path and a version each stay whole. A name character is a letter, a digit, or one of the markers in `nameMarkers` (`._/:`) or `-`.

`walk` runs over the tokens. A token is exempt when any function in `ExemptToken` accepts it. A `TokenExemption` is `func(text string, toks []Token, i int) bool`. The list for `Comment` is, in order:

- `LabeledToken`: digits right after a label word, such as `HTTP 403` or `migration 014`.
- `ExitStatus`: digits after `exit`, `exits`, `exited`, `status`, `errno` or `signal`, with `code` or `codes` allowed between. A status is a value the program answers with.
- `Literal`: digits directly after one of the bytes in `literalMarkers` (`="'`), which are an assignment or a quoted string. Also digits after a comparison operator from `comparisonMarkers` (`=<>`), allowing blanks between.
- `SectionRef`: a token behind the section sign `§`.
- `Money`: digits with the currency sign `$` directly against them.
- `Quoted`: a token inside a quotation. A quotation is a pair of matching `"` or backtick marks, from `QuotedSpans`. An opening mark with no closer bounds nothing. The apostrophe is not a quote mark, because it spells a contraction or a possessive far more frequently than it opens a quotation.
- `ListMarker`: digits that open a numbered list item, such as `1.` or `2)`. Only indentation and the comment markers in `listLead` (blank, tab, `/`, `#`, `*`, `;`) may stand before it.
- `Operand`: digits that are code, such as the argument of a call or an operand next to `*` or `+`.
- `MeasureToken`: a number whose plural noun takes a singular verb from `singularVerbs`.
- `WordSizeToken`: 8, 16, 32, 64 or 128 followed by `bits` or `bit`.

`tokenNumber` then decides whether a surviving token carries a number.

- A token with `://` is a URL, and its digits are part of it.
- A qualified name (`isQualifiedName`) holds a marker from `nameMarkers` between word characters, such as `net/http`. It carries no number, whether the name has letters or not, once digits fail. The check order is: a qualified name with a letter yields nothing, then `digitNumber`, then a qualified name yields nothing, then `wordNumber`.
- `digitNumber` takes the first digit run. A digit that touches a letter, directly or past a binding hyphen, is part of a name, as in `sha256`, `amd64` or `10ms`. An ordinal suffix of `st`, `nd`, `rd` or `th`, with no letter after it, makes it a number again.
- `wordNumber` takes the first whole word in `s.Words`. A hyphen binds a number word into a compound that names a shape. A letter on either side of the word, or past a hyphen, rejects it.

## Leading and Find

`Leading` is the pattern `(?i)^(?:\d[\d,]*|<prose words>)\s+`. It matches the cardinal at the front of a quantity, with the blanks after it. The counts repair uses it to cut the cardinal off a `Prose` finding, because a `Prose` finding carries the whole quantity, as in `15 plugins`. `Token.Text` for a `Comment` finding is the number alone.

## Units

`IsUnit(word)` and `InClass(word, class)` read the `numbers` table. A measurement is still a stated count and is still reported. What differs is the repair. The tally rewording of a plural will leave `30 seconds` with no magnitude. A unit takes a vague amount instead. `counts/reword.go` owns that choice.

## Tests

`cardinal/detect_test.go` runs every case in `rules/numbers-detect.xml` against the substrate it names, from the map `prose`, `comment` and `gate`. A case with no `found` says the substrate reports nothing, which is how an exemption is written down. A new exemption therefore adds a case to the XML and edits no Go test. `cardinal_test.go` holds the vocabulary difference and the shape of a `Prose` finding.
