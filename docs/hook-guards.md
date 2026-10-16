# hook-guards: the slopfix hook guards

`slopfix hook` reads one hook payload on stdin and runs every guard that serves the event. This file covers the guards `write`, `laziness`, `blame-language`, `ask-properly`, `link-refs`, `busy-poll` and `md-budget`. [no-work-loss](no-work-loss.md) covers `no-work-loss`. `clean-bash` and `auto-allow` have their own files. The closing-message detectors behind three of the guards are in [message-rules](message-rules.md). [commands](commands.md) lists the event table.

## Dispatch

`cmd/guards.go` holds the table `guards`, in run order. A `guard` has a name. The events it serves, and a `run` function that takes the raw payload and answers a `hookResult` of `Stdout`, `Stderr` and `Code`.

| Guard | Events | Entry point |
|---|---|---|
| `clean-bash` | PreToolUse | `bashclean.Run` |
| `write` | PreToolUse | `judge` in `cmd/hook.go` |
| `no-work-loss` | PreToolUse | `noworkloss.Run` |
| `auto-allow` | PreToolUse, PermissionRequest | `autoallow.Run` |
| `busy-poll` | PreToolUse, Stop | `busypoll.Run` |
| `md-budget` | SessionStart, PostToolUse, Stop | `mdbudget.Run` |
| `laziness` | Stop | `laziness.Run` |
| `link-refs` | MessageDisplay | `linkrefs.Run` |
| `blame-language` | MessageDisplay | `blamelanguage.Run` |
| `ask-properly` | MessageDisplay | `askproperly.Run` |

- The event names are the constants `eventPreToolUse`, `eventPermissionRequest`, `eventPostToolUse`, `eventSessionStart`, `eventStop` and `eventMessageDisplay`.
- `eventOf` reads `hook_event_name`. A payload with a `tool_name` and no event name counts as PreToolUse, for a payload built by hand. An unparseable payload has no event, so no guard serves it.
- `--only` takes guard names. Any other entry must be a rule category or rule ID. It turns the `write` guard on with that rule selection (`hookSelection`). An unknown name is an error that lists the guards. With no `--only`, every guard runs and the write guard runs every rule.
- `--max-comment-lines` (`tombstones.DefaultMaxCommentLines`) caps a comment block in the write guard. `0` turns the cap off.
- `runHook` prints `Stdout` and `Stderr`. A nonzero `Code` becomes the process exit through `os.Exit`. A refusal is thus an exit code that Claude Code reads. A payload that cannot be read prints nothing and exits zero.

### PreToolUse

`preToolUse` runs the serving guards in table order.

- A guard that exits nonzero ends the run, and its result is the answer.
- A guard whose `hookSpecificOutput.permissionDecision` is `deny` ends the run too.
- A guard that returns `updatedInput` replaces `tool_input` in the payload that every later guard sees. No guard judges a command that will not run.
- The remaining results go through `merge`. When any guard rewrote the input, the last `updatedInput` is put on the merged output, because it already holds the earlier rewrites.

### Stop and the other events

`dispatch` runs each serving guard on the payload and passes the results to `merge`.

- A result counts as spoken when it has `Stdout`, `Stderr` or a nonzero `Code`. With no spoken result, the answer is empty. With one, it passes through unchanged.
- With several, every result with `Code` `2` contributes its trimmed `Stderr` as a reason. A result whose stdout is a JSON object with `decision` equal to `block` contributes its `reason`. Any reason makes the answer exit `2` with the reasons joined by a blank line.
- Otherwise `hookSpecificOutput.additionalContext` strings join with a blank line, `systemMessage` strings join with a line break, and other keys copy over. `hookEventName` is set to the event.

### MessageDisplay

`messageDisplay` composes what the reader sees. It starts with `base` equal to the payload `delta`. A guard that answers `displayContent` beginning with the delta adds the rest as a note. A guard whose content does not start with the delta replaces the base (this is `link-refs`). The output is `base` plus the notes in guard order, in the envelope below. When nothing changed, the answer holds only the merged stderr.

