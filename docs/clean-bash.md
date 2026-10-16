# clean-bash: the Bash rewriter

`clean-bash` rewrites a Bash command wherever a rewrite exists, and denies it only where none does. The package is `bashclean/`. `bashclean.Run` in `bashclean/run.go` is the hook entry point and `bashclean.Transform` in `bashclean/clean.go` is the rewriter.

## Registration

`cmd/guards.go` registers `clean-bash` on the event `eventPreToolUse` only. On PreToolUse the guards run in the order `clean-bash`, the write guard, `no-work-loss`, `auto-allow`, `busy-poll`. A rewrite of the tool input reaches every guard after it, so no later guard judges a command that will not run (`preToolUse` in `cmd/guards.go`). The first deny ends the chain.

## Entry point

`Run` reads a PreToolUse payload (`Input`: `hook_event_name`, `tool_name`, `tool_input`, `cwd`) and returns a `HookResult` with `Stdout`, `Stderr` and `Code`. It returns the zero result (silence, the command runs as written) when:

- the reader fails or the payload is not JSON.
- `hook_event_name` is set and is not `PreToolUse`.
- `tool_name` is not `Bash`.
- `tool_input` is not a JSON object, or its `command` is missing or empty.
- the command parses and no rule applies.
- the command does not parse (`Transform` fails open and returns the command unchanged).

Silence is every failure path. `TestRunFailsOpen` in `bashclean/run_test.go` covers invalid JSON, empty stdin, a non-Bash tool, a missing command, another event, unparseable Bash and a command that needs nothing.

Otherwise `Run` calls `TransformIn(command, in.Cwd)` and answers one of two ways.

A deny (`Result.Denied`) returns `denyPayload(denyReason(res.Reason))`:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}
```

A rewrite (`Result.Changed`) returns `rewritePayload(raw)`, where `raw` is the whole original `tool_input` map with only `command` replaced, so every other key (such as `description`) rides along untouched:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"..."}},"suppressOutput":true}
```

## Silent output

A rewrite carries `updatedInput` and `suppressOutput: true` and nothing else. It sets no `permissionDecision`, so the normal permission flow still judges the rewritten command. It has no `systemMessage` and no `additionalContext`. It says nothing to the user or the model. A visible message will give the model something to blame for its own command mistakes. `TestRunRewriteIsSilent` pins this.

A deny must carry a reason, because a denial without one makes the model retry forever. `denyReason` maps the rule name in `Result.Reason` to a sentence that names the alternative that works.

| Reason | Sentence |
|---|---|
| `heredoc` (the default case) | `Heredocs are banned in this environment. Write file content with the Write/Edit tools; for command stdin use printf '%s' ... \| cmd or a temp file.` |
| `perl` | `perl is banned in this environment.` |
| `shred` | `shred/srm destroy data unrecoverably by design and are banned in this environment. There is no safe equivalent; if the file must go, use recycler trash <path> and it can be restored.` |
| `git_rm` | `git rm --pathspec-from-file hides which files it deletes, so it cannot be rewritten to recycler trash. Name the paths: git rm <path>... is rewritten to git rm --cached plus recycler trash.` |
| `truncate_zero` | `truncate -s 0 empties a file in place, destroying its contents unrecoverably. Use recycler trash <path> instead, which moves it to the recycle bin.` |
| `rm_flag` | `This rm carries a flag that cannot be translated to recycler trash.` and the list of accepted flags: `-r`, `-R`, `--recursive`, `-f`, `--force`, `-v`, `--verbose`, `-i`, `-I`, `--interactive` and `--`. |
| `toolchain_capture` | `go-toolchain`'s full output has to land in the transcript. A pipe or redirect is stripped for it, but a `$(...)` or `<(...)` capture cannot be. Run it bare. |

## Debug log

`CLEANUP_BASH_CMDS_LOG` names a file. When it is set, `logLine` in `bashclean/run.go` appends one line per event, opening the file with `O_APPEND|O_CREATE|O_WRONLY` and mode `0o644`. A failure to open or write never breaks the hook. The hook is silent toward the user and the model. This is the only debug channel.

- `DENY\toriginal=%q\treason=%q`
- `REWRITE\toriginal=%q\tcleaned=%q\trules=%q`, where `rules` is the comma-joined list of rule names that changed the tree.

