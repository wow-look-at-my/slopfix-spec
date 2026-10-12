# auto-allow

`auto-allow` answers permission questions from a table. It approves read-only work, refuses programs this environment does not run, and refuses calls that reach a denied tree. Everything else gets no answer. The call takes the normal permission path. The package is `autoallow/`, and `autoallow.Run` in `autoallow/run.go` is its entry point.

## Registration and events

`cmd/guards.go` registers the guard with the events `eventPreToolUse` (`PreToolUse`) and `eventPermissionRequest` (`PermissionRequest`). On PreToolUse the guards run in the order `clean-bash`, the write guard, `no-work-loss`, `auto-allow`, `busy-poll`, and the first refusal is the answer. A `clean-bash` rewrite of the command reaches `auto-allow`, so it judges the command that will run.

`Run` reads the payload from its reader and returns a `Result` with `Stdout`, `Stderr` and `Code`. It returns the zero `Result` (silence) when:

- the reader fails or the payload is not JSON.
- `hook_event_name` is neither `PermissionRequest` nor `PreToolUse`.
- `loadXMLRules` fails on the embedded table.
- no rule decides the call.

Silence is the fail-open answer. A malformed table therefore disables every rule, and `TestRulesXMLParses` in `autoallow/hook_test.go` exists to catch that.

## Why the two events are not interchangeable

`Run` sets `denyOnly` when the event is `PreToolUse`. The events then differ as follows.

| Verdict | PermissionRequest | PreToolUse |
|---|---|---|
| deny | answered | answered |
| allow | answered | never answered |
| ask | answered (see below) | never answered |

An allow on PreToolUse will settle the call before the user's own deny rules vote, so allow rides PermissionRequest only. A deny that rides PermissionRequest alone is silent under auto mode, so deny also rides PreToolUse. `TestPreToolUseDeniesButNeverAllows` pins both halves. Denied commands must produce a deny on PreToolUse, and allowed commands, the Read tool and unmatched commands must produce no output there.

The verdict is computed from `tool_input` alone, so a call judged on both events gets the same verdict on each. `Run` drops the verdict instead of the work: for a Bash call it evaluates the command, then returns silence when `denyOnly` is set. The decision is not `deny`.

The ask verdict exists in the evaluator (`evaluateCommandWith` can return `ask`). The shipped `<ask>` section is empty, so no shipped rule produces one.

## Response shapes

`decisionPayload(event, behavior, message)` in `autoallow/hook.go` renders the answer for the event it serves, followed by a newline. The Claude Code CLI rejects a `hookEventName` that is not the event it dispatched, so the shape follows the event and not the verdict.

For `eventPreToolUse` it marshals `PreToolUseResponse`, a flat object:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}
```

For every other event it marshals `PermissionResponse`, a nested decision:

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
```

The `message` field is omitted when empty on both shapes. A deny always carries a message, because the reason reaches the model verbatim. A marshal failure returns the empty string.

## Order of evaluation in Run

1. Path rules. `matchPathRule(hi, table.DenyPaths)` runs first, for every tool. A hit answers `deny` with the rule's message, on either event. The read tools are approved wholesale in step 2, and an approval settles the call, so location is judged first.
2. Read tools. A `Read`, `Glob` or `Grep` tool name is allowed on PermissionRequest and gets silence on PreToolUse.
3. MCP tools. `parseMCPTool(hi.ToolName)` splits the name. A name that parses is allowed on PermissionRequest when `matchMCPServer` finds it in the table. Any other MCP call gets silence, and the function returns here so an MCP call never reaches step 4.
4. Bash. Any tool other than `Bash` gets silence. A Bash call goes to `evaluateCommandWith(hi.ToolInput.Command, table)`.

## Input

`HookInput` reads `hook_event_name`, `tool_name`, `cwd` and `tool_input`. `ToolInput` holds the keys `command`, `file_path`, `notebook_path`, `path` and `pattern`. Each tool fills the keys its own shape has and leaves the rest empty. `ToolInput.pathFields` returns `FilePath`, `NotebookPath`, `Path` and `Pattern`, which are the keys that can carry a location.

## Path rules

A `<denyPath prefix="...">message</denyPath>` element becomes a `PathRule` in `Rules.DenyPaths`. `loadXMLRules` trims the whitespace of both fields. `matchPathRule` in `autoallow/paths.go` returns the message of the first rule the call reaches.