The table order puts `link-refs` first, so every note lands on the rewritten text.

`displayContent` changes only what the reader sees on screen. It changes neither the stored message nor the next request to the model.

### Failure behavior

Every guard fails open: an unreadable payload and a payload for another event. This also covers an unreadable transcript or state file, and an internal error all print nothing and allow. Exceptions are stated per guard below.

## write

The `write` guard repairs the text that a Write, Edit or MultiEdit adds. `judge` in `cmd/hook.go` implements it.

- Input: the PreToolUse payload. `tool_name` must be `Write`, `Edit` or `MultiEdit`, and `tool_input` carries `file_path` plus `content` (Write), `old_string` and `new_string` (Edit), or `edits` (MultiEdit). Any other tool, a payload for another event, or an unreadable input answers nothing.
- The text is judged where it lands. `place` (in `placement.go`) reads the file, replays the edits, runs the rules over the whole result, and subtracts the findings the file already carried. Rule and message matches a finding, not by line. When the edit cannot be pinned to the file (the old string is absent or appears more than once), the fragment is judged alone with a `Scope` that keeps every rewrite. That rewrite is inside the edit's bytes.
- `handFix` (in `handfix.go`): an Edit or MultiEdit that changes a line which `slopfix fix` repairs goes through with that line as `slopfix fix` writes it. The note `handFixNote` names the line.
- In a fork, a repair and its findings keep to the lines the fork wrote (`forkLinesOf`). A fork whose base cannot be read denies the write, with the reason `slopfix cannot tell which lines of PATH this fork wrote`.
- Verdict:
  - A `slopfix-expect` that does not hold denies, with the unmet lines.
  - A changed text answers `updatedInput` (the full tool input with the repaired text) and `additionalContext` from `notice`.
  - A write with only flags answers `additionalContext` alone.
  - A clean write answers nothing.
- `notice` says `slopfix repaired this write to PATH` with the rewrite count, or `slopfix let this write to PATH through and flagged what it reads` when nothing was rewritten. It lists `removed` and `flagged` lines. `reportCap` is `6`, and a longer list ends with `... and more, not listed`. The notice closes with `The write went through as it stands. Write prose that needs none of this.`
- A denial carries `permissionDecision` `deny` and a reason that starts with `blocked:` followed by the capped lines. Prose never reaches a denial: a comment is repaired and reported.
- Output shape: `hookSpecificOutput` with `hookEventName` `PreToolUse` plus `permissionDecision`, `permissionDecisionReason`, `updatedInput` and `additionalContext` as the verdict needs.

## laziness

Event: Stop. `laziness.Run` in `laziness/run.go`.

- Input fields: `hook_event_name`, `stop_hook_active`, `last_assistant_message` and `transcript_path`.
- An event name that is set and is not `Stop` allows. `stop_hook_active` true allows, so the guard fires at most once per turn and a message that cannot be rewritten never trips it forever.
- The message is `last_assistant_message`. When it is empty, the guard reads the transcript (JSONL, newest last) and takes the text of the last entry whose `type` or `role` is `assistant`. `content` may be a string or a list of typed parts, and only parts of type `text` count. The entry may hold `content` directly or inside `message`. An unreadable path leaves the turn unjudged.
- Verdict: when `laziness.Check` reports a hit, stderr is the single word `continue` and the exit code is `2`. The word gives the model nothing to argue with. With no hit, nothing.
- Stop, not MessageDisplay, because this rule sends the model back to work. A MessageDisplay note reaches only the reader.
- No environment variable disables it.

## blame-language

Event: MessageDisplay. `blamelanguage.Run` in `blamelanguage/run.go`. It never refuses and sends nothing to the model.

