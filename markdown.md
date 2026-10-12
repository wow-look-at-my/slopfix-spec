# markdown: the document model and the wrap rules

The `markdown` package splits a document into blocks. A prose rule reads only a prose block. Every other line is data. `Split` in `markdown/block.go` is the single entry point, and `markdown.Apply` in `markdown/edit.go` is the only door a repair writes through.

## Blocks

A `Block` holds `Kind`, `Lines`, `Start`, `Marker` and `Indent`.

- `Kind` is `Prose` or `Verbatim`. `Prose` is a paragraph or a list item. `Verbatim` is any other line.
- `Lines` are the source lines of the block, in order, without their line endings.
- `Start` is the line where the block begins, counting from `1`.
- `Marker` is the list bullet or number the item opened with. It is empty for a paragraph.
- `Indent` is the whitespace before the block.

`Block.Text` renders a prose block as the single line the rules read. It trims each line, drops the marker from the first line, and skips lines that are empty after the trim. It joins the rest with one space.

A verbatim block is always one line. `Split` emits one verbatim block per source line, so a fence of many lines is many verbatim blocks.

## How Split finds prose

`Split` parses the document with goldmark and its `extension.Table` extension (the package variable `parser`). The function `paragraphs` walks the tree and maps the line each paragraph opens on to the line it ends on. Only `ast.KindParagraph` and `ast.KindTextBlock` nodes become prose. A list item is a text block. A list item is prose.

Before the parse, a pass blanks bytes with spaces. Front matter and template tags each get such a pass. A blank keeps every byte offset, so line numbers hold.

- `blankFrontMatter` blanks a YAML front matter block. The block opens on a first line that is `---` after a trim and closes on the next such line. A file whose first line is not `---`, or whose block never closes, is left as written.
- `blankTemplateTags` blanks each line that holds one template tag and nothing else. It also blanks each line that holds one markup tag, such as a lone opening, closing or self-closing tag. The parser then reads the blanked line as a break between paragraphs.

The following are not prose:

- A fence, an indented code block, a heading of either style, a table. An HTML block and a thematic break. goldmark gives these no paragraph node.
- A block quote. `paragraphs` returns `ast.WalkSkipChildren` on `ast.KindBlockquote`, so a paragraph inside a quote stays as its author wrote it.
- Front matter, by the blanking above.
- A paragraph with no letter. `hasLetter` tests each line with `unicode.IsLetter`. A paragraph with none is a picture, such as braille or box art, and a join destroys its shape.
- A directive line, described below.
- A paragraph that is source code, described below.

A lazy continuation line stays in its paragraph. A list item keeps its marker, and a second paragraph in an item keeps its indent.

## Directive lines

`isDirective` marks a line that a template engine or an agent reads. A join or a rewrite changes what the line loads or renders. A line is a directive when either test holds.

- It contains any of the strings in `templateDirectives`: `{%`, `{{` or `{#`. The test is a substring match anywhere on the line.
- Its trimmed text matches `importLine`, the pattern `^@[^\s@]+$`. That is one `@path` import, as a CLAUDE.md lists the files it pulls in.

A directive line divides its paragraph. In `paragraphs`, each run of lines between directive lines becomes its own prose range, and the directive lines stay verbatim. Prose on both sides of a directive stays prose. An import inside a sentence is not a directive, because the whole trimmed line must be the import.

`isTemplateTag` is stricter and serves only `blankTemplateTags`. A trimmed line is a template tag when, after one leading `$` is removed, it starts with `{%`, ends with `%}` and holds exactly one `%}`. A tag such as `{% if x %}` or `${%- endif %}` is thus a break between paragraphs. The pattern `markupTagLine` is `^</?[A-Za-z][\w:.-]*(\s[^<>]*)?/?>$`. It matches a trimmed line that is one markup tag, because a custom tag cannot end a CommonMark paragraph by itself.

## Source code is not prose