For each rule it expands the prefix with `expandHome` and cleans it with `filepath.Clean`. A prefix that expands to the empty string is skipped. The call reaches the rule in multiple ways:

- `underRoot`: any of the path fields resolves to the root or to a path under it. An empty field never matches. The field goes through `expandHome`. A relative path joins the call's `cwd`, which is what the tool will do, and a relative path with an empty `cwd` never matches.
- `commandReaches`: the command text contains a spelling of the root. A shell command names its locations as bare words. Key scans the text. `homeSpellings` gives the absolute root and, when the root sits under the home directory, the `~`, `$HOME` and `${HOME}` forms.

`expandHome` resolves `~`, `$HOME` and `${HOME}`, bare or followed by a slash. When the home directory cannot be found it answers the empty string, which allows. A guard that refuses because it can not find a home directory will be worse than no guard.

The shipped table has one rule: prefix `~/.claude/plugins` with the message `Go to the plugin source directory instead.` The tree is refused whole. `paths_test.go` proves a Read, Write, Edit and Grep of that tree are refused on PreToolUse, a Read on both events. Path also proves that every branch below it (`cache`, `marketplaces`, `repos`, `config.json`) and the tree itself are refused.

## MCP tools

`parseMCPTool` in `autoallow/mcp.go` accepts a name that starts with `mcp__`. It splits on the last `__`. The server is the text between the prefix and that separator. The tool is the text after it. A name with no later separator, or one where the last separator sits at index 4 or earlier, returns multiple empty strings. A server name with single underscores, such as `Claude_Code_Remote`, survives the split.

`matchMCPServer` walks the `Rules.MCPServers` map. For each entry it applies `path.Match` of the entry key to the server, then `path.Match` of each tool pattern to the tool. One match allows. An empty or nil map allows nothing.

`loadXMLRules` builds the map from `<mcpServer name="...">` elements with `<tool>` children. A repeated server name replaces the earlier entry.

The trust unit is the server and not a tool-name pattern. The server author chooses tool names, so a pattern such as `get_*` guarantees nothing about a server nobody checked. The table therefore has no server-name wildcard that matches everything. An unlisted server is never allowed. A glob inside a server entry is used only where every tool it matches on that server's real surface was checked to be read-only.

The shipped servers:

| Server pattern | Tool patterns |
|---|---|
| `grafana` | `get_*`, `list_*`, `search_*`, `query_*` |
| `github` | `get_*`, `list_*`, `search_*`, `issue_read`, `pull_request_read`, `actions_get`, `actions_list` |
| `Context7*` | `resolve-library-id`, `query-docs` |
| `Playwright` | `browser_snapshot`, `browser_console_messages`, `browser_network_request`, `browser_network_requests`, `browser_take_screenshot`, `browser_find` |
| `plugin_grep_*` | `Grep` |
| `plugin_glob_*` | `Glob` |

`actions_*` is deliberately not a glob for `github`, because it will match `actions_run_trigger`. `TestShippedRulesAllowReadOnlyMCPTools` pins the allowed and refused names, including `mcp__CONTENTdm__search_items` and `mcp__Robinhood__get_equity_quotes`, which stay unallowed because their servers are unlisted.

### The Claude_Code_Remote decision

`rules.xml` has no `mcpServer` block for `Claude_Code_Remote`, on purpose. The hook stays silent for every tool of that server on both events, and `TestCCRToolsAreNeverAnsweredByThisHook` pins multiple tool names (including `send_later`, `add_repo`, `subscribe_pr_activity` and `create_trigger`) to empty output.

The reason, from the comment in `rules.xml`: the remote proxy replies with the code `-32003` (needs approval). The client raises a card for a human to click. A hook decision makes the client cancel the bridge request that displays the card and re-issue the call byte-identically with no grant. The server is still waiting on a human, so it rejects the call again and the one permitted retry is spent. The visible symptom is a card that flashes and vanishes, then a hard failure. With no block, the hook returns nothing, the dialog stands and a click authorizes the call.

Adding the server back to fix `send_later` is the regression.

## Bash commands

`evaluateCommandWith(command, rules)` in `autoallow/hook.go` takes the rule set as a value. It returns a behavior (`allow`, `ask`, `deny` or the empty string) and a message. Only `evaluateCommand` reads the package-level `rules` variable. The empty behavior means no decision.

The evaluation runs in the order of the headings below: process rules, then argv rules in the deny and ask sections, then the allow section.

### Layer 1: process rules