- Input fields: `hook_event_name`, `message_id`, `final` and `delta`. An event name that is set and is not `MessageDisplay` allows. An empty `message_id` allows.
- State: each flush appends `delta` to the file `slopfix-blame-` plus the first `16` hex characters of the SHA-256 of `message_id`, in `os.TempDir()`, with mode `0600`. Flushes before `final` answer nothing. On the last flush the guard reads the file, removes it, and sweeps. `sweep` removes every `slopfix-blame-*` file older than one hour. A lost file costs earlier phrases, not an incorrect mark.
- Verdict: on the last flush the message is judged whole with `blamelanguage.Check`. A hit appends a note to the last delta. The note is a blank line, then a blockquote line that starts `**no-blame-language** --`, then the quoted phrases. Then a fixed sentence that says every repository here has the same author and the model must own the defect and say what it fixed. `named` is `3`: the note quotes at most `3` distinct phrases and adds `, and more` after a cut. A phrase with an empty `Phrase` falls back to the sentence.
- Output shape: `{"hookSpecificOutput":{"hookEventName":"MessageDisplay","displayContent":"<delta + note>"}}`. `displayContent` replaces the delta.
- Disabled when `CC_NO_BLAME_LANGUAGE` is `0`, `false`, `no` or `off`.

## ask-properly

Event: MessageDisplay. `askproperly.Run` in `askproperly/hook.go`. It never refuses, and `Code` is always `0`.

- Input fields: `hook_event_name`, `transcript_path`, `message_id`, `index`, `final` and `delta`. Any event name other than `MessageDisplay` allows, including an empty one.
- State: `stateDir` is `cc-ask-properly` under `os.TempDir()`, with mode `0700`. A non-last flush writes the accumulated text to `<message_id>.txt` with mode `0600`. This happens after the id is stripped of every character outside letters, digits, `_` and `-`. On the last flush the guard reads the prior text, removes the file, and sweeps files older than one hour.
- The message is judged whole on the last flush: the stored text plus the last delta.
- A turn that already called the `AskUserQuestion` tool is not judged (`askTool`). `ReadTurn` reads the last `transcriptTailBytes` (`4 << 20`) of the transcript, finds the start of the turn (the last user record that is a real prompt, not only `tool_result` blocks), and looks for a `tool_use` block of that name. That name is in the assistant records since. An unreadable transcript leaves the message judged on its own text.
- Verdict: `Annotate` runs `askproperly.FindQuestions`. With no hit it answers nothing. A deferral hit whose text is already inside an earlier quoted hit is dropped. The note names at most `annotationCap` (`3`) findings, each quoted, and adds `, and more` past the cap. A finding longer than `findingCap` (`80`) characters keeps its last `80` characters behind `...`. A question hit shows its closing `?`. The note starts with a blank line and `> **ask-properly** --`, and says the decision was handed over in prose. That the model must make it and say what it assumed, and that a card is for the cases guessing cannot cover. This covers reaching outside the branch, destroying something, access the session lacks, or a fork the owner reserved.
- Output shape: the same `displayContent` envelope as `blame-language`.
- Disabled when `CC_ASK_PROPERLY` is `0`, `false`, `no` or `off`.

## link-refs

Event: MessageDisplay. `linkrefs.Run` in `linkrefs/run.go`. It rewrites the flush it is given and judges nothing about the model.

