# Message rules

`message.go` joins them. The hook guards that serve the same detectors are in [hook-guards.md](hook-guards.md).

## Shared behavior

- A message rule judges what the message asserts in its own voice. Each detector first blanks the lines it treats as quoted: a fenced block opened by multiple backticks or tildes (the fence lines too). An indented line, and a blockquote line that starts with `>`. The blanking keeps every byte offset. A finding still names the right line. A message can thus document a phrase inside a fence without tripping the rule.
- An inline backtick span is NOT exempt in any of the rules. A phrase in backticks is still the writer's own voice.
- `CheckMessage` builds it. `Registered` then drops nothing and panics on an ID that no rule registers.
- `CheckMessage(message, runs)` runs a rule only when `runs(id)` answers true. The result keeps the order laziness, blame, ask.
- Every rule has an autofix. The fix cuts. It asserts nothing, because a rewrite of a punt or a question will have to claim work or a decision nobody made.

## laziness/punt

`laziness.Check` reports a closing message that leaves the work undone because the work is harder, or that asks permission in place of acting. The `Tell` of a finding names the shape. `Detail` is the sentence, with whitespace collapsed to single spaces.

### The tells

The table `tells` in `laziness/laziness.go` is a slice of a name and a case-insensitive regular expression. Extending the rule ads a row.

The regular expressions in the source are the authority for exact spellings. An apostrophe may be straight or curly.

### Detection

- Each tell finds its first match in the asserted text. A tell with no match reports nothing.
- The reported unit is the sentence around the match. `sentenceBounds` looks back and forward for a sentence end. `CLAUDE.md` stays one token.
- A sentence is reported once, for the first tell in table order that found it. A sentence already seen is skipped.
- `Line` is the line where the sentence starts.

### Pardons

A sentence that carries a tell AND says the repair happened is not a punt. A fix claimed in another sentence pardons nothing. A bare diagnosis with no tell is clean.

## blame/deflection

`blamelanguage.Check` reports a closing message that shifts the work onto another author or an earlier time. Every repository in the org has the same author, so no other author exists to shift it to. The `Tell` of every finding is the fixed text `deflecting the work onto another author or an earlier time`.

### The phrases

The slice `phrases` in `blamelanguage/blamelanguage.go` holds. That `phrases` is in this order.

### Detection

- Matching is a case-insensitive literal match of each phrase (`regexp.QuoteMeta`). Each phrase reports at its earliest occurrence. A phrase with no match reports nothing, and phrases can both report on one sentence.
- Whitespace collapses first (`normalizeWhitespace`), so a phrase that a markdown line wrap split still matches. `offsets` maps each collapsed byte back to its source offset.
- `Phrase` is the wording as the writer spelled it, read back from the source text with its case kept. `Sentence` is the line that holds it, whitespace collapsed and cut to many characters plus `...` when over 160.
- The fence detector here tracks the marker character. A fence closes only on the same marker that opened it. A line is indented code when it starts with multiple spaces and is not blank.

## ask/prose-decision

`askproperly.FindQuestions` reports multiple kinds of hit: a question put to the reader in prose, and a deferral that hands the reader. A decision with no question mark. `Hit.Kind` is `question` or `deferral`. The detector returns nothing for an empty or blank message.

### What the detector reads

- `assertedText` blanks fenced code, indented code and blockquote lines, as above. It also blanks the inside of a double-quoted span on a line (`blankQuoted`). A phrase the message mentions is not read as a phrase it uses. The span keeps its length.
- `stripLinks` then removes markdown link destinations (the text between `](` and the next `)`) and every bare `http://` or `https://` URL, up to whitespace, `)` or `>`. A query string in a link is thus not a question. Offsets map back to the asserted text.

### Questions

- Each `?` in the scanned text is a candidate.
- `closesAQuestion` accepts the mark when, after any trailing closers (`` ` ``, `"`, `'`, `)`, `]`, `*`, `_`), the line ends or the text ends. When a space follows, the mark counts only if `opensWithCue` is true. When any other character follows, it is not a question. That is how a nullable type such as `string?` is excluded.
- `opensWithCue` looks at the first a couple of words of the sentence, lowercased and trimmed of punctuation. A word in `cueWords` makes it a question. The window is narrow on purpose: a statement that reaches `is` in a later word is not a question.
- questions on the same line report once. `Text` is the sentence without its `?`. `Line` is the source line, whitespace collapsed and cut to many characters plus `...` when over 160.

### Deferrals

Each is a case-insensitive literal. A phrase reports once, at its first occurrence. `Text` is the phrase itself.

## Judging a message on the command line

`slopfix check --message` reads stdin as a closing message. `cmd/check.go` (`checkMessageStdin`) runs the rules and `cmd/message.go` selects them.

- With no `--only`, every message rule runs. `messageSelection` returns an error for any other name, and the error lists the known IDs. A run that applies nothing must never read as a clean message.
- Without `--fix`, each finding prints on stdout. The command exits nonzero (`errFindings`) when any finding exists.
- With `--json`, one object is written with `findings` and, on a repair, the repaired `text`. The exit is zero.
- A selector flag (`--staged`, `--diff`) cannot be combined with `--message`.

## Repairing a message

`slopfix fix --message` (or `check --fix --message`) calls `FixMessage` and writes the repaired message to stdout. Remaining findings go to stderr. The exit is nonzero when any remain.

`FixMessage` loops at most `len(message) + 1` times. Each pass runs `CheckMessage`. It stops when no finding is left. Otherwise it calls `cutSentences`, and when that changes nothing it calls `cutLines`.

The tests in `ruleharness_test.go` drive each rule through `messageFindings` and `messageAutofix`, which run `CheckMessage` and `FixMessage` with only that rule enabled.
