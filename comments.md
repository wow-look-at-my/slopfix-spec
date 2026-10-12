# comments: what a comment gets wrong

These rules judge the comments of a source file. The `commentfix` package holds them. The `treecomments` package finds the comments, and the `code` package parses the file. The comment form of `ste/sentence-length` lives beside them in `commentfix/sentences.go`.

Every finding is an error. Every finding has a repair, and `Fix` runs the repairs until the text holds.

## Which files are read

`commentfix.Supported` answers whether the number rule reads a file. It is true when `treecomments.Supported` is true, or when `treecomments.HashComments` is true.

`treecomments.grammars` maps a lower-cased file extension to a tree-sitter grammar.

`treecomments.HashComments` adds files whose comments open on `#` and that the table does not name. The Bash grammar reads them, and `treecomments.Extract` keeps only the comments that open their line (`wholeLineOnly`). A file with an extension in neither table has no comments to read. The reason is that a `#` opens a directive in GLSL and a selector in CSS.

The length rule and the block pairing read a narrower set. `code.grammars` has the same extensions as `treecomments.grammars` without the hash-comment extensions. `commentfix.Parsed` and `code.LanguageFor` answer from it. A file outside that set yields no length finding.

A grammar with no generated parse tables yields no comments. `treecomments.reportMissingGrammar` then writes a line to stderr for each extension, naming `go generate ./grammars/...`.

`treecomments.Extract` takes every comment from the tree, in source order. A node is a comment when its type name contains `comment`. A marker inside a string literal is thus no comment. A syntax error does not stop `Extract`, because tree-sitter recovers around it. A hook reads a file mid-edit, so the number, tail and sentence rules answer on such a file. The length rule does not (see below).

`treecomments.Extract` then drops:

- The interpreter line that opens the file (`dropShebang`).
- The comment group that cgo reads as C source, right before a standalone `import "C"` (`dropCgoPreamble`).
- In a file named `_test.go`, an example's `Output:` or `Unordered output:` comment and each comment under it that adjoins it (`withoutExampleOutput`).

For a CMake file the lexer in `treecomments/cmake.go` replaces the Bash result. A bracket comment is no line comment. For a YAML file `yamlLineComments` restarts each comment at the `#` that opens its line.

`treecomments.Runs` groups comments into runs. A run is a stack of comments on adjacent lines with one left edge, each opening its line. A comment that follows code on its line starts a run of its own.

## Files and comments skipped by every rule here

- A file that `tombstones.Borrowed` names, and a file `commentfix.IsGenerated` marks. The `exempt` function in `fix.go` joins the two.
- A generated file. The marker is a line matching `generatedLine`, which reads `Code generated`, then any text, then `DO NOT EDIT.`, behind an optional comment opener. It counts only in the header: every earlier comment must have only blank text between it and the top of the file. For a language with no grammar the marker must head the file on its own line.
- A directive line, which addresses a tool. `treecomments.IsDirective` reads `// +build`, and a line comment with no space after the marker and a name followed by a colon, such as the `go:` forms. `commentfix.isDirectiveLine` adds a `//` or `#` line with a colon-terminated name that holds no space, the interpreter line, and a lint pragma.
- A lint pragma (`isLintPragma`). The words after a pragma are free text a person wrote, and the length rule reads them as prose.
- A license notice. A block with a line matching `licenseNotice` is neither measured nor repaired.
- A line with code in it (`codeLine`), such as a doc comment's tab-indented code block. Digits in code are no counts.
- A file the walk skips. A path git ignores is dropped, and so is a path `.gitattributes` marks with `linguist-vendored` or `linguist-generated` (`BorrowedAttributes`).

## comments/number

`commentfix.ID`. A number in a comment counts what exists today, and the edit that adds an item leaves it incorrect. The finding message is `a number in a comment is a count of what exists today`. The detail is the number.

Detection is `commentfix.Check`. It reads each run of comments, breaks the run into stanzas at every line that has a marker and no prose. It asks `cardinal.Find` with the `cardinal.Comment` substrate for each line. A number inside a quotation is skipped. A quotation can open on one line and close on a later line of the same stanza (`cardinal.QuotedSpans`). Directive lines and code lines never reach `cardinal.Find`.

The `cardinal.Comment` substrate reads the shape `Number`. It needs no frame. The words `zero` and `one` are absent, because they name a value or a pronoun. A repeat count and an ordinal are absent because neither counts a set. A word joined to other letters, such as `twoPhase`, is a name.

The finding fix is `Say it in words, or let the reader count. slopfix fix does this.` The constant `commentfix.Remedy` carries the longer advice. Describe what the code does, and cite a section by its slug or heading text and not by its position.

Repair is the fixer `FixerNumber`, whose label is `comments/number`. `repairNumbers` runs these steps on each paragraph of comment prose, in order.