- Input fields: `hook_event_name`, `message_id`, `index`, `final` and `delta`. An event name that is set and is not `MessageDisplay` allows. An empty `delta` only clears state on the last flush.
- Fence state: a fence can span flushes. The file `slopfix-linkrefs-` plus the first `16` hex characters of the SHA-256 of `message_id` in `os.TempDir()` exists. This happens when the previous flush ended inside a fenced block (`EndsInsideFence`). A last flush removes the file and sweeps `slopfix-linkrefs-*` files older than one hour. A lost file costs the fence exemption on later flushes, not an incorrect rewrite of another message. An empty `message_id` keeps no state.
- `RewriteDelta` rewrites only lines outside a fence, a blockquote and indented code. A line the rules exempt is left as it is.
- What it links (`FindUnlinkedInLine` in `refs.go`). A bare GitHub URL (`urlRe`), an issue. It pull request number with an `owner/repo` prefix (`numberRe`). A commit SHA of `7` to `40` hex characters that has both a digit and a letter. From `a` to `f` (`shaRe`, `validSHA`). This is and a branch whose name starts with a prefix from `claude`, `feature`, `feat`, `fix`, `bugfix`, `hotfix`, `release`, `chore`, `refactor`, `wip`. `renovate` or `dependabot` (`branchRe`). Text already inside a markdown link, an angle-bracket autolink or a character reference is blanked first. A token inside a longer word, path or number is not a match. Backticks around a token move inside the link text.
- What it never links (`refURL`): a bare `#N` with no repository, because the repository will be a guess. A SHA that `git cat-file -e` does not find. A branch that is not a remote-tracking ref on origin, and any SHA or branch when origin has no GitHub remote. Silence is the answer when the target cannot be shown to exist.
- URL shapes: an issue or pull request number becomes `https://github.com/OWNER/REPO/issues/N` (GitHub redirects an issue URL to its pull request). A SHA becomes `.../commit/SHA`. A branch becomes `.../compare/BASE...BRANCH?expand=1`, where BASE comes from `refs/remotes/origin/HEAD`. An empty base leaves the text alone.
- Pull request dots: a reference to a pull request gets a colored circle from `PullState` (`dot`). The states are `StateUnknown` (no circle), `StateMerged` (purple), `StateClosed` (black), `StateFailing` (red), `StateConflicted` (orange), `StatePending` (yellow) and `StateMergeable` (green). A merged or closed pull request keeps its words as plain text and the circle carries the link. Any other state puts the circle before the link. `BadgeLink` also adds the circle to a markdown link to a pull request that someone else wrote. A link that already carries a circle, or follows one, is not badged again.
- Pull request state (`classify`, `askPull`): `gh pr view N -R OWNER/REPO --json state,mergeable,mergeStateStatus,headRefOid`, bounded by `ghTimeout` (`2 * time.Second`). For an open pull request, `gh wait-ci checks -R SLUG --sha HEAD --json` bounded by `checksTimeout` (`12 * time.Second`) supplies the checks, and `mergeStateStatus` stands in when that call fails. Order of severity: merged, closed, a failed check (`FAILURE`, `ERROR`, `TIMED_OUT`, `CANCELLED`, `ACTION_REQUIRED`, `STARTUP_FAILURE`), a conflict (`mergeable` equal to `CONFLICTING` or `mergeStateStatus` equal to `DIRTY`), a pending or expected check, then mergeable. Every failure to ask answers `StateUnknown`, so an unanswered question never shows as green.
- Cache: a state is kept in `slopfix-linkrefs-pr-` plus a hash in `os.TempDir()`. A finished state never expires. Another state is reused for `cacheTTL` (`time.Minute`). `StateUnknown` is never stored. A flush that names several pull requests asks about them in parallel (`Prefetch`).
- Git calls: `remote get-url origin`, `symbolic-ref --short refs/remotes/origin/HEAD`, `rev-parse --verify --quiet refs/remotes/origin/BRANCH` and `cat-file -e SHA^{commit}`, each bounded by `gitTimeout` (`300 * time.Millisecond`) and memoized per process.
- Output shape: when a line changed, the `displayContent` envelope with the whole rewritten flush. Otherwise nothing.
- Disabled when `CC_LINK_ALL_REFS` is `0`.

## busy-poll

Events: Stop and PreToolUse. `busypoll.Run` in `busypoll/hook.go`. An empty event name counts as Stop. Any other event allows.

- Input fields: `hook_event_name`, `transcript_path`, `session_id`, `stop_hook_active`, `tool_name` and `tool_input`.
- Remote only: `remoteSession` is true when `CLAUDE_CODE_REMOTE_SESSION_ID` is set, or `CLAUDE_CODE_REMOTE` is set to anything but empty, `0`, `false`, `no` or `off`. A terminal session is never woken by an event, so a re-read there is the only way to learn that the answer moved. Only the terminal rule (below) applies outside a remote session.
- Every failure allows. An unreadable or missing transcript allows every call.