`TestRunLogsToTheDebugChannel` expects `rules="rm_recycle,pipefail"` for `rm -rf build`.

## The transform

`transform(command, dir, passes, warn)` in `bashclean/clean.go` parses the command with `syntax.NewParser(syntax.Variant(syntax.LangBash))`. A parse error returns the command unchanged. `Result` holds `Command`, `Denied`, `Reason`, `Changed` and `Rules`. A denied command is returned unchanged with the rule name in `Rules`.

The steps run in this order:

1. `heredoc` deny: `hasHeredoc` finds a `Hdoc` or `DashHdoc` redirect anywhere in the tree, including inside a command substitution. A here-string and a bit shift in arithmetic are not here-documents.
2. `perl` deny.
3. Read plan. If `PlanRead(command, dir)` returns a plan, the command is returned unchanged, so a mapped file read runs as written (see Read plans).
4. `shred` deny.
5. `git_rm` deny.
6. `truncate_zero` deny.
7. `rm_flag` deny.
8. `toolchain_capture` deny.
9. The rewrite rules, run to a fixed point.
10. `pipefail`, applied once after the loop.

The denies are checked before any rewrite, so a command with a denied part is never half-rewritten.

`effectiveCommand` in `bashclean/words.go` names the program a call runs. It uses `shellwalk.StripWrappers`, so a rule covers `sudo`, `env`, `nice`, `timeout`, `nohup`, `busybox`, `xargs`, `command`, `builtin`, a leading backslash and an absolute path alike (`TestWrappedCommandsResolve`). A non-static command word, and a lookup such as `command -v rm`, resolve to nothing.

### The fixed-point loop

The rules run to a fixed point because one rule's output is another rule's input and a single pass leaves the later rewrite undone. `runToFixedPoint` prints the tree, runs `onePass`, prints it again, and stops when the prints are equal. It returns false when the pass bound runs out.

`maxPasses` is `20`. The comment on it says raising it answers no non-convergence.

When the bound is exhausted, `reportNonConvergence` writes to the `warn` writer (`os.Stderr` in production) a message that starts with `cleanup-bash-cmds: the rewrite did not reach a fixed point in %d passes, so a pair of rules is undoing each other. Emitting the partial rewrite.`. That `cleanup-bash-cmds: the rewrite did not reach a fixed point in %d passes, so a pair of rules undo each other. The original and the partial command follows emitting the partial rewrite.`. It goes to stderr and not the debug log. This is because it reports a defect in the rules and must be visible without a log path set.

The partial rewrite is still emitted. `TestExhaustingTheBoundSaysSo` runs the transform with a bound of `1`, and `TestTheChainedRulesConverge` shows `cmd | grep x 2>&1` converging to `cmd`.

A rewrite maps over, edits within or prepends to the statement list, so it can add a statement and never drop one (`TestRewriteNeverDropsAStatement`).

`apply(name, fn)` prints the tree before and after `fn`, and adds `name` to `Rules` (once) only if the printed tree changed. `Changed` is true when the last print differs from the print before any rule. The printer is `syntax.NewPrinter`. The emitted command is the printer's canonical form, with a trailing newline.

### Pass order

`onePass` applies the rules in this order:

| Name | Function | What it does |
|---|---|---|
| `devnull` | `scrubDevnull` | drops stderr discards |
| `grep_json` | `grepJSON.apply` | turns a grep over JSON into jq |
| `toolchain_output` | `undivertToolchain` | keeps `go-toolchain` output on the terminal |
| `docker_compose_restart` | `dockerCompose` | rewrites `docker compose restart` |
| `gh_wait_ci` | `ghWaitCI` | rewrites Actions reads to `gh wait-ci` |
| `git_cd` | `rewriteGitC` | writes `git -C dir` as `cd dir && git` |
| `git_rm_recycle` | `rewriteGitRM` | unstages then recycles |
| `rm_recycle` | `rewriteRM` | writes `rm` as `recycler trash` |
| `truncate_recycle` | `rewriteTruncate` | recycles a truncate to zero |
| `find_delete_recycle` | `rewriteFind` | recycles `find -delete` |
| `or_true` | `stripOrTrue` | drops a trailing `\|\| true` |
| `grep` | `stripStages` with `isGrepStage` | drops a trailing `\| grep` |
| `stderr_merge` | `stripMerge` | drops a trailing `2>&1` |
| `tee` | `teeRewrite` | turns a trailing stdout redirect into `\| tee` |
| `sleep_cap` | `capSleep` | caps `sleep` |
| `narration_remove` | `narration` | drops constant `echo` and `printf` from their list or chain |
| `noop_remove` | `dropNoops` | drops a bare `true` or `:` from a list or chain that does real work |

