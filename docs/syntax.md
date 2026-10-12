# syntax: the sentence parser

The `syntax` package parses an English sentence into phrases and clauses. It holds no rule ID. The `ste`, `cardinal` and `counts` packages and the comment repairs call it where a regular expression cannot tell the grammar apart. The package is `syntax/syntax.go` (types and word classes), `syntax/parse.go` (tagging, retagging and chunking), `syntax/clause.go` (clauses) and `syntax/print.go` (debug output).

## Entry point

`Parse(text string, opaque [][]int) *Sentence` is the only entry point. It runs these steps in order.

- It tokenizes the text with the `prose` tokenizer (`github.com/jdkato/prose/v3/tokenize`). Each `*` is first replaced by a space, because an emphasis marker is markup and not a word. A space keeps every byte offset into `text`.
- It tags each token with the averaged-perceptron tagger of `github.com/jdkato/prose/v3/tag`, which assigns Penn Treebank tags. The tagger model loads once per process, behind `sync.OnceValue`, because decoding it is the costly step. A model that does not load panics.
- It marks a word inside an opaque span as `NNP`. `opaque` holds `[start, end]` byte spans. A word is inside a span when it overlaps it, that is, when `start < span[1]` and `span[0] < end`. The callers pass code spans, parentheticals and quotations, because their words are data.
- It runs `retag`, then `chunk`, then `restoreVerbs`. When `restoreVerbs` changes a tag, `chunk` runs again.
- It runs `clauses`.

`Sentence` holds `Text`, `Words`, `Phrases` and `Clauses`. A `Word` holds `Text`, `Tag`, and `Start` and `End`, which are byte offsets into the text given to `Parse`.

## Opaque words and masks

A masked span reads as a name. A word made only of the letter `x`, with `len(Text) > 3` and not already `NNP`, is retagged `NNP`. `filler` recognizes the words a mask writes over a code span or a quotation. Those words are `CODE`, `QUOTE`, and any word longer than one byte made only of `X`.

## Word classes

The classes live in `rules/syntax.xml` (`for="syntax"`) and load through `table.MustLoad(rules.FS, "syntax")`. `Is(word, class)` lowercases the word and tests membership. `WordsOf(class)` returns the words of a class.

- `subordinator`: `because`, `although`, `though`, `unless`, `whereas`, `while`, `when`, `whenever`, `where`, `wherever`, `if`, `once`, `until`, `before`, `after`, `since` and `whether`.
- `coordinator`: `and`, `but`, `or`, `so`, `yet` and `nor`.
- `relative`: `which`, `who`, `whom`, `whose` and `that`.
- `definite`: `the`, `these`, `those`, `this`, `that`, `its`, `their`, `our`, `your`, `his`, `her` and `my`. A number names a pair leaves a quantifier such as `each` or `any`.
- `number-word`: the number words from `one` to `twenty`, then `thirty` to `ninety` in steps of ten, and `hundred`.
- `indefinite`: `nothing`, `everything`, `something`, `anything`, `nobody`, `everybody`, `somebody`, `anybody`, `everyone`, `someone` and `anyone`. These are pronouns the tagger reads as nouns. Like a determiner, they cannot follow a plural noun.
- `object`: `it`, `them`, `him`, `her`, `us` and `me`. An object pronoun follows a verb or a preposition and never a noun.
- `postposed`: `above`, `below`, `here` and `there`. A place word that follows the noun it places, as in `the case above`.
- `person`: nouns that name a person and take `they` and not `it`, such as `user`, `caller`, `author`, `owner`, `reader`, `maintainer`, `operator`, `developer` and `agent`. That `person` is with their plurals.

`Sentence.Person(p)` tests the head of a phrase against `person`.

## Retagging

`retag` corrects tags that a clause test depends on and the tagger gets incorrect. Each case is a `switch` branch in `syntax/parse.go`. The branches, in order:

- `n't` and `not` become `RB`.
- A finite-verb tag on a dotted name, such as an identifier, a path or a version, becomes `NN`. `dottedName` requires a `.`, `/` or `_` between word characters.
- A bare form that follows a modal, tagged `IN` or `JJ` and followed by a word that can open an object, becomes `VB`.
- A word of capitals that is a key of `emphasized` takes that tag. The map covers `does`, `is`, `has`, `do`, `are`, `have`, `did`, `was`, `were`, `must`, `can`, `will`, `should` and `cannot`.
- A bare form after a plural noun and a `postposed` word, followed by a preposition, becomes `VBP`.
- `cannot` becomes `MD`.
- A plural noun after an adverb that follows a noun, and before a word that opens a noun phrase, becomes `VBZ`. The first word of a package comment, `Package`, makes the third word the verb.
- A dash (`—`, `–` or `--`) becomes `:`.
- A word in the `coordinator` class that is not already `CC` becomes `CC`, except `so` and `yet`.
- A plural noun after `CC` and before a word that opens a noun phrase becomes `VBZ`.
- A plural noun with a verb ending after a colon, where the words before the colon hold a clause, becomes `VBZ`.
- A plural noun after a singular noun and before an `object` word becomes `VBZ`.
- A plural noun in second position, after a code identifier and before a word that can open an object, becomes `VBZ`. The identifier becomes `NNP`.
- A bare `VB` with an `-s` ending, not after `TO` or `MD`, becomes `VBZ`.

