# message-rules: the rules that judge a closing message

Rules judge a closing message, which is never on disk: `laziness/punt`, `blame/deflection` and `ask/prose-decision`. Each is a `RuleSpec` in `rule_message_laziness.go`, `rule_message_blame.go` and `rule_message_ask.go`. The detectors live in the packages `laziness`, `blamelanguage` and `askproperly`. `message.go` joins them. The hook guards that serve the same detectors are in [hook-guards](hook-guards.md).

## Shared behavior

- `MessageIDs` in `message.go` names the set: `laziness.ID`, `blamelanguage.ID` and `askproperly.ID`. Their values are `laziness/punt`, `blame/deflection` and `ask/prose-decision`. The categories are `laziness`, `blame` and `ask`.
- A message rule judges what the message asserts in its own voice. Each detector first blanks the lines it treats as quoted: a fenced block opened by multiple backticks or tildes (the fence lines too). An indented line, and a blockquote line that starts with `>`. The blanking keeps every byte offset. A finding still names the right line. A message can thus document a phrase inside a fence without tripping the rule.
- An inline backtick span is NOT exempt in any of the rules. A phrase in backticks is still the writer's own voice.
- A finding carries `ID`, `Line` (counting from one), `Rule` (the tell), `Detail` and `Fix`. `CheckMessage` builds it. `Registered` then drops nothing and panics on an ID that no rule registers.
- `CheckMessage(message, runs)` runs a rule only when `runs(id)` answers true. The result keeps the order laziness, blame, ask.
- Every rule has an autofix. The fix cuts. It asserts nothing, because a rewrite of a punt or a question will have to claim work or a decision nobody made.

## laziness/punt

`laziness.Check` reports a closing message that leaves the work undone because the work is harder, or that asks permission in place of acting. The `Tell` of a finding names the shape. `Detail` is the sentence, with whitespace collapsed to single spaces.

### The tells

The table `tells` in `laziness/laziness.go` is a slice of a name and a case-insensitive regular expression. Extending the rule ads a row. The names, with the phrase each row matches:

- `disowning a defect you found`: `not mine to fix` (also `neither`, `ours`, `my own`), and `not my problem`, `not our job`, `not my responsibility` and the `our` forms.
- `handing a repair back to the reader`: `worth your attention`, `flagging it for you` (with `this`, `these`, `them`, `that` or no object, and `to` for `for`), `someone should fix` (also `look`, `clean`, `deal`), and `you may want to fix` (also `might`, `could`, and `look`, `check`, `clean`).
- `leaving a defect in place`: `left it as-is` (also `alone`, `unfixed`, `broken`, `red`, and `them`, `that`, `these`, `those`), the same with `leaving`, and `I did not fix` or `I didn't fix`.
- `excusing yourself from a repair`: the word `unasked`, `out of scope`, `outside the scope` (also `my`, `our`), `not caused by my change` (also `this`, `the`), and `pre-existing` followed a bounded number of characters of one sentence by `so I did not`. Pre- also followed `and I left` and the like.
- `announcing an attribution hunt instead of a repair`: `two things to establish` (also `three`, `first`), `whether master is red` (also `main`, `the base branch`, and `failing`, `broken`), and `establish whether I` (also `determine`, `work out`, `figure out`, and `if`, `who`, `we`, `this PR`, `my change`).
- `offering authorship in place of a fix`: `not this PR's fault` (also `my change`, `mine`, and `problem`, `failure`), `fails on master too` followed a bounded number of characters by `so` or `therefore`, and `I did not break it` (also `cause`, `this`, `that`).
- `asking permission in place of acting`: `want me to ... ?`, `would you like me to ... ?`, `shall I ... ?`, `should I ... ?`, `do you want me to ... ?` (each of these needs the question mark in the same sentence), `let me know if you would like`, `I can <action> if you would like`, and `say the word`.

The regular expressions in the source are the authority for exact spellings. An apostrophe may be straight or curly.

### Detection

- Each tell finds its first match in the asserted text. A tell with no match reports nothing.
- The reported unit is the sentence around the match. `sentenceBounds` looks back and forward for a sentence end. `endsSentence` ends a sentence at a line break, `!`, `?`, or a `.` that is not flanked by alphanumerics on both sides. `CLAUDE.md` stays one token.
- A sentence is reported once, for the first tell in table order that found it. A sentence already seen is skipped.
- `Line` is the line where the sentence starts.

### Pardons

A sentence that carries a tell AND says the repair happened is not a punt. The list `pardons` holds the forms: `fixed it` (also `repaired`, `patched`, `corrected`, followed by `it`, `them`, `that`, `those`, `these`, `anyway`, `here`, `now` or `in`), `already fixed` (also `repaired`, `pushed`, `landed`, `corrected`), `pushed the fix` (also `landed`, `committed`), and `fix in this turn` (also `fixed it in`, `the same commit`, `change`, `PR`, `pull request`). A fix claimed in another sentence pardons nothing. A bare diagnosis with no tell is clean.