After the loop `apply("pipefail", ensurePipefail)` runs once.

## Trailing rules

`bashclean/trailing.go` holds the rules anchored at the end of the command. A limiting pipe, a stdout redirect or a swallowed exit status in the middle of a script is a deliberate part of a longer script. It is preserved. The same shape on the last top-level statement truncates the answer the reader was about to get. It is stripped there and nowhere else.

The anchor is the last top-level statement (`trailing`), taken down the right branch of its `&&` and `||` chain (`spineLeaf`, since the parser builds these left-associative). `lastStage` is the textual end of a pipeline. `promoteInto(outer, inner)` lifts a statement over its parent, keeping the parent's negation, background and coprocess flags and appending its redirects after the inner ones.

- `or_true`: `stripOrTrue` removes a trailing `|| true` while the right side is a bare `true` (`isBareTrue`: one word, no assignments, no redirects, not negated, not backgrounded). This restores the real exit status.
- `grep`: `stripStages` removes trailing pipeline stages (`syntax.Pipe`) whose call is `grep` (`isGrepStage`), repeatedly. A grep that is not at the end of the pipeline stays: `foo | grep foo | head -5` is unchanged, `cmd | tail -10 | grep foo` becomes `cmd | tail -10`. `head` and `tail` stages are never stripped.
- `stderr_merge`: `stripMerge` removes trailing `2>&1` redirects (`DplOut` on descriptor `2` with the word `1`) from the last stage.
- `tee`: see the next section.

A grep or merge on a non-last line, inside `$(...)`, inside `<(...)` or inside a quoted string is untouched.

### tee

`teeRewrite` turns a trailing stdout file redirect into a pipe through `tee`, so the output lands in the file and stays visible. `cmd > f` becomes `cmd | tee f`, and `cmd >> f` becomes `cmd | tee -a f`. For a pipeline, the redirect on the last stage moves to a last `tee` stage (`a | b > f` becomes `a | b | tee f`). A stdin redirect stays on the producer (`cmd <in | tee out`). The rewrite applies only when the statement has exactly one stdout file redirect (descriptor absent or `1`, with `>` or `>>`) and `isStdoutFileTeeable` accepts it. The target is not a process substitution and does not start with `/dev/`.

A statement with several stdout redirects is left alone.

Because the trailing anchor is the last `&&` member, `cmd > f && next` keeps its redirect and `next && cmd > f` becomes `next && cmd | tee f`.

### pipefail

The `tee` rewrite introduces a pipe, so `ensurePipefail` keeps the producer's exit status observable. It prepends the statement `set -o pipefail` to the statement list unless `enablesPipefail` finds it already enabled on the leftmost statement of the first `&&` chain. Pipe follows enablesPipefail` recognizes a `set` call where an option word matching `-[A-Za-z]*o`fail`. `set -o pipefail`, `set -eo pipefail`, `set -euo pipefail`, `set -e -o pipefail` and several `-o` pairs all count. A strictness setting the caller wrote is never removed. Because `ensurePipefail` runs on every command that parses, a rewrite or a no-op command of any kind gets the prefix.

This happens unless it already has it. `Changed` is true in that case, so the first line of an emitted command is `set -o pipefail`.

## devnull

`bashclean/redirects.go` scrubs the stderr discard, tree-wide, over every statement's redirect list. Stderr is how a command reports its own failure. A discarded stderr costs another call asking whether it worked. `scrubRedirs` makes one positional pass:

- `2>/dev/null` and `2>>/dev/null` (`isStderrDevnull`: descriptor `2`, `>` or `>>`, target `/dev/null`) are dropped.
- `&>/dev/null`, `&>>/dev/null` and `>&/dev/null` (`isAllDevnull`: no descriptor, `RdrAll`, `AppAll` or `DplOut`) are demoted to `>/dev/null` or `>>/dev/null`. This keeps the stdout half the command asked for and frees only stderr.
- A stdout discard (`isStdoutDevnull`) is kept and recorded.
- A bare `2>&1` (`isStderrToStdout`) is dropped only when an earlier entry in the same list already sent stdout to `/dev/null`. The reversed spelling `2>&1 >/dev/null`, which sends stderr to the terminal, is left alone. A bare merge elsewhere survives, because it is a merge and not a discard.
- Other redirects survive, including `2>errors.log`, `12>/dev/null`, `2>/dev/null2` and `2>/dev/null.log`.

The target must be the exact word `/dev/null`. The rule matches parsed redirects and not text, so a quoted string that contains `2>/dev/null` is untouched.

## Recycling deletions

Delete-then-Write is the loophole around the Write refusal, so deletions go through `recycler trash`, which moves a path to the recycle bin. `recycler restore` brings it back. A command that already starts with `recycler trash` or `recycler restore` is not rewritten.

### rm_recycle

`rewriteRM` rewrites a call whose effective command is `rm`. It keeps any wrapper prefix and replaces `rm` plus its flags with `recycler trash` plus the targets (`rmTargets`). The accepted flags (`droppableRM`) are `--recursive`, `--force`, `--verbose`, `--interactive`, and short clusters made only of `r`, `R`, `f`, `v`, `I` and `i`. They are dropped, because `recycler trash` understands only paths. `--` ends flag parsing and is re-emitted in front of the targets only when a target begins with `-` (`needsSeparator`). A lone `-` is a filename.

Non-literal words (`"$DIR"`, globs) pass through as targets. `rm` with no targets becomes bare `recycler trash`.

Examples from `bashclean/ported_test.go`: `rm -rf a b` becomes `recycler trash a b`, `rm -- -weirdname` becomes `recycler trash -- -weirdname`, `xargs -0 rm -f` becomes `xargs -0 recycler trash`, `\rm -f x` becomes `recycler trash x`. `rmdir` and `rm` in a string argument are untouched.

An `rm` with any other flag is denied as `rm_flag` (see Denials).

### truncate_recycle

`rewriteTruncate` rewrites a `truncate` that empties a file. `isTruncateZero` recognizes the size flag in every spelling: `-s 0`, `-s0`, `--size=0`, `--size 0` (the value matches `^0+$`). The call becomes `recycler trash` plus the targets (`truncateTargets`). Any other flag fails the rewrite. The call is denied as `truncate_zero`, since `-r RFILE` names a reference file and keeping its value will recycle an untouched file. A nonzero size is untouched.

### find_delete_recycle

`rewriteFind` replaces each `-delete` word of a `find` call with `-exec recycler trash {} +`. The primaries after it keep their place.

### git_rm_recycle

`bashclean/gitrm.go` parses a `git rm` call (`parseGitRM`). The subcommand is the leading non-flag word after `git`, so `git -c k=v rm f` counts and `git commit -m rm` does not. `--cached`, `--dry-run` and any short cluster containing `n` delete nothing, so they are not matched and pass through.

`rewriteGitRM` writes `git rm opts -- paths` as `git rm --cached opts -- paths && recycler trash paths`. Unstaging comes first. A path already gone from disk still gets its deletion staged. A path git does not track stops the chain before anything moves. Assignments on the original call stay on the first command. The `recycler trash` call gets `--` only when `needsSeparator` says a path needs it.

A call with `-C` is not rewritten here. This is because `git_cd` turns `-C dir` into a `cd` first and the next pass then sees a plain `git rm` (`git -C /repo rm foo` becomes `cd /repo && git rm --cached -- foo && recycler trash foo`). A call with `--pathspec-from-file` is denied as `git_rm`, since the paths are hidden and no rewrite can name what to recycle.

## git_cd

`rewriteGitC` (`bashclean/gitcd.go`) lifts every `-C dir` out of a git call's global options, because a permission rule reads `git push` and `-C dir` will stand between both words. `splitGitC` keeps the other global options (`-c`, `--git-dir`, `--work-tree`, `--namespace` take a value), and keeps flags before the subcommand. A `-C` after the subcommand (`git grep -C 3 foo`) is not the global option. The call becomes `cd d1 && cd d2 && git args` (`cdChain`, one `cd` per `-C`, in order).

