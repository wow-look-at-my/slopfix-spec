# tombstones: a comment about a state the code has left

A tombstone describes a state the code left, or argues for the diff instead of telling the next editor what breaks. The `tombstones` family holds the rules that find one. Each rule has an ID that begins with `tombstones/`. `AllIDs` in `tombstones/tells.go` returns the full set: `IDVolume`, the dead-referent ID, and the ID of every entry in `english/english.xml` that carries an `id` attribute. That attribute starts with `tombstones/`. One fixer, named by the constant `Name` (value `tombstones`) in `tombstones/repair.go`, repairs all of them.

It is registered with `Place` set to `10`, for `fixer.Source` and `fixer.Document` files, with the rules of `AllIDs` as its `Rules`.

The hook entry in `hooks.go` runs `slopfix hook --only tombstones --max-comment-lines <n>`. The flag `--max-comment-lines` on `hook` and on `check` defaults to `DefaultMaxCommentLines`, which is `14`. A value of `0` turns the volume cap off.

## What is judged

Only prose is judged (`AddedBlocks` in `tombstones/comments.go`). A block is a `Block` with its text, the lines that weigh against the cap, and the zero-based line numbers. The zero-based line also is a purity flag for each line, an optional list prefix, and `Prose`. `Prose` is the text with every byte outside a comment blanked.

- Source: `code.Runs` returns each comment run from a tree-sitter parse. A path no grammar parses, or a file whose parse has an error, yields no block. A string literal that holds `previously` is code and is never judged. `Block.Lines` counts the lines of the run that are comment alone and are not a directive (`treecomments.IsDirective`). A line that shares its row with code is not pure. A run of generator directives therefore never reaches the volume cap.
- Documents: `IsDocument` is true for a path with the extension `.md`, `.markdown`, `.rst`, `.txt` or `.adoc`. It is false under a `testdata` directory and for a path `treecomments.HashComments` names as hash-comment code, such as a `CMakeLists.txt`. `paragraphs` takes the prose blocks that `markdown.Split` returns. A fence, a heading, a quotation, HTML, frontmatter and indented code are not prose. `blankInlineCode` blanks each backtick span, so a phrase inside a span is a literal and never a claim. Every line of a paragraph is pure. `Prefix` holds the indentation and list marker that open the paragraph. A rewrite writes it back so a nested item stays in its list.
- Borrowed text: `Borrowed` is true. This holds for a path under a `vendor` or `node_modules` directory, and for a path that `.gitattributes` marks with `linguist-vendored` or `linguist-generated` (`commentfix.BorrowedAttributes`, read through `git check-attr` and cached for each absolute path). `exempt` in `fix.go` adds `commentfix.IsGenerated`. No rule reads or rewrites such a file. `TestAPathMarkedVendoredIsBorrowed` in `tombstones/vendored_test.go` proves that a repair leaves it unchanged.

The input may be a fragment, so a scanner that starts mid-string can read code as a comment. That costs a false finding at worst.

## The wording rules

A wording rule is an entry of `english/english.xml` with an `id`. Each entry cuts the phrase and not the line, so the rest of the sentence survives. Git history keeps what the phrase narrated. `rule_tombstones_patterns.go` registers one rule for each ID. Its detection reports the rule when any entry of that ID rewrites the text. The finding says `a phrase about a state the code has left`, names the entry's match pattern as the detail.

It gives the fix text `Cut the phrase. slopfix fix does this.` The autofix applies every entry of the ID. Every entry carries `where="comment document"`, so each applies to a source comment and to a document paragraph. The worked examples in the table are the tests of each entry.