A comment that loses all its prose loses its lines, delimiters included. When it follows code, only the comment goes. A block comment that has no prose but still shares its line with code keeps its delimiters.

`clearResidual` then reads `Check` again and deletes each number that remains, up to `residualPasses`, which is `8`. It deletes the whole numeric literal (`literalAround`) and closes the gap. After that, `danglingMarkers` deletes each bare comment marker line that has no prose under it. A repaired file therefore has no `comments/number` finding.

Every edit goes through `treecomments.Apply`. The gate refuses an edit that reaches a byte that is neither comment nor blank around it. It parses the source again and refuses an edit that changes any node that is not a comment. It also refuses an edit that damages a directive line.

## comments/length

`commentfix.IDLength`, the fixer `FixerLength` (label `comments/length`, `Place` `20`) and again `FixerLengthAgain` (label `comments/length-after-number`, `Place` `40`). A comment run weighs more than the code it documents.

The finding detail is the first non-blank line of the block, cut to `87` bytes and `...` when over `90`. The finding fix is `Cut the comment back inside the code it documents. slopfix fix does this.`

### What a block is

`treeBlocks` pairs each comment run with the construct beneath it, from the tree. It needs a parse with no error: `code.ParseWith` refuses a root with `HasError`. A file that does not parse yields no length findings.

- A run is comments on adjacent lines. A comment node that starts past the indent of its line trails. It opens no run.
- A run whose last comment shares its line with code after it is a note on that code. It is no block.
- The block spans whole lines. A grammar can end a comment node on the construct it documents. The block ends at the last line that opens with a comment marker (`opensWithMarker`). That check is off when the last comment opens with `/*`.
- The construct is the next named sibling after the run. An attribute run (a node type that contains `attribute`) is skipped to the item it decorates (`pastAttributes`).
- A run before a `cgo` `import "C"` is skipped, and so is the interpreter line.
- The block measures the code with `nodeSpan`. It counts the non-blank lines the node occupies and the non-whitespace characters, each line cut at the column where a comment starts there.
- At the top level of a file, each following sibling that starts on the very next line joins the span. That level is until a blank line or a comment on its own line (`paragraphSpan`). Inside a function body only the statement under the comment counts. A sequence node that starts with its first child is descended into (`isSequence`).
- With nothing after the run, the code is the directive lines of the block alone.
- In a file named `_test.go` the block ends at the line that opens an example's output (`withoutExampleOutput`). Blocks with a license notice are dropped (`withoutLicenseNotices`).
- A block above the `package` declaration of the file root has `header` set. `CheckLength` skips it.

### The measure

`measure` counts the non-blank lines of the block and its non-whitespace characters. Directive lines are not part of the block's prose (`prose`). The free text after a lint pragma adds its characters (`pragmaProse`).

`judge` fails a block in these cases:

- The block has no code (`codeLines` is zero) and has prose. The tell is `the comment documents nothing`.
- Its prose lines exceed `codeLines`.
- Its characters exceed `max(floorChars, codeChars)`, where `floorChars` is `120`, and `oneSentence` is false.

`oneSentence` is true for prose that `ste.Sentences` splits into a single sentence of at most `ste.SentenceWordCap` words, which is `25`. The block must also hold no banner line. A banner is a line whose text has no letter and no digit.

When both measures fail, the tells join with `, and `.

### Detection

`CheckLength` reports a block only when the repair brings it inside the budget. The block must be `exact` (decided by the tree). The repaired text must differ from the original and pass `judge`. A block that no cut fits keeps its opening sentence whole, so no finding names it. `report.go` (`pending`) also asks `CheckLength` of the text as written, so `check` reports a block that `Fix` will fit. The `Repairable` field of every hit is `true`.

### Repair

`lengthEdits` answers an edit for each block that fails `judge`. It never rewrites a block that is not `exact`. `maxLines`, from `Request.MaxCommentLines`, is the volume cap. When it is above zero it lowers `codeLines` to `maxLines` if the code is longer, so a long function does not buy an unbounded comment. The command line default of the cap is `tombstones.DefaultMaxCommentLines`, which is `14`. A cap of zero turns the cap off.

The cap alone judgs a header block (above `package`). When it holds more prose lines than `maxLines`, `capLines` cuts it.

The opening sentence is never cut. A block trimmed to nothing is a worse edit than a block left long. A block comment keeps its closer through every cut (`reclosed`). The Go convention of a bare `//` line between a doc and a directive after it is kept (`withSeparator`).

`wrapWidth` is `78`, the width `reflow` lays prose out at.

`capLines` serves the volume cap. It reflows, then calls `fitVolume`, which fits each plain paragraph to the characters its own lines carry by `ste.FitToBudget`. A list, heading or aligned line stands as written. Next it drops blank separator lines, then cuts last thoughts, then `dropToSentenceEnd`, which drops whole lines only when the last line kept ends a sentence. With no such line the run stays for a rewrite by hand.

### Clause cuts