`Split` asks `code.Is` (`code/sniff.go`) about the whole document, and again about each paragraph. When a grammar parses the text whole with no error, every line of it is verbatim. Source text is code whatever its file is named.

`code.Is` first requires the text to contain at least one of the bytes in `codeMarks`, which is the string `(){};=`. It then tries the grammars in `sniffers` in this order: TypeScript, TSX, JavaScript, Go, Rust, C and C++. Bash is left out on purpose, because any run of words is a command to it. English prose never parses whole in these grammars.

## List markers

`listMarker` splits a line into its leading whitespace and its marker. A bullet is `- `, `* ` or `+ `, and the marker is the bullet character. An ordered marker is digits, then `.` or `)`, then a space, and the marker includes the digits and the punctuation. A line that opens no item returns an empty indent and an empty marker. For such a line `Split` takes the leading spaces and tabs as the indent.

## The join

`Format` puts each prose block on a single line and moves newlines only. `FormatFunc` does the same and passes the text of each block through a `repair` function first. A verbatim block never reaches `repair`.

`FormatEdits` returns one edit per prose block that the join or `repair` changes. The new line is the block indent, then the marker and one space when the block has a marker, then `repair(block.Text())`. A block of one line that equals the new line produces no edit. The edit replaces the whole block through `BlockEdit`.

`WordsOnly(before, after)` reports whether both documents carry the same words in the same order. It compares `strings.Fields` of each, rejoined with one space. `Format` in `slopfix.go` returns the formatted text and the result of `WordsOnly` against the source. The `wrap-and-ste` fixer in `fix.go` applies the join only when that result is true. A result whose words differ from the source is a bug.

## The gate

`markdown.Apply(content, edits, scope)` writes edits through `edit.Gate`. It enforces the following properties.

- An edit lies inside a single prose block. `proseSpans` gives the byte range of each prose block. An edit that reaches past the block containing its start is refused with the reason `it reaches past its prose block`.
- After the splice, the document is parsed again. The list of verbatim blocks, from `verbatim`, must equal the list before the splice. A verbatim block that holds only blanks is not in the list. The container tree, from `shape`, must also be equal.

`shape` renders the container tree with `P` for a run of paragraphs. A run of paragraphs in one container renders as a single `P`, so an edit may divide a paragraph with a blank line. A paragraph that leaves its list item changes the shape and is refused. Text that opens a fence, starts a heading or ends a list changes the verbatim list, so the edit that wrote it never lands. See `edit-the-only-way-a-repair-writes.md` for the gate contract.

## wrap/hard-wrap

`wrap/hard-wrap` (constant `IDHardWrap`, category `RuleWrap`) rejects a paragraph or list item split over several source lines. A hard wrap freezes the width of one window into the file, and each later edit re-flows lines that nobody touched.

Detection is in `Check` in `slopfix.go`. For each prose block, and for each line after the first, it reports one finding at line `block.Start + i`. The rule text is `a paragraph is one line`. The detail names the first line of the paragraph. A single-line block gives no finding.

Repair is the join. The `wrap-and-ste` fixer (`Place` value `30`, files of kind `fixer.Document`) calls `markdown.FormatEdits`. It joins each prose block to one line. The same pass applies the STE and `english/comma-never` word repairs through `repair`. The fixer answers to the family and rule selection, and `f.Wants` and `f.Keeps` decide which word repairs run. A document is joined only when `WordsOnly` holds.

A workflow is never joined, because a newline in YAML is syntax.

Not flagged:

- A block of one line.
- A verbatim block, which includes a quotation, a fence, a table, a heading, a picture, a directive line and source code.
- Front matter.

The registered case in `rule_wrap_hardwrap.go` is a wrapped paragraph in `x.md`.

## wrap/long-block

`wrap/long-block` (constant `IDLongBlock`, category `RuleWrap`) rejects a paragraph or list item over the character cap. Its constants are in `longblock.go`.

