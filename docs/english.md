# english: the prose table and english/comma-never

The `english` package holds the rule `english/comma-never` and the prose table that every wording repair reads. The rule is a `RuleSpec` in `rule_english_commanever.go` with category `RuleEnglish`. The table is `english/english.xml`, embedded into the binary with `go:embed` and parsed at run time by `mustLoad` in `english/english.go`. Its schema is `english/english.xsd`.

## english/comma-never

`english.IDCommaNever` rejects a contrast added as an afterthought with a comma and the word `never`. English that was edited writes `, not` for the same contrast.

### Detection

`english.CheckCommaNever(prose, line)` reads the text of a prose block. `Check` in `slopfix.go` calls it for each prose block of a document, with `block.Text()` and `block.Start`. Source files, workflows and chat messages are not read by this rule.

The pattern is `commaNever`, which is `(?i),(\s+)never\b`. It matches a comma, white space and the whole word `never`, in any letter case. A match is skipped when a code span or a quotation holds it (`unmasked`). The code span pattern is a pair of backticks on one line. The quotation pattern is a pair of straight or curly double quotes on one line.

The finding carries these fields.

- `ID` is `english/comma-never`.
- `Rule` is `a contrast added as an afterthought`.
- `Detail` is the matched text, from the comma through `never`.
- `Fix` depends on the word after the match. Before a verb it is the constant `fixNeverVerb`, which reads `Write ", and never" before a verb.` followed by the note that `slopfix fix` writes it. Elsewhere it advises `, not` or a sentence of its own.

### What is not flagged

- The word `never` with no comma before it, as in `it never fails, and it never waits`.
- A longer word that begins with the same letters, such as `nevertheless`, because the pattern ends on a word boundary.
- A match inside a code span or inside a quotation.

### Repair

`english.FixCommaNever` rewrites every match that `unmasked` returns. The fixer has the label `wrap-and-ste`. It is registered in `fix.go` for the family `wrap`, `ste` and `english`, reads `fixer.Document` files only, and has `Place` `30`. The repair runs only when the `english` family is wanted and `english/comma-never` is kept.

The replacement keeps the white space after the comma and picks one of three forms.

- `, not` is the default. A noun phrase or a participle after `never` reads right after `not`.
- `, and never` applies when `beforeVerb` is true and the clause is not an opening phrase, or when a third-person verb follows.
- `, do not` applies when `beforeVerb` is true, `finiteBefore` is false and `thirdPerson` is false. The words ahead of the comma are then an opening phrase, and `never` opens an instruction.

`beforeVerb` parses the sentence around the match with the `syntax` package. It skips adverbs, which carry the tag `RB`. It is true when the next word carries one of the tags `VB`, `VBP`, `VBZ`, `VBD` or `MD`. It is also true when the next word is followed by one of the pronouns `it`, `them`, `him`, `her`, `us` or `me`. This marks a verb the tagger missed. `finiteBefore` is true when a finite verb or a modal stands in the sentence ahead of the match.

`thirdPerson` is true when the first word after the adverbs, which end in `ly`, ends in `s` and not in `ss`.

The test cases in `english/commanever_test.go` hold the worked examples. For instance the text `The list names the fork, never its own tree.` becomes `The list names the fork, not its own tree.`

The rule has a registered case in `rule_english_commanever.go`. Detection must find the case. The repair must remove the finding, as for every rule.

## The table: english/english.xml

The root element is `english`. Its children are `class`, `drop`, `rewrite`, `pattern`, `shape`, `flag` and `test`. The `Table` struct names them. The file carries its tests beside each entry, and `mustLoad` panics at start when an entry lacks what it needs.

### Surfaces

A surface is the kind of text a repair reads. The constants are `english.Comment`, `english.Document` and `english.Message`, with the values `comment`, `document` and `message`. An entry limits itself with the `where` attribute. The value is a list of surfaces separated by white space. `AppliesTo` is true when `where` is empty, is `both`, or lists the surface. An entry with no `where` reads every surface.

### Entries

- `class` is a set of words that fill the same slot. `words` lists the members. `suffix` claims the words with an ending. `open` claims every word that no other class holds. `except` names classes that an open class gives up. A class with a word list is closed. The `english` package adds the class `indefinite`, taken from `rules/syntax.xml`.
- `drop` names a word or phrase that a repair deletes. The attribute `word` is required.
- `rewrite` swaps a phrase for another. The attributes `from` and `to` are required.
- `pattern` is a regular expression rewrite for a shape that a swap cannot express. `match` is a Go regular expression, and `replace` writes the groups as `$1` and `$2`. An empty `replace` cuts the match.
- `shape` is a rewrite over word classes in the match language of the `table` package. A capture is written `{class:name}`, and `{name}` in `replace` writes it back. A shape requires an `id`.
- `flag` names a phrase without a rewrite, where no single replacement is right. `phrase` and `say` are required, and `say` tells the author what to write.
- A `test` element that is a child of the root belongs to no entry. It states a line of prose and what the whole repair writes for it.