- `tombstones/date`: an ISO date, `YYYY-MM-DD` with a year in `19xx` or `20xx`, with the word `on`, `as of` or `since` in front of it. A date inside parentheses goes with them, as in `status (2026-07-21): file I/O works` becoming `status: file I/O works`. A date that opens a parenthesis with a separator after it. Or ends one with a separator before it, goes alone and leaves the parentheses balanced. Any other bare date goes. A copyright year or year range after `copyright`, with an optional `(c)` or the copyright sign, is cut on purpose, and the holder stays. `Copyright 2019-2026 The Go Authors.` becomes `Copyright The Go Authors.`
- `tombstones/change-reference`: `pr`, `pull request`, `issue`, `ticket` or `commit`, an optional `#` and digits, with an optional leading `see` and optional parentheses.
- `tombstones/then-and-now-contrast`: `instead of` and an optional `the`, then `old`, `former`, `previous` or `legacy` and the next word.
- `tombstones/position-reference`: `as mentioned`, `as noted` or `as described` before `above` or `below`, and `see above` or `see below` with the rest of the sentence.
- `tombstones/hedged-time`: `for now`, `currently`, and `will be` followed later in the sentence by `later`, `soon`, `eventually`, `someday` or `in a future`/`in the future`, with the rest of the sentence.
- `tombstones/unstated-value`: `is TBD` or `is to be determined`, replaced with ` has no set value`.
- `tombstones/shrug`: `for some reason`, `do not ask why` or `do not ask how` with the rest of the sentence, and `obviously`.
- `tombstones/unexplained-workaround`: `a hack around` becomes `a workaround for`, and `a magic number` becomes `a constant`.

An entry with no `id` still rewrites when the table is applied to a comment or a paragraph. However, it names no rule, so no report or `--only` selector reaches it. The unnamed entries in the same section of the table cover the same ground: other forms of `old`, `previous` and `legacy`. A change verb with a source or an agent (`moved from`, `we removed`, `this replaces`, `was renamed`), the words `previously`, `formerly`, `originally`, `anymore`, `nowadays`, and the voice of a review (`this PR`, `per the review`, `as requested`, `negative control`, `we ran`, `to be clear`). The entries that read `the owner said` and `per the owner` apply to comments only, because a document such as a `CLAUDE.md` states rules about what the user says.

A cut never removes a negation while the words it negates stay. The words `no longer` are therefore absent from the table, and so are `original` and `former` alone. This is because each is a noun as frequently as an adjective. An entry with a `subject` attribute (`preceding` or `matched`) rewrites only when the subject of the clause fits that reading. A change verb inside a subordinate clause is left alone.

## Repair of wording

`repairFile` in `tombstones/repair.go` runs the wording repair first.

- Source: `rewriteComments` runs `commentfix.Tighten` on every block whose lines are all pure (`pureSpan`). A block with a line shared with code is never rewritten, because the rewrite will carry the code. The block is replaced as lines and the replacement is reflowed onto the block's own marker at the column `wrapWidth` (`78` in `commentfix`). A comment that was only a tombstone is deleted whole: `// This used to read the flag.` above a function leaves the function alone (`TestAWordingTellIsRewrittenOutOfSource`).
- Documents: `rewriteParagraphs` skips a paragraph that holds a backtick. Otherwise it joins the paragraph body, runs `english.FixN(body, english.Document)`, and writes the result back as a single line with the same `Prefix`. A paragraph left with no letter or digit is deleted (`hasWord`).
- A rewrite that a gate refuses is not lost. In a document each refused edit yields a finding through `wordingHits` for every wording rule whose phrase the edit span still holds. In source, `phraseCuts` cuts the phrase from each remaining pure comment line with `commentfix.RewriteLineProse` and `cutTombstones`, and `phraseHits` reports any phrase still present. A scope can hold some lines of a block and not others. This is the case it serves.
- The findings carry the tell `a phrase about a state the code has left` and the line number counted from one.

## tombstones/name-nothing-in-the-repository-defines

The ID is `IDDeadReferent`. `ruleID` builds it from the tell `a name nothing in the repository defines` (constant `deadReferent`). Lowercase, a leading `a `, `an ` or `the ` removed, each space turned into a hyphen, and the prefix `tombstones/` added. This rule reads no wording. A comment that names a symbol found nowhere in the repository describes a tree that is gone, as in a pointer to a deleted test. Its finding detail is the name.

The fix text is `Cut the sentence that names it. slopfix fix does this.` The rule registers multiple cases: a Go doc comment naming `parseLegacyFlag`, and a JSDoc closer line.

### Candidates

`DeadReferents` in `tombstones/referents.go` takes names from `Block.Prose` only, split by `identifierWords` on every byte outside letters, digits and the underscore. Code on a shared line names what it uses. The repository answers for that, so it never supplies a name. A word is a candidate when `isCandidate` accepts it:

- Its length is at least `minCandidate`, which is `8`.
- It is not all capitals (`name != strings.ToUpper(name)`).
- `identifierShaped` is true: the first byte is not a digit. The word has an underscore, or an upper-case letter that follows a lower-case letter or a digit. Otherwise, it starts with a capital and holds a digit.

In a document, `documentName` first trims underscores from both ends of the word and then keeps it only if an underscore remains inside. Emphasis such as `_already established_` and a product name such as `PCRE2Project` name nothing.

A name is dropped before any search when:

- the added text holds it more than once, because the text says where else it sits.
- `foreignInGo` is true: the path ends in `.go`. The name has an underscore. The name does not start with `Test`, `Benchmark`, `Example` or `Fuzz`, so a C name. Otherwise, a kernel field in a Go comment is not judged.
- `namesAFile` is true: a word of a path that `git ls-files --cached --others --exclude-standard` lists spells the name. Otherwise, the name ends in an underscore and starts a word of such a path.

The rule answers nothing, and so reports nothing. This happens when the path is outside every work tree (`RepoRoot` walks up to a `.git` directory or file), when the blocks name no candidate, or when they name more than `maxNames`. Which is `40`. An absent answer never reads as a missing symbol.

### The probe and the index

A name is dead when no file of the repository other than the file being judged holds it as a whole identifier. The copy of the file on disk holds the comment itself. It does not count (`holdsBeyond` subtracts it).

- Ripgrep probe: for each name, `rg --no-messages --fixed-strings --word-regexp --files-with-matches --max-count 1 -e <name> <root>`. Prob bounds the searcheTimeout`, which is `2` seconds. A timeout, or a ripgrep exit code above `1`, abandons the whole answer. A name is dead when the output lists no file other than the one being judged.
- Index: `symbolIndex.build` lists the files git knows under the root, tracked and untracked unless ignored. It reads each file and skips one over `indexFileCap` (`4 << 20` bytes), one with a NUL byte in its first `8000` bytes, and one it cannot read. It counts, for every candidate word, the files that hold it. Inde bounds the readxTimeout`, which is `5` minutes. An incomplete read leaves the index unusable. A built index answers every name with no probe, and a name it never saw is dead. An ignored file stays out of the index as it stays out of the probe.
- Choice between them: `indexFor` returns an unbuilt index for the first `probeBudget` calls of a process, which is `50`, and so the probe answers. After that it builds the index once. `PrimeIndex` builds the index at once and adds `probeBudget` to the call counter. A tree walk calls it first. With no ripgrep on the path, the index is built on the first need and answers every name. With neither, the rule answers nothing.

### Reporting

`HitForName` returns the `Hit` for a name from the first block whose prose holds it. `LineNo` counts from zero here, and `onLine` adds one for a finding. `Strippable` is true only when the line is pure and `wholeSentencesOnLine` is true: the line has prose, its sentence ends on that line. Otherwise, no prose line follows. The previous prose line ends a sentence, and every sentence on the line holds the name as a whole identifier (`wordIndex`). A name found in no block yields a hit with `LineNo` of `-1` and is never strippable.

A trailing comment that names a dead symbol is reported on its own line and is not strippable. In a document, `Strippable` is forced to false, because a document line is a paragraph and deleting it takes other text with it.

### Repair

After the wording rewrite and the volume cut, `repairFile` repairs dead names in this order.

