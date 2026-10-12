# syntax: the sentence parser

The `syntax` package parses an English sentence into phrases and clauses. It holds no rule ID.

## Entry point

`Parse(text string, opaque [][]int) *Sentence` is the only entry point. It runs these steps in order.

- It tokenizes the text with the `prose` tokenizer (`github.com/jdkato/prose/v3/tokenize`). Each `*` is first replaced by a space, because an emphasis marker is markup and not a word. A space keeps every byte offset into `text`.
- It tags each token with the averaged-perceptron tagger of `github.com/jdkato/prose/v3/tag`, which assigns Penn Treebank tags. The tagger model loads once per process, behind `sync.OnceValue`, because decoding it is the costly step. A model that does not load panics.
- It marks a word inside an opaque span as `NNP`. `opaque` holds `[start, end]` byte spans. A word is inside a span when it overlaps it, that is, when `start < span[1]` and `span[0] < end`. The callers pass code spans, parentheticals and quotations, because their words are data.
- It runs `retag`, then `chunk`, then `restoreVerbs`. When `restoreVerbs` changes a tag, `chunk` runs again.
- It runs `clauses`.

## Opaque words and masks

A masked span reads as a name. A word made only of the letter `x`, with `len(Text) > 3` and not already `NNP`, is retagged `NNP`. `filler` recognizes the words a mask writes over a code span or a quotation.

## Word classes

The classes live in `rules/syntax.xml` (`for="syntax"`) and load through `table.MustLoad(rules.FS, "syntax")`. `Is(word, class)` lowercases the word and tests membership. `WordsOf(class)` returns the words of a class.

`Sentence.Person(p)` tests the head of a phrase against `person`.

## Retagging

`retag` corrects tags that a clause test depends on and the tagger gets incorrect. Each case is a `switch` branch in `syntax/parse.go`. The branches, in order:

- `n't` and `not` become `RB`.
- A finite-verb tag on a dotted name, such as an identifier, a path or a version, becomes `NN`.
- A bare form that follows a modal, tagged `IN` or `JJ` and followed by a word that can open an object, becomes `VB`.
- A word of capitals that is a key of `emphasized` takes that tag.
- A bare form after a plural noun and a `postposed` word, followed by a preposition, becomes `VBP`.
- `cannot` becomes `MD`.
- A plural noun after an adverb that follows a noun, and before a word that opens a noun phrase, becomes `VBZ`. The first word of a package comment, `Package`, makes the third word the verb.
- A word in the `coordinator` class that is not already `CC` becomes `CC`, except `so` and `yet`.
- A plural noun after `CC` and before a word that opens a noun phrase becomes `VBZ`.
- A plural noun with a verb ending after a colon, where the words before the colon hold a clause, becomes `VBZ`.
- A plural noun after a singular noun and before an `object` word becomes `VBZ`.
- A plural noun in second position, after a code identifier and before a word that can open an object, becomes `VBZ`. The identifier becomes `NNP`.
- A bare `VB` with an `-s` ending, not after `TO` or `MD`, becomes `VBZ`.

After the loop, a sentence may open in lower case on a word followed by an `-s` form and an object opener. The first word then reads as a name and the second as `VBZ`. A last pass handles more shapes. A `VBD` after a noun and a comma, before an adjective or adverb, becomes `VBN`. A participle that opens a noun phrase whose own verb follows becomes `JJ` (`participleAdjective`). A `VBZ` after a `filler` word and before a comma or a relative word becomes `NNS`.

## Verb restoration