The schema names an optional `id` on every entry. `PatternIDs` returns the `id` of each pattern that has one.

### Tests

Every entry carries its tests. `mustLoad` panics when one of these is missing:

- A `drop` with no `word` or no test.
- A `rewrite` with no `from`, no `to` or no test.
- A `flag` with no `phrase`, no `say` or no test.
- A `shape` with no `match` or no test, or a `match` that does not parse.
- A `pattern` with no `match`, no test, a test with no expected output. A `subject` that is not a known position, or a `match` that does not compile.

An entry states a test in multiple ways. The attributes `test` and `expect` state the input and the expected output. A child `<test in= out=/>` adds more cases. A test whose `out` equals its `in` states that the entry leaves the text alone. The Go tests `TestEveryDropFires`, `TestEveryRewriteFires`, `TestEveryPatternFires`, `TestEveryShapeFires`, `TestEveryWholeLineCaseHolds` and `TestEveryFlagFires` run each case. A flag test must fire through `Flagged` and must come back unchanged from `Fix`.

### How a repair applies the table

`english.FixN(s, surface)` returns the new text and the number of rewrites. `Fix` returns the text alone. The order is fixed.

1. Every `rewrite` that applies to the surface. Rewrites go before drops, because a drop will otherwise cut the middle of a phrase such as `in order to`.
2. Every `drop`.
3. Every `shape`.
4. Every `pattern`, last, because a pattern must see text that a word swap settled.
5. Clean up. White space collapses to single spaces, a space before `.` or `,` closes, a stranded mark before a period goes, and a doubled period collapses. When a rewrite happened, `dropFragments` removes each sentence that a cut left with no finite verb where the original had one. The opening capital is restored (`capitalise`).

A `rewrite` and a `drop` match a whole word or phrase, case-insensitively, between word boundaries (`replaceWordN`). The word `just` does not touch `adjustment`. A hyphen counts as a word byte. A match is skipped inside a code span, inside a quotation, and when a capitalized match inside a sentence has a capitalized word. This happens after it (`inProperName`).

A `pattern` skips a match in these places (`ApplyN`):

- Inside the label of a markdown link, the text between square brackets before an opening parenthesis.
- Inside a quotation or a code span.
- At the hyphen of a compound word (`splitsCompound`).
- When the rewrite takes away a negation word and keeps the words it negates (`keepsNegation`). The negation words are `no longer`, `not`, `no`, `never`, `none`, `cannot`, `nobody`, `nothing`, `neither`, `nor`, `without` and any `n't`.
- When a cut to the end of the sentence strands an article, a relative word or a conjunction (`strandsOpener`).
- When the pattern names a `subject` and the clause does not state the sentence's own assertion (see below).

A replacement keeps the capital of the text it replaces (`keepCapital`). A cut, which is an empty replacement, takes the punctuation that attaches the phrase. `cutSpan` asks the `syntax` parse. A phrase between a pair of commas takes both. A phrase that ends its clause takes the comma before it. A phrase that opens its clause takes the comma after it.

A cut that will take some words of a noun phrase and leave others is refused. `join` then joins the sides with a single space, or with none before closing punctuation.

### Subject positions

The `subject` attribute of a pattern names where the subject of the clause stands. The constants are `SubjectMatched` and `SubjectPreceding`, with the values `matched` and `preceding`. `SubjectPositions` lists them, and a pattern that names any other value stops the program at load.

A change verb states a change in the code tree when the clause is the sentence's own assertion. A subordinator before the verb, or a noun the clause hangs off, makes it a condition on a value that the running code handled. The table cuts the first reading and leaves the second. `asserts` reads the word classes `noun`, `article`, `determiner`, `pronoun`, `relative` and `conjunction`. `matched` treats a noun against the left side of the match as the head the clause modifies. `preceding` walks back over a noun phrase to its head and requires that the head is no relative word, conjunction or noun.

### Word classes the table declares

The classes are `article`, `determiner`, `relative`, `conjunction`, `preposition`, `auxiliary`, `adverb`, `pronoun`, `verbform`, `noun`, `central`, `pleonastic`, `propped`, `plural`, `singular` and `ingnoun`. The class `verbform` claims the suffixes `ing` and `ed`. The class `noun` is open and excludes `verbform`. The class `plural` claims the suffix `s`. The class `singular` is open and excludes `verbform`, `plural` and `indefinite`. A word is looked up after trimming the edge marks `.,;:!?()[]{}"'` and a backtick, in lower case.