A rule with a `command=` attribute is a process rule (`CommandRule`). `loadXMLRules` separates process rules from argv rules when it reads each section. This covers constructs the allow path refuses to read: command substitutions, subshells, conditionals and redirects. A denied program must never be one `$(...)` away from running.

Sections are tried in the order deny, then ask. The first rule that matches returns its section as the behavior. A rule with no `message` gets `<name> may not be run here.` A parse error returns no match.

`matchCommandRule` first calls `matchKeyword`, which answers a rule whose name is a shell keyword the command uses. It recognizes `while` and `until`, found on the `WhileClause` node (`Until` selects the name). A rule named `until` therefore matches the loop and not a program.

Then it finds the statements that are the right side of a pipe (`syntax.Pipe` or `syntax.PipeAll`). For each `CallExpr` statement it resolves the program with `shellwalk.ResolveProgram`, which removes wrappers, absolute paths and version suffixes. `shellwalk.MatchesProgram(name, rule.Name)` decides the match. A trailing version counts as the same program, so `python` covers `python3.11`. Stdin when it is a pipe target or has a here-document feeds a statement, here-string or `<` redirect.

A rule with `inlineScript="true"` (`InlineOnly`) matches only when `isInlineScript` is true, which spares `node script.js`. `isInlineScript` is true when any of these holds:

- an argument is in `shellwalk.StdinMarkers` (`-` or `/dev/stdin`).
- an argument equals an `evalFlags` entry.
- an `evalFlags` entry is a short flag (a dash and one letter). An argument is a single-dash cluster that contains that letter, so `perl -pe` and `-lane` match `-e`.
- the first argument equals an `evalSubcommands` entry (as in `deno eval`).
- Stdin and `shellwalk.NamesAScript` finds no script operand feeds the statement, so stdin is the program and not its input.

A named script makes stdin its input, so `printf ... | node hook.ts` is not denied.

The shipped deny process rules:

| `command` | Narrowing | Message |
|---|---|---|
| `python` | none | `Python is not available here. Use jq for JSON and node for scripts.` |
| `until` | keyword | `Do not wait in the shell. End the turn and read the output when the command reports, or use gh wait-ci for CI.` |
| `true`, `false`, `:` | none | `This command does nothing. Run the real one, or say what is blocking.` |
| `node` | inline, `-e`, `--eval`, `-p`, `--print` | write the script to a file |
| `ruby`, `lua`, `Rscript`, `osascript` | inline, `-e` | write the script to a file |
| `perl` | inline, `-e`, `-E` | write the script to a file |
| `php` | inline, `-r` | write the script to a file |
| `deno` | inline, `-e`, `--eval`, subcommand `eval` | write the script to a file |
| `bun`, `tsx`, `ts-node` | inline, `-e`, `--eval` | write the script to a file |

The `until` rule exists because the harness re-invokes a session when a background command exits. A shell that waits holds the turn open and the session deadlocks.

### Layer 2: argv rules in the deny and ask sections

If layer 1 gave no answer, `parseAllCommands` in `autoallow/shell.go` reads the command into a list of argument lists. It returns nil. The evaluator returns no decision, when:

- the command does not parse.
- `hasOutputRedirect` finds an output redirect that `isAllowedRedirect` does not accept.
- a statement is not a simple call, `&&`, `||` or pipe (loops, conditionals, subshells and blocks yield nil).
- `hasDangerousConstruct` finds a command substitution, parameter expansion, arithmetic expansion or process substitution anywhere in a statement.
- a word is not made of literals, single-quoted text and double-quoted literals, or is empty.

`isAllowedRedirect` accepts a merge of stderr into stdout (`2>&1`). A write on descriptor 1 or 2 with `>`, `>>`, `&>` or `&>>` to `/dev/null` or to a path under `/tmp/` after `path.Clean`. The clean defeats `/tmp/../etc/passwd`. The target must be a plain literal.

With a parsed list, the evaluator tests the deny section and then the ask section: for each command, `evaluateArgs(args, section.nodes, rules.Allow)`. A result of `allow` or `deny` from any command returns the section's behavior, with the message that `evaluateArgs` returned. The section gives the verdict, not the rule, so an same node denies under `<deny>` and allows under `<allow>`.

### Layer 3: the allow section

Every command in the list must be allowed: `evaluateArgs(args, rules.Allow, rules.Allow)` per command. Any `deny` result returns `deny` with its message. Any other non-allow result makes the whole command pass through with no decision. If all commands are allowed, the answer is `allow`. A compound therefore clears the bar only when every part clears it.