The `cd` stays bare only on the command's trailing leaf (`spineLeaf` of the last statement). This holds where nothing runs after it, and only when the statement has no redirects, is not negated, backgrounded or a coprocess. Anywhere else the chain is wrapped in a subshell so the directory change reaches the git call alone (`git -C /a fetch && ls` becomes `(cd /a && git fetch) && ls`). A statement with a redirect gets the subshell, and the `tee` rule then moves the redirect.

## docker_compose_restart

`docker compose restart ARGS` becomes `docker compose up -d --force-recreate ARGS`. It matches the words `docker`, `compose`, `restart` at the start of a call, anywhere in the tree. `docker-compose restart` and the text in a `grep docker compose restart` argument list are untouched.

## gh_wait_ci

`bashclean/ghwaitci.go` rewrites Actions reads into the `gh wait-ci` extension, because the shim refuses `gh run`, `gh workflow` and `gh pr checks` at run time. Each costs a tool call to fail. Only these forms are rewritten, and a form outside the table is left alone:

| Before | After |
|---|---|
| `gh run view <id> --log-failed` | `gh wait-ci log <id> --failed` |
| `gh run view <id> --log` | `gh wait-ci log <id>` |
| `gh run view <id>` | `gh wait-ci view <id>` |
| `gh run watch <id>` | `gh wait-ci <id>` |
| `gh run rerun <id>` | `gh wait-ci rerun <id>` |
| `gh run list [flags]` | `gh wait-ci runs [flags]` |
| `gh pr checks [flags]` | `gh wait-ci checks [flags]` |

The run id must be digits (`runID` is `^[0-9]+$`), which keeps the rewrite off an expansion. Remaining flags and values (such as `-R o/r`) carry over. `gh run list` and `gh pr checks` rewrite only when `onlyFlagsAndValues` holds, meaning no positional word remains. Consider a bare word right after a dash word. That right is that flag's value, a `--flag=value` carries its own, and any other bare word is a positional that names a subject (so `gh pr checks 42` is left alone).

## sleep_cap

`capSleep` caps every `sleep` call at `3` seconds. The wait is the sum of the arguments. Each argument must match `^([0-9]+(?:\.[0-9]*)?|\.[0-9]+)([smhd]?)$`, with the suffix scaling by `1`, `60`, `3600` or `86400`. A sum over `3` becomes `sleep 3`. A call with no argument, a non-literal argument (a variable or substitution), or an argument that does not match the pattern (`infinity`, `1e-3`, `abc`) also becomes `sleep 3`. A sum of `3` or less is kept as written.

Assignments and redirects on the call are preserved. It matches only a call whose first word is `sleep`, so `timeout 5 sleep 30` and a string `"sleep 30"` are untouched.

## narration_remove

`bashclean/narration.go` turns a constant `echo` or `printf` into the no-op `:` only when its stdout reaches the terminal. `dropNoops` then removes that `:` from its list or chain. In a pipeline, or where its status decides a condition, the `:` stays. A command whose only work is narration stays as written, because the auto-allow guard refuses a command that runs nothing.

`noop_remove` drops a bare `true` or `:` from a list or chain that does real work. A no-op stays where nothing else runs, as a pipeline stage. Those stays are as the last statement of a nested list, and before a read of `$?`. A `false` stays, because it fails the list.

`isNarration` accepts `echo` with all-constant words, and `printf` with at least one word, all constant (`allConstant`). A word is constant (`wordIsConstant`) when it is made of literals. This holds with no glob character (`*`, `?`, `[`, `{`) and no leading `~`, single-quoted text, or double-quoted literals. A variable, command substitution or arithmetic makes it non-constant.

Visibility threads top-down through the statement structure (`narrationStmt`), and the traversal never enters word parts, which excludes every capture by construction:

- A statement is visible when its parent is visible, its redirects touch stderr only (`redirsStderrOnly`), and it is not a coprocess. A stderr redirect stays on the `:` (`echo warn 2>>err.log` becomes `: 2>>err.log`).
- In a pipeline, the left side is not visible. The right side takes the pipeline's visibility.
- `&&` and `||` members, blocks, subshells, loop bodies, `if` and `elif` conditions and branches, `case` items and `time` take the visibility of their parent.
- A function body is not visible, since the call site decides.
- `X=$(echo hi)`, `echo x | jq`, `echo x > f` and `echo foo >&2` are data and stay.