### The entries by group

Drops, all of them whole words or phrases. `actually`, `basically`, `essentially`, `fundamentally`, `simply`, `obviously`, `clearly`, `of course`, `in fact`, `indeed`, `really`, `very`, `quite`, `somewhat`, `fairly`, `just`, `note that`, `it is worth noting that`, `please note that`, `needless to say`, `at the end of the day`, `for the purposes of` and `with respect to`. The message surface adds `it is important to note that`.

Rewrites, each a phrase for a shorter one. `in order to`, `due to the fact that`, `in the event that`, `for the purpose of`, `a large number of`, `at this point in time`, `is able to`, `has the ability to`, `make use of`, `take into account`, `the reason is because`, `in spite of the fact that`, `a sufficient number of`, `prior to`, `subsequent to`, `in the near future`, `on a regular basis` and `whether or not`. The message surface alone rewrites an em dash before `and`, `but`, `so` and `which`, and rewrites `that being said` to `but`.

Shapes: `pleonastic-postdeterminer` removes `one`, `single`, `individual` or `particular` between a central determiner and a singular noun. `prop-word-one` removes `one` after a determiner that it props up. A hyphen binds a word into a compound, which a shape never reads across.

Flags: `fixme`, `somehow` and `no longer`. A flag is data with tests. No other package reads the flags in code.

Patterns for tombstones, with the `id` that selects each. The `tombstones` package reads these through `PatternIDs`, and its category is specified apart from this one.

- `tombstones/date` cuts a date written as year, month and day with the word that introduces it, a parenthesized date. A date at the edge of a parenthesis, and the year of a copyright line. The holder of a copyright stays.
- `tombstones/change-reference` cuts a pull request, issue, ticket or commit number.
- `tombstones/then-and-now-contrast` cuts `instead of` and `rather than` before an old, former, previous or legacy noun, and the clauses that start `where it used to` and `moved from`. It also cuts `this used to`, `previously`, `formerly`, `originally` and `hitherto`, `anymore`, `nowadays` and `these days`.
- Wording patterns without an `id` cut change verbs, review talk and process talk. They use the `subject` attribute where the verb needs it. They include `the old X` becoming `the X`, `this replaces`, `this change`, `worth noting`, `as requested`, `per the review`, `to be clear`, `negative control` and `I ran`. The two that name the owner, operator, user, reviewer or maintainer read the comment surface alone. This is because a document such as a CLAUDE.md states rules about what the user says.
- `tombstones/position-reference` cuts `as mentioned above` and `see above`, and the forms with `below`.
- `tombstones/hedged-time` cuts `for now`, `currently` and a `will be` clause that names a later time.
- `tombstones/unstated-value` rewrites `is TBD` to `has no set value`.
- `tombstones/shrug` cuts `for some reason`, `do not ask why` and `obviously`.
- `tombstones/unexplained-workaround` rewrites `a hack around` to `a workaround for` and `a magic number` to `a constant`.

Generic patterns have no `id`. One closes the white space before `,` `.` `;` `:` `!` and `?`. The other collapses a run of spaces. The first applies only when white space or the end of the text follows the mark, so a file name such as `.gitmodules` stays whole.

The pattern for `owner/repo#N` reads the message surface alone. It writes a markdown link to the issue on github.com. It carries the shape of a link and not the guarantee of the `link-refs` guard, which checks that the target exists. A bare number sign is deliberately absent, because it needs the repository of the reader.

The word `no longer` is a flag and not a pattern, because a cut will invert the sentence. The words `original` and `former` are absent from the cut patterns, because each is a noun as frequently.

## The XML under rules

The files `rules/english-*.xml` are embedded with the rest of `rules/` through `rules.FS`. The `english` package does not read them. It embeds `english/english.xml` alone. I found no reader of a table with the target `english` outside the tests of the `table` package.

Each file names its target in the `for` attribute of its root. The files `english-classes.xml` and `english-frames.xml` have `for="numbers"`. The files `english-concise.xml`, `english-filler.xml`, `english-message.xml`, `english-pattern.xml`, `english-sentence.xml` and `english-vague.xml` have `for="english"`. They use the vocabulary of `rules/rules.xsd`, where an entry has an `id` and a child `<test in= out=/>`. A pattern writes `to=` and not `replace=`. The schema of `english.xml` is separate, because the repair reads the tables through different code.

A change aimed at the incorrect table compiles and does nothing. Trace from the function that a test calls before adding an entry.

## See also

- [tombstones](tombstones.md) for the wording rules this table carries
- [markdown](markdown.md) for the prose blocks the rule reads
- [rules](rules.md) for the rule table and the fixer places