## Argv rule evaluation

`evaluateArgs(args, nodes, allow)` matches `args[0]` against each node's name and evaluates every match with `evaluateOneNode`. Deny beats allow beats passthrough across the matching nodes, so duplicate entries merge. `TestDuplicateEntriesMerged` and `TestDuplicateEntriesDenyWins` pin this. `allow` is the top-level allow set, carried down for the `execFlags` recursion.

A node's `name` is a literal word or a comma-separated list of spellings (for example `awk,gawk,nawk,mawk`). `matchesName` compares the exact string.

`evaluateOneNode` applies the following checks in this order. The first one that returns ends the evaluation of that node.

1. `helpAlwaysAllowed` with `--help` or `-h` among the remaining arguments: allow.
2. `denyWithMessage` set: deny with that message.
3. Each `refuse` that matches the arguments: deny with its message.
4. `denyArgSubstrings`: if any argument contains a listed substring, the node does not match (no decision). The substring appears inside a script argument, not as its own word.
5. `requiredFlags`: allow if any listed flag is present, otherwise no decision.
6. `bareOnly`: allow if there are no remaining arguments, otherwise no decision.
7. `requireFlagValue`: read the value of the first listed flag (or `default`), allow if it is in the `allowed` list, otherwise no decision.
8. `flagsWithValue` flags and their values are removed before subcommand matching.
9. Subcommands: if the node subcommand rules and arguments remain, recurse. A decision from the subcommand is last. If none is made and the leading word does not start with `-`, the result is no decision, so an unknown. Otherwise, mutating word never falls through to `allowedFlags`.
10. `deniedFlags`: if any is present, no decision.
11. `execFlags`: for each flag, `extractExecSubCommands` collects the words after it up to `;` or `+`, dropping `{}`. Each sub-command is evaluated against the top-level allow set. A deny result denies, and anything not allowed gives no decision.
12. `allowedFlags`: with `*` the node allows. With a list, every argument that starts with `-` must be in the list (`checkAllowedFlags`). With `allowedArgPrefixes`, at least one positional argument is required and every positional must start with a listed prefix.
13. Otherwise no decision.

Flag matching in `hasAnyFlag` accepts a bare flag and the `--flag=value` form.

### Refusals

A `Refusal` denies a command outright with its `Message`. It is a verdict of its own. The command is ordinary, and what its arguments carry decides it. `Refusal.matches` skips the rule's own word, then requires every kind of condition given to hold. Within one kind, one value is enough. A refusal with no conditions never matches.

- `Flags` (`<flag>`): a whole-word match, or a `--flag=value` form. A two-character short flag also matches inside a short group (`isShortGroup`: one dash, then letters only), so `-d` refuses `-fd`.
- `FlagValue` (`<flagValue>` with `<flag>` and `<value>`): a flag whose value equals one of the values, case-insensitively. It accepts `-X V`, `--long=V` and `-XV` for a two-character short flag.
- `ArgPrefixes` (`<argPrefix>`): an argument that starts with a prefix.
- `ArgSubstrings` (`<argSubstring>`): an argument that contains a substring, so a request body counts.

The shipped refusals:

- `git push` with `--delete`, `-d`, `--prune` or `--mirror`, and with an argument that starts with `:` or `+:` (an empty source deletes the remote branch).
- `git branch` with `--delete`, `-d` or `-D`.
- `git update-ref` with `--delete` or `-d`.
- `gh api` with a `-X` or `--method` value of `DELETE` together with an argument containing `/git/refs/`, and `gh api` with an argument containing `deleteRef`.
- `gh api` and `curl` with an argument containing `state=closed`, `"state":"closed"` or `"state": "closed"`.

The `git` deny rule lists `-C`, `-c`, `--git-dir`, `--work-tree` and `--namespace` under `flagsWithValue`, so global options do not hide the subcommand. The branch-deletion messages tell the model that deleting a branch is the user's call. The pull-request message says closing a pull request is the user's call and that `gh pr view` is the only pull request command this session runs.

## The table format

`autoallow/rules.xml` is embedded with `go:embed` (`rulesXML` in `autoallow/run.go`), so the table travels inside the single binary and a missing file cannot silently turn every rule off. `autoallow/rules.xsd` describes it. `loadXMLRules` in `autoallow/rules_xml.go` passes the bytes through `table.Readable`, which rewrites an XML 1.1 declaration to 1.0 so `encoding/xml` accepts it, then decodes into `xmlRules`.

