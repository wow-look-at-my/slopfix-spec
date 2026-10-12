# ste: Simplified Technical English

ASD-STE100 is a controlled language. Each approved word has a single meaning and part of speech. Its rules keep each sentence to a single reading. STE governs prose. It applies to a comment or a commit message as much as a document. The text that reaches `Check` is already a block joined to a single line.

The members share the sentence splitter, the masks and the repair pass. They therefore share a package. Each member still selects on its own by ID.

The warning rules read patterns that need a person to repair. A warning never fails `check`. `check --json` gives each finding a `severity` of `error` or `warning`. The language server sends a warning at warning level.

How a long sentence divides:

- A clause after `and` or `but` that names its own subject starts the new sentence. `but` and `yet` become `However,`.
- A clause after `, so` divides when it names its own subject, and `so` drops. A `so` with no comma states a purpose, and divides only behind a carrier.
- A verb group that shares the subject gets it again. A long subject becomes an agreeing pronoun.
- A closing `, which` clause opens with `This`. A closing `because` clause opens with `This is because`.
- A list, a quotation and a subordinate clause never divide at a clause boundary.
- The first half must hold a main clause.
- No division leaves part of a dash aside on each side. A division at the closing dash ends the aside with the sentence.
- A sentence with no boundary divides between words, as close to the cap as a good place allows. A comma. Then a word that opens a phrase, rank first. The first part never ends on a word that opens what it leaves out.
- The forced division never lands inside a code span, a link, a quotation or a parenthesis. A bold run that opens on the `and` the division drops opens the rest instead. The rest opens as it stands when it names its own subject or opens on an imperative. So does a clause after a dash or a colon, and an instruction after `, so`. A finite verb gets the subject again.
- Any other rest goes behind a carrier (`ste/carrier.go`). A phrase of place, a participle or a relative clause after a noun restates the noun: `That barn is behind the hills`. The rest of a list takes `It also covers`, or the subject and `also` before a list of verb groups. A purpose after an instruction takes `Do this so`.
- An opening subordinate clause or infinitive moves behind its main clause: `Y. This happens if X.` A main clause can point back into it, as `those files` does. That main clause keeps the order: `Suppose X. Then Y.` A long subject goes into a sentence of its own: `Consider a reader arriving at X. That reader still deserves Y.`

What `ste` does not flag:

- An inline code span, a link target and an HTML entity are masked. Every repair leaves them as they are.
- A comma splice needs a subject and a finite verb after the comma. A list, an Oxford comma, a participle and an infinitive do not qualify. Without a conjunction, the words before the comma must be a main clause.
- No repair rewrites inside a quotation.
- Text in parentheses counts as a single word. A citation thus cannot inflate a sentence.
- A period ends a sentence only when what follows opens the next. That rules out `e.g.` and `$(...)`. A file name or a section mark can open a sentence in lower case.
- `ste/count` exempts arithmetic, such as a range or an expression. It exempts no noun, because a duration or a size goes stale too.
- A number that picks an item from a list, as in `gate 5`, is a count.
- A cut keeps the sentence English. `over` and `above` always stay, so `over 32 banks` becomes `over many banks`. A capital moves only at the start of a sentence.