After the loop, a sentence may open in lower case on a word followed by an `-s` form and an object opener. The first word then reads as a name and the second as `VBZ`. A last pass handles more shapes. A `VBD` after a noun and a comma, before an adjective or adverb, becomes `VBN`. A participle that opens a noun phrase whose own verb follows becomes `JJ` (`participleAdjective`). A `VBZ` after a `filler` word and before a comma or a relative word becomes `NNS`.

`verbEnding(word)` is true for a word that ends in `s` and not in `ss`, `us` or `is`.

## Verb restoration

`restoreVerbs` repairs a compound noun that hides a verb, as in `the write fails`. The tagger reads that as a plural compound noun. Rest repairs a stretch between dividing words. With no finite verboreOne`. The dividing words, from `divides`, are a comma, a colon, `CC`, `WDT`, `WP`, and an `IN` or `WRB` word in the `subordinator` class.

`restoreOne` retags the head of the earliest compound whose number shows it is a verb.

- A plural noun after a singular noun or name becomes `VBZ`.
- A singular noun after a plural noun becomes `VBP`.
- A singular noun after a singular noun, with a verb ending, becomes `VBZ`.
- A plural head after a `filler` word and before a comma, a relative word. Otherwise, `that` stays a noun, as in a list of named rules.

The function `restoreOpener` handles a sentence that opens on an `-s` form with no subject, such as a doc comment that names its function. The word becomes `VBZ` when the word after it is a preposition, `TO`, or can open an object. A compound that follows another noun phrase directly opens a clause of its own, and `restoreVerbs` repairs it. `innerVerb` finds an `-s` form between a singular noun and a name, as in `the vkbench needs` followed by a name.

## Phrases

`chunk` groups the words into phrases. A phrase is a `NounPhrase` or a `VerbGroup`. `Phrase` holds `Kind`, `First` and `Last`, `Head`, `Det`, `Numerals`, `Finite`, `Imperative` and `Coordinated`.

A noun phrase (`nounPhrase`) reads an optional `PDT`, a determiner (`DT`, `PRP$` or `WP$`), the numerals (`CD` words), the modifiers and the head nouns. A `PRP` or `EX` word is a noun phrase by itself. A possessive `'s` (`POS`) turns the phrase read so far into the determiner of the longer phrase, so `Det` then points at the `'s`. The modifiers (`modifiers`) are adjectives, a `CD`. This holds before a noun or adjective, a `VBN` or `VBG`. Participle after a determiner or adjective and before a noun, and a hyphen after an adjective.

A phrase with no noun is pronominal: the last numeral becomes the head, or a bare `DT` becomes the head.

A verb group (`verbGroup`) reads leading adverbs, then verbs, `TO`, `RP` and adverbs that lead into a verb. A leading adverb joins when a verb follows it. A second finite verb ends the group. `Finite` is true when the lead verb is `MD`, `VBZ`, `VBP` or `VBD`. Chun sets Imperative`k`.

Methods on `Sentence`:

- `Span(first, last)` returns the source text from word `first` to word `last`, both included. It returns an empty string for a bad range.
- `PhraseAt(i)` returns the phrase that covers word `i`.
- `NounPhrases()` returns every noun phrase in source order.
- `Plural(p)` is true for a coordinated phrase, a head tagged `NNS` or `NNPS`, and a `PRP` head that is `we`, `they`, `us` or `them`.
- `Person(p)` is true when the head is in the `person` class.

## Clauses

`clauses` cuts a chunked sentence into `Clause` values. A clause holds `First` and `Last`, `Link`, `Kind`, `Comma`, `Subject`, `Verb` and `Depth`. `Link` is the word that attaches the clause. It is negative when no word does. `Comma` is true when a comma stands directly in front of the link. `Subject` is nil when the clause shares its subject with an earlier clause, or when a relative word is its subject.

Last trims trailing punctuationWord`.

`LinkKind` has the values `Opens`, `Coordinate`, `Subordinate`, `Relative` and `Punctuated`.