The root `<rules>` holds, in any order:

- `<test cmd="..." expect="...">`: a cross-cutting test.
- `<allow>`, `<ask>`, `<deny>`: sections of `<rule>` elements.
- `<mcpServer name="...">` with `<tool>` children.
- `<denyPath prefix="...">` with the message as its text.

A `<rule>` carries these attributes: `name` (a comma-separated list of spellings of the word as typed), `description`, `command` (the resolved process name), `inlineScript`, `evalFlags`, `evalSubcommands` (comma-separated lists), `message`, `allowedFlags` (the value `*`), `denyWithMessage`, `helpAlwaysAllowed` and `bareOnly`. Its children are `<test>`, `<allowedFlags>`, `<deniedFlags>`, `<execFlags>`, `<requiredFlags>` and `<flagsWithValue>` (each holds `<flag name="...">` elements), `<denyArgSubstrings>` and `<allowedArgPrefixes>` (each holds `<value>` elements), `<refuse message="...">`, `<requireFlagValue default="...">` (with `<flag>` and `<allowed>`), and nested `<rule>` elements, which are subcommands.

A rule with `command=` becomes a process rule. Every other rule becomes a `CommandNode`. A `<test>` has `cmd` and `expect`. An empty `expect` means the hook answers nothing.

The XML parses before it is used. A `--` inside an XML comment is the usual cause of a parse failure. A failure turns every rule off. `TestRulesXMLIndentedWithTabs` requires that no line of `rules.xml` starts with a space.

## Tests carried by the table

`<test>` elements live where their rule lives, in any section, and at the root. `loadEmbeddedTests` in `autoallow/hook_test.go` collects the root tests and walks the allow, ask and deny sections recursively through subcommands. `TestEvaluateCommands` runs each one through `evaluateCommandWith` with the shipped rules and compares the behavior to `expect`. The collection fails if it finds none.

## The shipped allow section

The allow section is a read-only inspection list. It holds plain commands with `allowedFlags="*"` (for example `ls`, `cat`, `head`, `tail`, `wc`, `stat`, `du`, `df`, `echo`, `printf`, `jq`, `rg`, `fd`, `sort`, `uniq`, `realpath` and `cd`) and commands that need conditions:

- `which` allows any flags. `command` allows only `-v` and `-V`, because bare `command` runs its argument.
- `yq` denies `-i` and `--in-place`. `find` denies `-delete` and checks the commands after `-exec`, `-execdir`, `-ok` and `-okdir`. `mount` is `bareOnly`.
- `awk,gawk,nawk,mawk` deny `-f`, `--file`, `-E`, `-i`, `--include`, `-l`, `--load`, `-D`, `--debug`, `-o`, `--pretty-print`, `-p` and `--profile`. A script argument containing `system(`, `system (`, `getline`, `@include`, `@load`, `>>`, `>"`, `> "`, `|"` or `| "` does not match.
- `ldconfig`, `dpkg`, `just`, `git config`, `git replace` and `git push` allow only listed read flags (`requiredFlags`). `git push` allows only `--dry-run` and `-n`.
- `go` allows `version`, `env` and `doc`, and denies `build` and `test` with a message that names `go-toolchain`.
- `git` allows a list of read subcommands. `branch`, `tag`, `remote`, `submodule status` and `commit-graph verify` narrower flag sets.
- `gh` allows read subcommands of `repo`, `issue`, `release`, `workflow`, `run list`, `search`, `browse`, `label list`, `cache list`, `gist` and `api`. `gh api` uses `requireFlagValue` with default `GET`. `gh pr` allows `view` only, and `gh pr` subcommands such as `checks`, `close`, `create`, `merge` and `list` are denied with `gh pr view is the only gh pr this session runs`. `gh run view` and `gh run watch` are denied with a message that names `gh run list`.
- `claude` allows `--version`, `-v`, `--help` and `-h` anywhere, and read subcommands of `mcp`, `plugin` and `config`.
- `docker`, `docker compose`, `docker-compose`, `zpool`, `zfs`, `apt`, `apt-cache`, `apt-mark`, `dpkg-query` and `brew` allow read subcommands.
- `curl` allows any flags but only when every positional argument starts with `http://localhost:9120/read`. Its `flagsWithValue` list keeps header, data and output values out of the positional check.

The ask section is empty on purpose. The ask section everything not allowed already reaches the user. An entry earns its place only by making a specific request louder than the default prompt.