1. Rename (`renameEdits` in `tombstones/rename.go`), for source only. A rename keeps the sentence. It runs before any cut. `replacementFor` picks a replacement in multiple steps. First, `caseVariant`: the identifier that equals the dead name when case is ignored, taken from the text, or if none, from the repository (`repoCaseVariants`, which reads the index when built and otherwise runs `rg --ignore-case`). It must be unique and not itself dead. Second, when the dead name is the first identifier of the comment, as a doc comment opens with its subject. The name that the line after the comment declares (`declaredName`). That skips a Go method receiver and the keywords of `declKeywords`. The declared name must pass `isCandidate`, differ from the dead name and not be dead. The first whole-identifier occurrence on the line is replaced.
2. Strip. A strippable hit drops its line. `stripEdits` joins adjacent lines into a single edit. `delimitersKept` keeps the closer of a block comment that opened above the run, and the opener of one that closes below it. A strip that does not land is reported as a finding on its line. The blocks that lost a line are then rewrapped by `reflowStripped` with `commentfix.Tighten`, but only when the block count is unchanged.
3. Cut (`cutReferents` in `tombstones/cut.go`), for each dead name that no strip resolved. In a source block of line comments alone (`pureSpan`). `commentfix.CutSentence` removes every sentence of the block that holds the name, including one that runs over several lines, and reflows each paragraph it changed. A paragraph it empties goes. One edit applies to a block. A later pass takes a second name. Otherwise `sentenceAround` finds the sentence on the line that holds the last occurrence of the name. It runs from after the previous `. ` to the next `. `, or to `*/`, and never reaches back past a comment marker (`commentOpeners`: `//`, `/*`, `#`, `--`, `* `). Code on the line stays. A document has no markers. When the sentence is the whole comment, the marker goes with it. Any name still dead afterwards is noted as a finding.

`DeadReferentHits` returns a hit for each dead name in a text, as the registered rule's detection uses.

## tombstones/comment-volume

The ID is `IDVolume`, with the value `tombstones/comment-volume`. It counts the lines of a merged comment run against the cap. No rewording defeats it. It applies to source only: in a document, and when the rule is not kept, `repairFile` sets the cap to `0`. A document has no volume cap.

`Find` reports each block where `Block.Lines` exceeds the cap. A cap of `0` or less turns it off. The hit has the tell `a comment block of N lines`. The hit also has the first line of the run as phrase and line. `LineNo` set to the first line counted from one, and `EndLineNo` set to the last. It is never strippable, because it is a judgement of the whole block.

`Block.Lines` counts only the lines that are comment alone and not a directive. A trailing note on a code line is read with that line and adds nothing, and a run of `//sys` directives never reaches the cap.

The repair is `capEdits`. It cuts from the end of the run, the way `comments/length` cuts.

- A block of comment lines alone (`pureSpan`) goes through `commentfix.CapLines`. This cuts the run from its end until at most the cap of its lines are prose. This is a block with no sentence end to cut at keeps its opening sentence. The block is repaired to a sentence of at most the STE cap, and nothing after it (`TestAVolumeCapWithNoSentenceEndKeepsItsOpening`). A block of sentences loses whole sentences from its end (`TestTheVolumeCapCutsWholeSentences`). A block comment keeps a balanced opener and closer (`TestTheVolumeCapDropsLinesToASentenceEnd`).
- A block that shares a line with code drops its last pure prose lines instead, because a line edit there will carry the code. If the last kept line does not end a sentence, `trimLastKeptLine` cuts it back to its last `.`, `!` or `?`. That line keeps a block closer that followed. If it holds no sentence end, `dropLastKept` drops lines from the end until a kept line ends a sentence. A block with no such line keeps its prose, and no finding names it (`cuttable`).

`repairFile` notes the hit with the fix text `Cut the run from its end down to the cap. slopfix fix does this.`, but only when `cuttable` is true. This happens when the cap cut falls outside the scope a run may write. A removal made by the cap is recorded once as `comment prose past the volume cap`.

## Scope and gates

Every edit is written through `f.ApplyComments`, which holds it to the comment gate and to the `edit.Scope` of the run. In a fork, only the lines the fork wrote can fail the check, and `blockCap` in `forkscope.go` passes the cap only for `IDVolume`. [fork-scope](fork-scope.md) holds the fork rule. Each `Repair` returned by `FixIn` carries the text, whether it changed, the removed lines quoted, the rewrite count, the `Kept` hits that survive. The `Refused` edits. A caller refuses on `Kept`.

The tests of the package pin these behaviors: `tombstones/tombstones_test.go` for the wording repair. The list structure and the volume cap, `tombstones/scan_test.go` for blocks, `HitForName` and the dead-name search, `tombstones/referents_index_test.go` for the index, and `tombstones/vendored_test.go` for borrowed paths.

## See also

- [english](english.md) for the wording table this family reads
- [fork-scope](fork-scope.md) for the fork scope the edits obey
- [comments](comments.md) for the comment repair context