`clauseCuts` reads `rules/comment-clauses.xml`. A mark ends a clause when a space follows it, and a word-length mark such as `--` needs a space before it too. Each opens a part the cut can drop and leave the claim before it true. A condition such as `when` or `if` is absent, because a cut before it changes the claim.

A candidate cut must keep balanced brackets, backticks and quotes (`balanced`). It must not end on a word of the `dangling` class. It must close a whole sentence (`closesWhole`), except a cut at a colon, which keeps the statement the colon elaborates. A kept part gets a period when it lacks a sentence end. The file carries its own `<test>` entries, for example a comment with a colon clause that cuts back to the text before the colon.

## comments/tail

`commentfix.IDTail`, run by the fixer `FixerNumber`. A comment stops on a word that opens what a cut took away. The finding rule text is `the comment stops on a word that opens what is no longer there`. The detail is the paragraph prose. The fix is `Finish the sentence, or let the repair close it. slopfix fix does this.`

Detection is `CheckTails`. For each paragraph of comment prose, `stopsMidThought` splits the prose into sentences with `ste.Sentences`. It takes the last word of the last sentence. The paragraph is a finding when that word does not end a sentence. Its lower-cased form, with trailing `.,;:!?)"'` removed, must also be in the class `dangling` of `rules/comment-tails.xml`.

The class `dangling` holds `and or but so yet then the a an to of in on at by for from with than rather that which who when while where because if is are was were as into over under per`. The class is closed on purpose: the language admits no new article, conjunction or preposition. A comment that reaches its full stop is never a finding, whatever word stands before the stop.

A paragraph is a run of comment lines with one marker, broken at a blank comment line, at a directive, and at a code line. A comment that follows code is a paragraph of its own. A block comment is one paragraph whatever blank lines it holds.

Repair is `CloseProse`. It splits into sentences and looks at the last.

1. If the last word does not dangle, or it ends a sentence, nothing changes.
2. A clause that stands alone is kept.
3. Otherwise `wholeHead` drops words from the end until the head stands as a sentence. The head has at least `minimumHead` words, which is `3`. It does not end on a dangling word or on an `auxiliary` word.

`standsAlone` asks `ste.StandsAlone`. A doc comment opens on the name it documents. A clause also stands alone when `ste.StandsAlone` accepts it with `It` in place of its first word. That first word must start with a capital, hold none of `,;:()`, and be absent from the `openers` set. The `openers` set is `if when because since while unless until although though after before so and but or as where whether once the a an this that these those each every all some no for with to in on at by from of then only also`.

The file `rules/comment-tails.xml` carries its own `<test>` entries. An unfinished clause closes where it last said something. A finished comment stays as written. A fragment after a finished sentence goes whole.

## ste/sentence-length in a comment

The rule id is `ste.IDSentenceCap`, which is `ste/sentence-length`. Its cap is `ste.SentenceWordCap`, which is `25`. Its comment form is separate from `comments/length`: a short comment can hold a sentence past the cap. Detection is `CheckSentences`. The fixer `FixerSentence` has the label `comments/sentence-length`, the family `ste` and `Place` `35`. It reads source files and workflows.

Detection reads each paragraph that `judged` accepts. `judged` rejects a verbatim paragraph, a paragraph with no prose, a paragraph with a lint pragma line, and a license notice. A paragraph divides into segments (`segmentsOf`). A segment is a run of lines with one paragraph of prose. A new segment begins at each of these places.

- A line with no prose.
- A line that starts with `@`.
- A line break that ends a thought with no stop (`lineEndsThought`).

`lineEndsThought` needs the line before the break to end on no mark and on no dangling word. It needs the line after the break to open with a capital or a list marker.

Within a segment, `sentences` splits on sentence ends, and a lower-case word also opens a sentence there. A comment sentence frequently opens on a parameter name. Each sentence goes through `ste.Check`. A finding carries the lines the sentence covers (`Line` and `EndLine`), the sentence, and the tell and fix of the STE rule.

Repair is `sentenceEdits`. Both halves must stay grammatical. The segment is laid out again at the width of its longest line, with its own marker, indent and continuation marker. A block comment aligns later lines under the opener's prose and keeps its closer. A comment after code, and a comment in a workflow, stay on one line.

A fixture holds the test that both repairs settle in one fix (`sentencecap_test.go`).

A sentence the rule cannot divide stays, and the finding asks for a rewrite by hand (`ste.ByHand`).

## Directives, doc comments and other shapes

- A comment above the `package` clause is a header. It is exempt from `comments/length` unless the volume cap applies.
- Every rule here skips a cgo preamble.
- A doc comment's code block, written with a tab after the marker, stays verbatim (`para.verbatim`). So does a block comment line that carries no marker and sits past the opener's prose column.
- A block comment with no closer is never rewritten (`blockPara` returns false).
- The empty block `/**/` is read as `/*` plus `*/`.