## toolchain_output and toolchain_capture

A pipe, a redirect or a capture truncates exactly what a `go-toolchain` run is for: the coverage list, the test failures and the build errors. `undivertToolchain` (`bashclean/toolchain.go`) strips them silently so the run lands in the transcript.

- A pipeline whose first stage (`pipeHead`) is `go-toolchain` is replaced by that stage. Everything after the pipe is dropped, including `|& tee log`, so `go-toolchain | tee log; git push` becomes multiple statements.
- On a `go-toolchain` statement, redirects that move stdout are dropped (`redirectsStdout`: `>`, `>>`, `&>`, `&>>` on descriptor `1` or none). A redirect of stderr alone survives (`go-toolchain > log 2> errors` becomes `go-toolchain 2>errors`).

A `go-toolchain` inside a command or process substitution is denied as `toolchain_capture`. This is because the output feeds a value to the rest of the script and removing the substitution will change what the script computes. A program is `go-toolchain` when `effectiveCommand` names it, so `sudo go-toolchain` counts. Redirecting any other command is ordinary and the `tee` rule applies.

## grep_json

`bashclean/grepjson.go` rewrites a grep over JSON files into a `jq` query. grep reads a JSON file as lines of text. It matches escape sequences and punctuation and prints a fragment with no path to the value. `jq` tests the keys and the decoded values instead. The output has shapes:

- JSON Lines: each matching record, whole and compact, as grep prints a line.
- A document: each matching leaf as `.path.to[0].key = value`.

The table is `bashclean/grepjson.xml`, validated by `bashclean/grepjson.xsd` and embedded as `grepJSONXML`. `mustLoadGrepPrograms` panics on a malformed table. A broken file stops the binary at its first start instead of rewriting nothing. The file holds:

- `<fixture name kind>`: test inputs with kind `document`, `lines`, `one-line` or `none`.
- `<flags name>`: named flag sets of `<flag short long effect value>`. `effect` must be one of the set `grepEffects`: `pattern`, `ignore-case`, `case-sensitive`, `smart-case`, `invert`, `basic`, `extended`, `fixed`, `perl`, `word`, `line`, `with-filename`, `no-filename`, `line-number`, `no-line-number`, `count`, `none`. A flag needs one short letter or a long spelling. `value="optional"` lets a long flag take `=value` (as `--color`).
- `<program name flags syntax>`: the programs the rule rewrites, each tied to a flag set and a regex syntax (`basic`, `extended`, `perl` or `fixed`). The shipped programs are `grep` (flag set `grep`, `basic`), `egrep` (`extended`), `fgrep` (`fixed`) and `rg` (flag set `rg`, `perl`).
- `<translate syntax from to>`: regex translation cases that test `posixToOnig`.
- `<test cmd keep>`: each carries the expected output of the rewritten command run against the fixtures, or `keep="true"` when the grep must stay.

A flag outside the program's set stops the rewrite, so `-A`, `-l`, `-o` and `-r` keep the grep. `rg -h` and `rg -q` are not in the `rg` set, since `rg` reads `-h` as help and `-q` as quiet.

### When the rewrite applies

`rewrite` acts on a `CallExpr` statement when `effectiveCommand` names a program in `grepPrograms` and no `xargs` wrapper precedes it. `parseGrep` must succeed: every word it keeps is a literal, because the pattern becomes part of the jq regex. Several patterns (`-e`, `--regexp`) are allowed, and a pattern flag in a short cluster takes the rest of the cluster or the next word.

The inputs are the file operands, or the file in a `<` stdin redirect when there are none. `operandKind` decides the kind of all inputs and rejects the rewrite when:

- a word is not literal, is empty, is `-`, starts with `~`, or contains `{` or `}`.
- a glob matches nothing (a glob expands as the shell expands it, against the directory the command runs in).
- an operand is not JSON (`notJSON`).
- the operands differ in kind, since a document and a stream print different shapes (`merge`). A `jsonOneLine` file merges with either.

With `-c` and more than one input the rewrite is skipped, since one query cannot print a total per file.