- `LongBlockCap` is `1500`. It is the most characters a prose block may hold.
- `LongBlockTarget` is `LongBlockCap * 2 / 3`, which is `1000`. A division brings each part down to it.
- `LongBlockWordCap` is `120`. It is the most words a part of a division may hold. It is the org's paragraph cap in words.
- `LongBlockWordTarget` is `LongBlockWordCap * 2 / 3`, which is `80`.

Detection is `longBlocks`. For each prose block it counts the runes of `Block.Text()` with `utf8.RuneCountInString`. A block at or under `LongBlockCap` gives no finding. A block over the cap gives a finding only if `divide` returns a couple of parts. The finding is at `block.Start`. Its rule text is `over the 1500-character cap for a paragraph or a list item at N characters`, with the real count for `N`.

Its detail is the first `60` runes of the text followed by `...`. The tail `...` is added even when the text is shorter.

Every reported block can be repaired, because a finding needs a division into parts. A block with no place to cut is not reported.

### Cuts

`cuts` lists each place the text may divide, in order. A cut is the byte where the next part opens. A cut sits at each space whose next byte is not a space, with the space itself not at the start or end. The scan tracks state and skips a cut in these places:

- Inside a code span, toggled by the backtick.
- Inside a quotation, toggled by `"`.
- Inside bold text, toggled by `**`.
- Inside square brackets, so inside the text of a link.
- Where the text that follows matches `blockOpener`. That pattern is `^(?:[-*+]\s|\d{1,9}[.)]\s|#{1,6}\s|>|` followed by a triple backtick, `~~~`, `<` or `|`. It covers a list marker, a heading, a quotation, a fence, HTML and a table. A part therefore never opens a new block.

Each cut has a class, best first.

- `cutSentence`: the cut is the start of a sentence, as `ste.Sentences` splits it, and no parenthesis is open.
- `cutInnerSentence`: the cut is the start of a sentence inside an open parenthesis.
- `cutWord`: any other blank between words.

### Division

`divide(text)` returns the parts. It loops while the remaining text is too big. The remaining text is too big when `fits` fails for `LongBlockTarget` characters and `LongBlockWordTarget` words, or when it holds more sentences than `ste.ParagraphSentenceCap`. That constant is `6`, in `ste/warnings.go`. `fits` counts runes and `strings.Fields` words.

Each pass chooses the next cut as follows.

- It scans the cuts after the start. It stops at the first cut whose chunk no longer fits the targets or holds too many sentences.
- Among the cuts that fit, it keeps the one with the lowest class. A later cut of equal class replaces an earlier one. The part is as long as it can be.
- If no cut fits, or the best is a `cutWord`, it looks for the first sentence cut that fits the larger limits `LongBlockCap` and `LongBlockWordCap`. A sentence end past the target but under the cap reads better than a cut between words.
- If that fails, it takes the first cut after the start.
- If there is no cut at all, the loop ends.

Each part is trimmed. The last part is the remaining text.

### Repair

The fixer `wrap/long-block` (`Place` value `35`, files of kind `fixer.Document`) calls `longBlockEdits`. It runs after the join and the word repair. It reads each block whole. For each prose block over the cap that `divide` cuts into parts, it writes the parts as paragraphs with a blank line between them. The first part carries the indent, and the marker plus one space for a list item. Each later part carries the indent, plus spaces equal to the marker width plus one, so the part stays inside the item.

The gate admits the blank line. It refuses an edit that moves a paragraph to another container.

`paragraphEdits` is a separate pass in the `wrap-and-ste` fixer. It serves `ste/paragraph-length`. It divides a paragraph with `ste.Paragraphs`, only when the block has no marker. A list item stays whole there.

Not flagged:

- A block at or under `LongBlockCap`.
- A block with no cut, such as one long run with no blank between words.
- A verbatim block.

The registered case in `rule_wrap_longblock.go` is one list item made of a repeated sentence, in `x.md`. `longblock_test.go` checks that a division moves only newlines and blanks (`WordsOnly`), that every part stays under the character cap and the word cap. This is and that no part opens with a list marker or a heading.
