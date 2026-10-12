# auto-allow

`auto-allow` answers permission questions from a table. It approves read-only work, refuses programs this environment does not run, and refuses calls that reach a denied tree. Everything else gets no answer. The call takes the normal permission path. The package is `autoallow/`, and `autoallow.Run` in `autoallow/run.go` is its entry point.

## Registration and events

`cmd/guards.go` registers the guard with the events `eventPreToolUse` (`PreToolUse`) and `eventPermissionRequest` (`PermissionRequest`). A `clean-bash` rewrite of the command reaches `auto-allow`, so it judges the command that will run.

It returns the zero `Result` (silence) when:

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
2. Read tools.
3. MCP tools. `parseMCPTool(hi.ToolName)` splits the name. A name that parses is allowed on PermissionRequest when `matchMCPServer` finds it in the table. Any other MCP call gets silence, and the function returns here so an MCP call never reaches step 4.
4. Bash. Any tool other than `Bash` gets silence. A Bash call goes to `evaluateCommandWith(hi.ToolInput.Command, table)`.

## Input

Each tool fills the keys its own shape has and leaves the rest empty.

## Path rules

A `<denyPath prefix="...">message</denyPath>` element becomes a `PathRule` in `Rules.DenyPaths`. `loadXMLRules` trims the whitespace of both fields. `matchPathRule` in `autoallow/paths.go` returns the message of the first rule the call reaches.

For each rule it expands the prefix with `expandHome` and cleans it with `filepath.Clean`. A prefix that expands to the empty string is skipped. The call reaches the rule in multiple ways:

- `underRoot`: any of the path fields resolves to the root or to a path under it. An empty field never matches. The field goes through `expandHome`. A relative path joins the call's `cwd`, which is what the tool will do, and a relative path with an empty `cwd` never matches.
- `commandReaches`: the command text contains a spelling of the root. A shell command names its locations as bare words. Key scans the text.

When the home directory cannot be found it answers the empty string, which allows. A guard that refuses because it can not find a home directory will be worse than no guard.

The shipped table has one rule: prefix `~/.claude/plugins` with the message `Go to the plugin source directory instead.` The tree is refused whole. `paths_test.go` proves a Read, Write, Edit and Grep of that tree are refused on PreToolUse, a Read on both events.

## MCP tools

`parseMCPTool` in `autoallow/mcp.go` accepts a name that starts with `mcp__`. It splits on the last `__`. The server is the text between the prefix and that separator. The tool is the text after it. A name with no later separator, or one where the last separator sits at index 4 or earlier, returns multiple empty strings. A server name with single underscores, such as `Claude_Code_Remote`, survives the split.

`matchMCPServer` walks the `Rules.MCPServers` map. For each entry it applies `path.Match` of the entry key to the server, then `path.Match` of each tool pattern to the tool. One match allows. An empty or nil map allows nothing.

`loadXMLRules` builds the map from `<mcpServer name="...">` elements with `<tool>` children. A repeated server name replaces the earlier entry.

The trust unit is the server and not a tool-name pattern. The server author chooses tool names, so a pattern such as `get_*` guarantees nothing about a server nobody checked. The table therefore has no server-name wildcard that matches everything. An unlisted server is never allowed. A glob inside a server entry is used only where every tool it matches on that server's real surface was checked to be read-only.

`actions_*` is deliberately not a glob for `github`, because it will match `actions_run_trigger`. `TestShippedRulesAllowReadOnlyMCPTools` pins the allowed and refused names, including `mcp__CONTENTdm__search_items` and `mcp__Robinhood__get_equity_quotes`, which stay unallowed because their servers are unlisted.

### The Claude_Code_Remote decision

`rules.xml` has no `mcpServer` block for `Claude_Code_Remote`, on purpose.

The reason, from the comment in `rules.xml`: the remote proxy replies with the code `-32003` (needs approval). The client raises a card for a human to click. A hook decision makes the client cancel the bridge request that displays the card and re-issue the call byte-identically with no grant. The server is still waiting on a human, so it rejects the call again and the one permitted retry is spent. The visible symptom is a card that flashes and vanishes, then a hard failure. With no block, the hook returns nothing, the dialog stands and a click authorizes the call.

Adding the server back to fix `send_later` is the regression.

## Bash commands