## blame/deflection

`blamelanguage.Check` reports a closing message that shifts the work onto another author or an earlier time. Every repository in the org has the same author, so no other author exists to shift it to. The `Tell` of every finding is the fixed text `deflecting the work onto another author or an earlier time`.

### The phrases

The slice `phrases` in `blamelanguage/blamelanguage.go` holds. That `phrases` is in this order. This covers `pre-existing`, `preexisting`, `not my fault`, `not my problem`, `not mine to fix`, `not my responsibility`, `worth your attention`, `flagging this for you`, `flagging this here`, `left as-is`, `someone should`, `out of scope`, `not caused by my change`, `not caused by my diff`, `you may want to`, `that predates this session`, `predates this session`, `this was existing code`, `i only copied it`, `git blame shows`, `not related to my change`, `unrelated to my diff`.

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

- Each `?` in the scanned text is a candidate. The sentence is the text back to the previous `.`, `!`, `?` or line break, cut to its last many characters.
- `closesAQuestion` accepts the mark when, after any trailing closers (`` ` ``, `"`, `'`, `)`, `]`, `*`, `_`), the line ends or the text ends. When a space follows, the mark counts only if `opensWithCue` is true. When any other character follows, it is not a question. That is how a nullable type such as `string?` is excluded.
- `opensWithCue` looks at the first a couple of words of the sentence, lowercased and trimmed of punctuation. A word in `cueWords` makes it a question. The list is `what`, `which`, `why`, `how`, `when`, `where`, `who`, `whose`, `should`, `shall`, `would`, `could`, `can`, `will`, `do`, `does`, `did`, `is`, `are`, `was`, `were`, `am`. `have`, `has`, `any`, `want`, `prefer`, `ok`, `okay`, `right`, `correct`, `agree`, `sound`. The window is narrow on purpose: a statement that reaches `is` in a later word is not a question.
- questions on the same line report once. `Text` is the sentence without its `?`. `Line` is the source line, whitespace collapsed and cut to many characters plus `...` when over 160.

### Deferrals

The slice `deferralPhrases` holds: `let me know`, `your call`, `up to you`, `say the word`, `just say`, `tell me which`, `tell me what you`, `waiting on you`, `waiting for you to`, `if you want me to`, `want me to`, `would you like me to`, `do you want me to`, `shall i`, `should i proceed`, `i won't touch`, `i will not touch`, `and i'll pick`, `and i will pick`, `and i'll land`, `or say`. Each is a case-insensitive literal. A phrase reports once, at its first occurrence. `Text` is the phrase itself.

## Judging a message on the command line

`slopfix check --message` reads stdin as a closing message. `cmd/check.go` (`checkMessageStdin`) runs the rules and `cmd/message.go` selects them.

- `--only` takes a message rule ID or a family, which is the part before the slash (`laziness`, `blame`, `ask`). With no `--only`, every message rule runs. `messageSelection` returns an error for any other name, and the error lists the known IDs. A run that applies nothing must never read as a clean message.
- Without `--fix`, each finding prints on stdout. The command exits nonzero (`errFindings`) when any finding exists.
- With `--json`, one object is written with `findings` and, on a repair, the repaired `text`. The exit is zero.
- A selector flag (`--staged`, `--diff`) cannot be combined with `--message`.

## Repairing a message

`slopfix fix --message` (or `check --fix --message`) calls `FixMessage` and writes the repaired message to stdout. Remaining findings go to stderr. The exit is nonzero when any remain.

`FixMessage` loops at most `len(message) + 1` times. Each pass runs `CheckMessage`. It stops when no finding is left. Otherwise it calls `cutSentences`, and when that changes nothing it calls `cutLines`.

- `messageSentences` divides the message into sentences. A sentence ends at a line break, `!`, `?`, or a `.` that is not between multiple alphanumerics.
- `cutSentences` considers only sentences that touch a reported line. It cuts a sentence only when `CheckMessage` on that sentence alone still reports a finding. A sentence that a rule exempts, such as one inside a fence, is untouched. The line break that ends a sentence stays, so the lines around it survive.
- `cutLines` removes each whole reported line. It is the fallback when no single sentence reproduces its finding.
- A message with a finding in a fence-adjacent context is thus never cut beyond the lines the rules reported.

The tests in `ruleharness_test.go` drive each rule through `messageFindings` and `messageAutofix`, which run `CheckMessage` and `FixMessage` with only that rule enabled. The case texts are in the rule_message_*.go` files.

## See also

- [hook-guards](hook-guards.md) for the guards that serve the same detectors
- [rules](rules.md) for the message rules in the registry