### Stop: a run of identical turns

- `parseTurns` reads the last `transcriptTailBytes` (`6 << 20`) of the transcript. A turn is everything the assistant did after a real user prompt. A user record that holds only `tool_result` blocks continues the turn.
- A turn's signature is its sorted tool calls, each as the tool name and the JSON input with sorted keys. A turn with no tool call has an empty signature and never refuses.
- `streak` counts the trailing run of turns that share the last turn's signature, where each follows the previous one within `maxGap()`. A gap is the start of a turn minus the end of the one before it.
- The guard refuses when the streak reaches `threshold()`. `defaultThreshold` is `4`, and `NO_BUSY_POLL_THRESHOLD` overrides it with an integer above `1`. `defaultMaxGap` is `5 * time.Minute`, and `NO_BUSY_POLL_MAX_GAP_SECONDS` overrides it with a positive integer of seconds. A bad value falls back to the default.
- Verdict: stderr holds the refusal text from `reasonTemplate` and the exit code is `2`. The text names the streak length, lists the repeated calls (a Bash call shows its command, other tools show compact JSON, each cut to `200` characters plus `...`), and gives ways out. This also covers reply with no tool call and wait for a real signal, or arm a real wakeup. When `stop_hook_active` is true it adds that a repeat will refuse again.

### PreToolUse: a status read that cannot learn anything

