# rules

Every detection slopfix reports is a registered rule. A rule is one `RuleSpec` (`rule.go`) with a detection. The repair that answers it, and the worked cases that prove both. The registry refuses to start a binary that holds a rule without all three, and one common test drives every rule on every case.

## RuleSpec

Each rule lives in its own `rule_<category>_<name>.go` file and registers itself from `init`. No file holds a list of the rules, so a deleted rule file takes its rule with it.

A read of an unchanged fixture is answered once for every rule that asks. `remembered` keys the findings by a SHA-256 digest of the read kind, the root, the message and every file. The cache holds at most `fixtureReadCap` entries, which is `64`, and is cleared when it fills.

## RuleCase and Materialize

A `RuleCase` is a fixture: a repository and a closing message.

`Materialize(dir, c)` writes the repository under `dir`. It runs `git init -q` there, writes each file with `0o755` directories and `0o644` files, then runs `git add -A` and a commit. The files are committed because a rule about a committed file asks git what the tree holds. When `Path` is set, its `Text` joins `Files` under that path. Afterwards `Path` is empty, `Text` holds the message alone, `Files` is nil and `Root` is `dir`, so every rule reads one shape.

`fixtureFiles` lists every regular file under `Root` outside `.git`, sorted by absolute path. `eachText` hands every file and then the message to a repair, and writes a changed file back. `allTexts` answers every file and then the message.

## Registration

`RegisterRule` panics at init when a rule is malformed. Each panic names the rule:

- an empty `ID`
- an empty `Category`, because `--only` cannot select it
- a nil `Detect`
- a nil `Autofix`. The message says a detection with no autofix hands the reader a finding with no way out of it
- no `Cases`, because the harness has no case to prove the detection
- an `ID` registered twice

`Registered(findings)` returns the findings unchanged and panics on a finding whose ID no rule registered. The panic text is `a finding under "<id>", and no rule registers that ID`. `registeredHits` does the same for the tombstones a repair keeps. A detection thus cannot reach a reader without the autofix and the case of its rule.

`Repairable(id)` (`repairable.go`) is true when the ID is registered and its `Autofix` is non-nil.

`ReportableIDs` lists every ID a package below the root can report, read from each package's own list and not from the registry.

## Rule table

A finding is an error unless its rule is in `ste.WarningIDs` or `workflow.WarningIDs`. A finding with `Severity` equal to `ste.SeverityWarning`, which is `"warning"`, is a warning (`ste.Finding.Warning`). A warning fails no check.

## The common test

`TestEveryRuleUndergoesTheCommonTest` in `ruleharness_test.go` runs every case of every registered rule in these steps, with no way for a rule or case to skip one:

```
* <input fixture, which includes the case(s) that the rule should detect>
* run ALL OTHER rules on the fixture, confirming that there are no detections other than the current rule we're testing
* run the rule on the fixture, confirming it is detected
* run the rule on the result, confirming it was fixed (i.e. no longer detected)
* run ALL OTHER rules on the "fixed" fixture, confirming there are STILL no detctions.
```

The mechanics of each step:

- The fixture is `Materialize(t.TempDir(), raw)`.
- `everyOtherRule` calls `Detect` of every registered rule except the one under test. Each finding it returns fails the step.
- The rule's own `Detect` must return at least one finding, and every finding must carry the rule's own ID.
- The result is `rule.Autofix(fixture)`. The rule's `Detect` must return nothing on it.
- `everyOtherRule` runs again on the result and must return nothing.

A rule thus never leaves text that another rule flags, and a repair never hands another rule new text. A fixture is clean to every rule but its own.

## The repair guarantee

`allfix_test.go` holds `TestFixLeavesNoErrorOnAnyTree`.

The test runs `CheckTreeWith` first. Then it runs `FixTreeWith` and requires `Unmet` to be empty and a second `CheckTreeWith` to hold no error. `errorLines` counts a finding that is not a warning, and every kept tombstone. The test also asserts specific repaired wording in `README.md`, and that `justfile` and `docs/agents-continued.md` exist.

## The Fix loop

`Fix(req)` in `fix.go` runs `fixAll`, then limits the result to the scope of the request. `fixAll` returns the text unchanged for an exempt file (`tombstones.Borrowed` or `commentfix.IsGenerated`). Otherwise it calls `fixText`, which does this:

- That kind includs an empty path.
- It opens the file with `fixer.Open`, with the caller's category selection (`Wants`), rule selection (`Keeps`), scope, `MaxCommentLines` and `Creates`. `Creates` is on only when the request is not `OneFile`, has no bounded scope, and either has no `Owned` scope or an owned scope. That scope covers the whole file.
- It runs `fixer.Run(f, fixer.For(kind))` for at most `fixRounds` rounds, which is `4`. A round that leaves the text unchanged ends the loop. The rounds exist because one repair can hand a later rule new text, such as a division that leaves a count. The bound stops repairs that undo each other.
- Each new file a repair creates is itself repaired with `fixAll`, with `OneFile: true`, so it lands clean whatever the run selected.
- It then collects the findings no rewrite answers. `pins.CheckPath` runs when `RulePins` is wanted. A workflow adds `workflow.Check` findings and the sentence cap. A source file adds `commentFindings`, and `comments/length` as kept hits. A document adds `counts.SectionFindings` and `Check`.
- The result passes through `Registered` and `registeredHits`.

`Report(req)` runs the same path with no repair landing, so every finding is reported on the text as it stands.

Fixers register themselves with `fixer.Register` and run in ascending `Place` order. The places in the code are. `10` tombstones (`tombstones/repair.go`), `20`. `21` counts (`counts/counts.go`, `counts/sections.go`) and the comment length repair (`commentfix/repair.go`), `30` the wrap and STE pass (`fix.go`) and the comment number repair, `35` long block (`longblock.go`). And comment sentences (`commentfix/sentences.go`), `40` a second counts pass and a second comment length repair, `80` workflow test extraction (`workflow/repair.go`). `1000` pins (`pins/pins.go`) and `2000` the Go layout pass (`fix.go`, `goformat.Name`).

The Go layout pass runs only on a `.go` file that another fixer changed.

## slopfix-expect annotations

The `expect` package marks a fixture file whose repair is stated in the file itself.

`fixAll` applies the package. A file with any annotation, or any annotation error (`Annotations.Any`), is a fixture:

- The rules run on `Stripped`. A bounded scope is shifted with `Shift`.
- `Repair.Unmet` holds the result of `Check`.
- The returned `Text` is the original text, `Changed` is false, and the scope is the original scope. A fixture is never rewritten.

`UnmetError` carries the path and the unmet lines, and `FixFile` returns it for a file on disk. `expect_test.go` proves that the annotated file is left as it was. Those proves are that an annotation the repair breaks lands in `Unmet`, and that `FixFile` returns an `UnmetError` and leaves the file on disk unchanged.

## Hooks mapping

`hooks.go` holds `hooks`, the only mapping from a hook, a gate or a build phase to the rules it runs. `Only` holds a category or a rule ID. An empty `Only` is the default set.

`Selects(hook)` resolves a hook to rule IDs. A pending hook selects nothing. An entry that names a category expands to every rule in it. An entry that is not a category is added as an ID, and an empty `Only` selects `AllIDs()`.

It holds no repository rule and no message rule. Those reach a hook through the `ci check` entry and the message entries.