### Boundaries

`boundary` decides whether a word opens a clause. The cases, in order:

- A `;`, `:`, `—`, `–` or `--` opens a `Punctuated` clause.
- A `CC` directly after a link. That `CC` is in a clause. This holds with no verb yet and no comma, where a noun phrase and verb follow the link, joins the halves of the clause subject. It opens nothing.
- A `CC`, or `so` after a comma, opens a `Coordinate` clause when `opensAfterConjunction` holds. That holds when a gerund subject follows, when a finite verb group follows. A verb is already known, when a bare verb follows an imperative main clause, or when a subject and finite verb follow. Otherwise the conjunction joins phrases, as in `files and directories`.
- `that` after `CC` inside a `Relative` clause opens another `Relative` clause.
- A subordinator opens a `Subordinate` clause. `subordinator` accepts `so that`. A `that` tagged `IN` that is not a relative, `as long as` and `as soon as`, and any `subordinator` class word that is not followed by `of`. The ambiguous words `before`, `after`, `since`, `until` and `once` count only when a subject and finite verb follow them (`subjectVerbAt`), so `after the merge` is a preposition.
- A relative word opens a `Relative` clause: a `WDT`, `WP` or `WP$` word in the `relative` class, or a `that` that `relativeThat` accepts. `relativeThat` requires a noun before `that` and a finite verb after it, with adverbs allowed between, or an object relative that `objectRelativeAt` accepts.
- After a comma, in a subordinate clause at positive depth that has its verb. It opens the sentence, a subject followed by a finite verb opens the main clause with kind `Opens`.
- After a comma, in the first subordinate clause that opens the sentence, an imperative verb group opens the main clause.

A clause that holds no word before the link takes the link as its own opener. Otherwise the open clause is closed and a new one starts.

### Depth

`depthOf` gives the depth of a new clause. A `Subordinate` or `Relative` clause is one deeper than the clause before it. A `Coordinate` clause has the depth of the clause before it. Any other kind is depth `0`. These adjustments apply:

- A `Coordinate` clause inside a deeper clause returns to depth `0` when `returnsToMain` holds. That holds when a comma precedes the conjunction. It also holds when the next verb has the form of the main verb and not the form of the subordinate verb.
- A `Relative` clause after a `Relative` clause joined by `CC` keeps the depth of the first.
- A `Relative` clause after a `Coordinate` clause that follows a `Relative` clause takes the depth of that earlier relative.

### Subject and verb

`attach` records the first verb group of a clause as its verb. A finite group is the verb. A group with no subject, a lead tag of `VB`, and only adverbs before it, is an imperative. Its `Imperative` field is set. Any other non-finite group is not a clause verb.

`subjectBefore` finds the subject as the noun phrase that ends before the verb. It skips adverbs, and a quantifier (`all`, `both`, `each`) or `postposed` word that floats off the subject. It extends the phrase back through prepositional phrases, so `The file in the cache` is the subject of `holds`. A phrase joined by `CC`, and a comma list of noun phrases before it, form a coordinated subject with `Coordinated` set. A gerund and its object are the subject when a finite verb follows, as in `adding a rule is`. A subject and finite verb with no mark before a later finite verb form a reduced relative, and the later verb is the clause verb.

`resume` returns to a clause that waits for its verb. After a relative or subordinate clause that already has a verb, a new finite verb group resumes the interrupted clause. The new clause has kind `Opens`, takes the parent subject and has the parent depth. It applies to a relative clause that interrupts a parent with no verb. That clause is to a leading gerund clause that is the subject, and to a leading subordinate clause whose main subject sits before the verb. A reduced relative is not resumed.

### Not clauses

Nouns joined by a conjunction open no clause. Neither does an ambiguous subordinator, such as `after`, that no subject and finite verb follow.

## Debug output

`print.go` writes these views of a parsed sentence.

- `Brackets()` writes the sentence with each noun phrase in square brackets and each verb group in angle brackets.
- `Outline()` writes a line for each clause, as `kind/depth subject="..." verb="...": text`, with `-` for a missing subject or verb. The kind names are `opens`, `coordinate`, `subordinate`, `relative` and `punctuated`.
- `Tags()` writes each word as `word/TAG`.

The tests in `syntax/syntax_test.go` use these to state behavior, for example that `The gate reads every file and refuses the write.` has a coordinate clause with no subject and the verb `refuses`.

## See also

- [ste-simplified-technical-english](ste-simplified-technical-english.md) for a caller of the parser
- [english](english.md) for the `english/comma-never` rule that reads a verb
- [cardinal](cardinal.md) for the point and item tests