- `judgeCall` refuses a call only when `isStatusRead` holds. A status read is a Bash command in statement position that starts with one of `gh wait-ci`, `gh pr view`, `gh pr checks`, `gh pr status`, `gh pr list`, `gh run view`. `gh run list` or `gh run watch`, or a tool whose bare name (after the last `__`) is in `statusReadTools`. `pull_request_read`, `list_pull_requests`, `search_pull_requests`, `get_commit`, `list_commits`, `list_branches`, `get_session`, `list_sessions`, `list_triggers`, `readnotifications`, `taskget`, `taskoutput` and `tasklist`. `gh wait-ci` followed by `log`, `grep`, `annotations`, `artifacts`, `jobs` or `workflows` reads output, not state, and is not a status read.
- The subject is what the call asks about (`subjectsIn`). `pr:OWNER/REPO#N` or `pr:#N` for a pull request, found by slug. That `pr:OWNER/REPO#N` is by JSON fields, or by `gh pr view|checks|status N` with an optional `--repo`, and `sha:` plus the first several characters for a commit. A call with no subject is allowed. Keying on the subject stops a re-spelled command from hiding a repeat.
- Evidence ages out: `recentRecords` keeps only transcript records written within `maxGap()` of now. A transcript with no usable timestamp is used whole.
- Terminal rule, applies in every session: `terminalSubjects` finds subjects the transcript shows settled. A record settles a pull request when it carries one of `"outcome":"merged"`, `"merged":true`, `"state":"merged"`, `"state":"closed"`, `pull_request.closed` or `has been merged` and names exactly one pull request. It settles a commit. This happens when it carries `ci passed`, `rollup: success` or `(rollup: success)`, or when every `N/M builds passed` tally. In it is full with a nonzero total, and names exactly one commit. A call about a settled subject is denied with the text `terminalText`.
- Repeat rule, remote sessions only: `readSinceLastSignal` finds subjects already read. That rule is with a result that was not an error, since the last thing that can change an answer. That thing is a new user prompt, a wake marker (`<wake reason=`, `<task-notification>`, `<webhook-payload>`, `<event source=`). A user message typed mid-turn, or a Bash call to `git push`, `git commit`, `git merge`, `gh wait-ci dispatch` or `gh wait-ci rerun` (`worldChangers`). A second read of such a subject is denied with `repeatText`.
- Both refusal texts say how long until the refusal lapses, from `maxGap()`, in whole minutes or in seconds.
- Output shape: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}`. A call it does not refuse emits nothing.

## md-budget

Events: SessionStart, PostToolUse and Stop. `mdbudget.Run` in `mdbudget/hook.go`. It recovers from any panic and reports nothing, with the panic text on stderr.

- Measured files: every `CLAUDE.md` under the working directory (the walk skips `.git` and `node_modules`), `~/.claude/CLAUDE.md`, and every `.md` file in `~/.claude/claude_snippets`. For a path a tool names, `isInstructionFile` accepts a file named `CLAUDE.md` and a `.md` file whose directory is named `claude_snippets`.
- Size is the count of characters (`utf8.RuneCountInString`), not bytes.
- Constants: `defaultBudget` is `40000`, `minBudget` is `1000`, `nearFraction` is `0.975` and `widthLimit` is `150`. `nearLimit` is the budget times `nearFraction`, rounded up. A file at or above it counts as at the wall.
- `CC_CLAUDE_MD_BUDGET` sets the budget. An empty or unparseable value keeps the default. A value of `0` or less disables the guard. A positive value below `1000` becomes `1000`.
- `CC_CLAUDE_MD_WIDTH` set to `1`, `true`, `yes` or `on` turns on the wrap check. It is off otherwise, and `measure` then returns no wide lines to any caller. A wide line is over `150` characters and has a space inside its first `150` characters. Fenced lines, lines indented by multiple spaces, and lines that start with `|`, `>` or `#` are exempt.
- State: a per-session JSON file `claude-md-budget/<first 16 hex of SHA-256 of session_id>.json` in `os.TempDir()`. It holds `paths` (files this session left offending), `fired` (the signature the Stop gate blocked on, per file), `seen` (a size and mtime signature per candidate), `candidates` and `walked_at`. A candidate list is reused for `walkTTL` (`120` seconds). Losing the file costs a repeated notice, not an incorrect verdict.
- Input fields: `cwd`, `hook_event_name`, `session_id`, `stop_hook_active`, `full_scan` and `tool_input.file_path`. An unparseable payload counts as SessionStart in the current directory. `full_scan` is never sent by Claude Code. It serves CI: it prints the plain-text census and exits `1` when any file is over the budget, otherwise `0`.
- SessionStart (and any other event name): records the snapshot, then reports every candidate at or above `nearLimit`, worst first. Output is `additionalContext`, headed `INSTRUCTION-FILE BUDGET EXCEEDED` when any file is over, else `INSTRUCTION FILE AT THE BUDGET WALL`.
- PostToolUse: when `tool_input.file_path` is an instruction file, only it is measured. Otherwise the guard compares signatures with the stored snapshot and measures the files that changed, which catches an edit made through Bash. An offender (at the wall, over, or wide when the wrap check is on) is recorded in `paths`. The report is `additionalContext` for the worst one, with how much the uncommitted copy grew over `HEAD` when git can say.
- Stop: ignored when `stop_hook_active` is true or `session_id` is empty. For each recorded path that is still an offender and whose signature differs from the one in `fired`, the guard stores the signature. The guard adds the file to the refusal. Nothing to refuse means nothing. The marker is kept, so a file left unchanged never blocks twice, while a file touched again and left broken blocks again.
- Stop verdict: stdout is `{"decision":"block","reason":"..."}` with exit `0`. The reason tells the model to move a section into `docs/<topic>.md` verbatim. The reason leave a one-line pointer, or to say plainly what it left oversized. A width-only offender gets the wrap remedy instead.
- Every report ends with the remedy list from `remedy` and `remedyFor`: extraction, not summarization, and no appending to an oversized item.

## See also

- [clean-bash](clean-bash.md) and [auto-allow](auto-allow.md) for the guards with a page of their own
- [no-work-loss](no-work-loss.md) for the `no-work-loss` guard
- [message-rules](message-rules.md) for the detectors behind the message guards
- [commands](commands.md) for the event table and `--only`