`evaluateCommandWith(command, rules)` in `autoallow/hook.go` takes the rule set as a value. Only `evaluateCommand` reads the package-level `rules` variable. The empty behavior means no decision.

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

The `until` rule exists because the harness re-invokes a session when a background command exits. A shell that waits holds the turn open and the session deadlocks.

### Layer 2: argv rules in the deny and ask sections

If layer 1 gave no answer, `parseAllCommands` in `autoallow/shell.go` reads the command into a list of argument lists. It returns nil. The evaluator returns no decision, when:

- the command does not parse.
- `hasOutputRedirect` finds an output redirect that `isAllowedRedirect` does not accept.
- a statement is not a simple call, `&&`, `||` or pipe (loops, conditionals, subshells and blocks yield nil).
- `hasDangerousConstruct` finds a command substitution, parameter expansion, arithmetic expansion or process substitution anywhere in a statement.
- a word is not made of literals, single-quoted text and double-quoted literals, or is empty.

`isAllowedRedirect` accepts a merge of stderr into stdout (`2>&1`). The clean defeats `/tmp/../etc/passwd`. The target must be a plain literal.

With a parsed list, the evaluator tests the deny section and then the ask section: for each command, `evaluateArgs(args, section.nodes, rules.Allow)`. A result of `allow` or `deny` from any command returns the section's behavior, with the message that `evaluateArgs` returned. The section gives the verdict, not the rule, so an same node denies under `<deny>` and allows under `<allow>`.

### Layer 3: the allow section

Every command in the list must be allowed: `evaluateArgs(args, rules.Allow, rules.Allow)` per command. Any `deny` result returns `deny` with its message. Any other non-allow result makes the whole command pass through with no decision. If all commands are allowed, the answer is `allow`. A compound therefore clears the bar only when every part clears it.

## Argv rule evaluation

`evaluateArgs(args, nodes, allow)` matches `args[0]` against each node's name and evaluates every match with `evaluateOneNode`. Deny beats allow beats passthrough across the matching nodes, so duplicate entries merge. `TestDuplicateEntriesMerged` and `TestDuplicateEntriesDenyWins` pin this. `allow` is the top-level allow set, carried down for the `execFlags` recursion.

A node's `name` is a literal word or a comma-separated list of spellings (for example `awk,gawk,nawk,mawk`). `matchesName` compares the exact string.

`evaluateOneNode` applies the following checks in this order. The first one that returns ends the evaluation of that node.

Flag matching in `hasAnyFlag` accepts a bare flag and the `--flag=value` form.

### Refusals

A `Refusal` denies a command outright with its `Message`. It is a verdict of its own. The command is ordinary, and what its arguments carry decides it. `Refusal.matches` skips the rule's own word, then requires every kind of condition given to hold. Within one kind, one value is enough. A refusal with no conditions never matches.

The branch-deletion messages tell the model that deleting a branch is the user's call. The pull-request message says closing a pull request is the user's call and that `gh pr view` is the only pull request command this session runs.

## The table format

`autoallow/rules.xml` is embedded with `go:embed` (`rulesXML` in `autoallow/run.go`), so the table travels inside the single binary and a missing file cannot silently turn every rule off. `autoallow/rules.xsd` describes it. `loadXMLRules` in `autoallow/rules_xml.go` passes the bytes through `table.Readable`, which rewrites an XML 1.1 declaration to 1.0 so `encoding/xml` accepts it, then decodes into `xmlRules`.

A rule with `command=` becomes a process rule. Every other rule becomes a `CommandNode`. A `<test>` has `cmd` and `expect`. An empty `expect` means the hook answers nothing.

The XML parses before it is used. A `--` inside an XML comment is the usual cause of a parse failure. A failure turns every rule off. `TestRulesXMLIndentedWithTabs` requires that no line of `rules.xml` starts with a space.

## Tests carried by the table

`<test>` elements live where their rule lives, in any section, and at the root. `loadEmbeddedTests` in `autoallow/hook_test.go` collects the root tests and walks the allow, ask and deny sections recursively through subcommands. `TestEvaluateCommands` runs each one through `evaluateCommandWith` with the shipped rules and compares the behavior to `expect`. The collection fails if it finds none.

## The shipped allow section

The allow section is a read-only inspection list.

The ask section is empty on purpose. The ask section everything not allowed already reaches the user. An entry earns its place only by making a specific request louder than the default prompt.