`restoreVerbs` repairs a compound noun that hides a verb, as in `the write fails`. The tagger reads that as a plural compound noun. Rest repairs a stretch between dividing words. With no finite verboreOne`.

`restoreOne` retags the head of the earliest compound whose number shows it is a verb.

- A plural noun after a singular noun or name becomes `VBZ`.
- A singular noun after a plural noun becomes `VBP`.
- A singular noun after a singular noun, with a verb ending, becomes `VBZ`.
- A plural head after a `filler` word and before a comma, a relative word. Otherwise, `that` stays a noun, as in a list of named rules.

The function `restoreOpener` handles a sentence that opens on an `-s` form with no subject, such as a doc comment that names its function. The word becomes `VBZ` when the word after it is a preposition, `TO`, or can open an object. A compound that follows another noun phrase directly opens a clause of its own, and `restoreVerbs` repairs it. `innerVerb` finds an `-s` form between a singular noun and a name, as in `the vkbench needs` followed by a name.

## Phrases

`chunk` groups the words into phrases. A phrase is a `NounPhrase` or a `VerbGroup`.

A `PRP` or `EX` word is a noun phrase by itself. A possessive `'s` (`POS`) turns the phrase read so far into the determiner of the longer phrase, so `Det` then points at the `'s`. This holds before a noun or adjective, a `VBN` or `VBG`. Participle after a determiner or adjective and before a noun, and a hyphen after an adjective.

A phrase with no noun is pronominal: the last numeral becomes the head, or a bare `DT` becomes the head.

A verb group (`verbGroup`) reads leading adverbs, then verbs, `TO`, `RP` and adverbs that lead into a verb. A leading adverb joins when a verb follows it. A second finite verb ends the group. Chun sets Imperative`k`.

## Clauses

`clauses` cuts a chunked sentence into `Clause` values. `Link` is the word that attaches the clause. It is negative when no word does. `Comma` is true when a comma stands directly in front of the link. `Subject` is nil when the clause shares its subject with an earlier clause, or when a relative word is its subject.

Last trims trailing punctuationWord`.

### Boundaries

`boundary` decides whether a word opens a clause. The cases, in order:

- A `CC` directly after a link. That `CC` is in a clause. This holds with no verb yet and no comma, where a noun phrase and verb follow the link, joins the halves of the clause subject. It opens nothing.
- A `CC`, or `so` after a comma, opens a `Coordinate` clause when `opensAfterConjunction` holds. That holds when a gerund subject follows, when a finite verb group follows. A verb is already known, when a bare verb follows an imperative main clause, or when a subject and finite verb follow. Otherwise the conjunction joins phrases, as in `files and directories`.
- `that` after `CC` inside a `Relative` clause opens another `Relative` clause.
- A subordinator opens a `Subordinate` clause. `subordinator` accepts `so that`.
- `relativeThat` requires a noun before `that` and a finite verb after it, with adverbs allowed between, or an object relative that `objectRelativeAt` accepts.
- After a comma, in a subordinate clause at positive depth that has its verb. It opens the sentence, a subject followed by a finite verb opens the main clause with kind `Opens`.
- After a comma, in the first subordinate clause that opens the sentence, an imperative verb group opens the main clause.

A clause that holds no word before the link takes the link as its own opener. Otherwise the open clause is closed and a new one starts.

### Depth

`depthOf` gives the depth of a new clause. A `Subordinate` or `Relative` clause is one deeper than the clause before it. A `Coordinate` clause has the depth of the clause before it. Any other kind is depth `0`. These adjustments apply:

### Subject and verb

`attach` records the first verb group of a clause as its verb. A finite group is the verb. A group with no subject, a lead tag of `VB`, and only adverbs before it, is an imperative. Its `Imperative` field is set. Any other non-finite group is not a clause verb.

`subjectBefore` finds the subject as the noun phrase that ends before the verb. It extends the phrase back through prepositional phrases, so `The file in the cache` is the subject of `holds`. A phrase joined by `CC`, and a comma list of noun phrases before it, form a coordinated subject with `Coordinated` set. A gerund and its object are the subject when a finite verb follows, as in `adding a rule is`. A subject and finite verb with no mark before a later finite verb form a reduced relative, and the later verb is the clause verb.

`resume` returns to a clause that waits for its verb. After a relative or subordinate clause that already has a verb, a new finite verb group resumes the interrupted clause. The new clause has kind `Opens`, takes the parent subject and has the parent depth. It applies to a relative clause that interrupts a parent with no verb. That clause is to a leading gerund clause that is the subject, and to a leading subordinate clause whose main subject sits before the verb. A reduced relative is not resumed.

### Not clauses

Nouns joined by a conjunction open no clause. Neither does an ambiguous subordinator, such as `after`, that no subject and finite verb follow.

## Debug output

`print.go` writes these views of a parsed sentence.

The tests in `syntax/syntax_test.go` use these to state behavior, for example that `The gate reads every file and refuses the write.` has a coordinate clause with no subject and the verb `refuses`.