The content decides and never the extension. `sniffJSON` in `bashclean/jsonsniff.go` stats the path and opens only a regular, non-empty file, because an open on a FIFO blocks. It reads a fixed head of `sniffHead` (`64 << 10` bytes) and, for a larger file, a tail of `sniffTail` (`4 << 10` bytes). A larger file counts only if its last non-white-space byte closes an object or array (`closesJSON`). `classify` strips a UTF-8 BOM, requires a leading `{` or `[`, and tokenizes the head: a syntax error is never acceptable. An unexpected end is acceptable only when the head is cut.

More than one top-level value is `jsonLines`. A single value on a single line is `jsonOneLine`, which reads as either kind. Any other result is `jsonDoc`. The sniff results are cached per Transform in `grepJSON.cache`, because the fixed-point loop asks about the same file each pass.

### The query

The rewrite replaces the call with `jq -n -r --arg re <regex> '<program>' <files>`, keeping the wrapper prefix and the original file words. The program reads every input with `inputs`, so a file operand and a stdin redirect take the same path. The pieces are the constants `jqPath`, `jqRecords` and `jqLeaves` in `bashclean/grepjson.go`.

- OnigRegex`: each pattern line becomes `(?:. builds the regex..)`, joined with `|`. A newline in a pattern separates alternatives, as for grep. `-x` wraps it as `\A(?:...)\z`, and `-w` as `(?<!\w)(?:...)(?!\w)`.
- The syntax is translated for Oniguruma with `translatePattern`. Fixed patterns are escaped (`reMeta`). Perl patterns pass through, and POSIX patterns go through `posixToOnig` in `bashclean/posixregex.go`, which swaps the meaning of the escaped and bare forms of `( ) { } | + ?`. For basic syntax, turns `\<` and `\>` into `\b`, escapes a leading `*`, a mid-pattern `^` and a `$` that is not an anchor. Escapes backslash, `[` and `&` inside a bracket expression. An unterminated bracket or trailing backslash fails the translation and keeps the grep.
- The case flag (`caseFlag`) is `i` for `-i`. Smart case is `i` unless a pattern holds an upper-case letter.
- A match tests every key. Every decoded scalar of a record (lines), or every string in the path and the decoded value of a leaf (document). `-v` appends `| not`.
- `-c` wraps the stream as `[...] | length`.
- The file name prefix is shown with `-H`, and with several inputs unless `-h` or `-I` was given. The line number prefix (`-n`) applies to lines only. A document has no line to number, because its path is the location.
- Shel quots a pattern or program with a single quotelWord`, which closes the quote and adds an escaped quote.

## Read plans

`PlanRead(command, dir)` in `bashclean/readplan.go` maps one plain file read onto Read tool calls. It returns a `ReadPlan{Reads []ReadArgs, Note string}`, where `ReadArgs` is `file_path`, `offset` and `limit` (the last two omitted when zero). It returns nil when the command has no exact Read equivalent. The caller then runs the command as written.

The command must be one statement that is a plain call. It must have no redirects, no background, no negation, no coprocess and no assignments, and `effectiveCommand` must name the program. Every argument must be literal and contain none of `*`, `?` or `[`. The supported programs:

- `cat`: files, with `-n` and `--number` ignored. Any other flag, or no file, returns nil.
- `head` and `tail`: the count in each spelling (`-n N`, `-nN`, `--lines=N`, `--lines N`, `-N`), default `defaultLines` (`10`). Every file gets the same count. `head` maps to `limit`. `tail -n N` maps to an offset from the end, which needs the file's line total. `tail -n +N` maps to `offset` only. A count of zero, `head` with `+N`, and any other flag (`-c`, `-f`, a negative count) return nil.
- `sed`: `-n` (or `--quiet`, `--silent`) with one `Np` or `A,Bp` script and exactly one file. A range with `A` equal to zero or `B` below `A` returns nil, as does any other flag, so `sed -n -e 3p` is not mapped. `sed` numbers lines across all its files as one stream, so a second file does not map.
- `awk`, `gawk`, `mawk`. A program made only of line-number comparisons (`NR` or `FNR` with `==`, `>=`, `<=`, `>`, `<`) joined by `&&`, optionally followed by `{print}`, `{print;}` or `{print$0}`, after blanks are removed. `NR` counts across files, so it maps only on one file. `FNR` restarts per file and maps on several. A range that selects no line returns nil, as does a leading flag or an operand containing `=`.

`resolve` makes each path absolute: `~` and `~/` expand against the home directory, and a relative path joins `dir`, which must itself be absolute (a relative path with no directory has no absolute form). `readPath` cleans the path and leaves a pseudo-file under `/proc`, `/sys` or `/dev` (`magicPath`) to Bash. A tail count needs the line total from `countLines`. This counts a last line with no newline and fails for a missing file, a non-regular file or a file over `maxCountBytes` (`10 << 20`).

`readNote` builds the note. `Your Bash command ` followed by the command in backticks, then ` read a file, so its output is shown as the Read tool shows it. These Read calls give the same lines:`, one `- Read(file_path: "...", offset: N, limit: N)` line per read, and the closing sentence `Use the Read tool to read files. Its offset and limit parameters select lines, which is what head, tail, sed -n and awk were for.` `TestPlanReadNote` pins the exact text.

`transform` calls `PlanRead` before the destructive denies and the rewrite rules. A command that maps is returned unchanged, so `cat`, `head`, `tail` and `sed -n` run as written.

### RunPost

`RunPost` in `bashclean/readoutput.go` answers a PostToolUse payload (`hook_event_name`, `tool_name`, `cwd`, `tool_input.command`, `tool_response.stderr`, `tool_response.interrupted`). It returns silence unless the event is `PostToolUse`, the tool is `Bash`. The call was not interrupted, stderr is empty, `PlanRead` maps the command, and every file can be read. Otherwise it returns:

```json
{"hookSpecificOutput":{"hookEventName":"PostToolUse","updatedToolOutput":{"stdout":"...","stderr":"","interrupted":false},"additionalContext":"<the plan note>"}}
```

The stdout shows each read as the Read tool shows it (`readText`): the line number, a tab and the line. That stdout is with a trailing carriage return cut, from `offset` (at least `1`) for `limit` lines (all lines when `limit` is zero). A blank line joins with several files each part gets a header `==> PATH <==` and the parts.

`cmd/guards.go` does not register `RunPost` on any event. It is an exported function with tests in `bashclean/readoutput_test.go`, and the plugin's tool.call module can call the binary through `check read-plan`.

### check read-plan

`cmd/readplan.go` adds the command `slopfix check read-plan`. It reads a JSON object `{"command": ..., "cwd": ...}` on stdin. It prints the plan as one JSON line: `{"reads":[...],"note":"..."}` for a command that maps, and `{"reads":null,"note":""}` for any other command. Stdin that is not a `{command, cwd}` object fails with `read-plan: stdin is not a {command, cwd} object`.

## Denials

Every denial is returned as `Result{Command, Denied: true, Reason}` with `Reason` also in `Rules`. It carries no `updatedInput`. A denied command is never rewritten.

| Reason | Detected by | Scope |
|---|---|---|
| `heredoc` | `hasHeredoc` | the whole tree, including substitutions |
| `perl` | `hasStatementCall` with `perlName` (`^perl[0-9.]*$`) on the effective command | statement level: simple calls, `&&` and `\|\|` chains, pipes, blocks, subshells, `if`, loops, `case`, `time`, function bodies. A `perl` inside `$(...)` is not denied |
| `shred` | effective command `shred` or `srm` | statement level |
| `git_rm` | `hasUnrewritableGitRM`: a `git rm` with `--pathspec-from-file` | statement level |
| `truncate_zero` | `hasBadTruncate`: a truncate to zero that `truncateTargets` rejects | statement level |
| `rm_flag` | `hasBadRM` with `rmUnknownFlags`: an `rm` flag outside `droppableRM` before any `--` | the whole tree, including `$(...)` |
| `toolchain_capture` | `capturesGoToolchain` | any command or process substitution |

`perlName` matches `perl`, `perl5`, `perl5.36` and their wrapped forms (`command perl`, `\perl`, `/usr/bin/perl`). `perlcritic` and a `perl` argument to another program are not matched. A `shred`-like name such as `shredder` is a different command.

## See also

- [auto-allow](auto-allow.md) for the guard that judges the rewritten command
- [no-work-loss](no-work-loss.md) for the guard that sees the original command
- [hook-guards](hook-guards.md) for the guard table
- [commands](commands.md) for the `hook` command and its event table
