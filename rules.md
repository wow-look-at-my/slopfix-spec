# rules

Every detection slopfix reports is a registered rule. A rule is one `RuleSpec` (`rule.go`) with a detection. The repair that answers it, and the worked cases that prove both. The registry refuses to start a binary that holds a rule without all three, and one common test drives every rule on every case.

## RuleSpec

`RuleSpec` in `rule.go` has these fields:

| Field | Type | Role |
|---|---|---|
| `ID` | `string` | The name a report prints and `--only` accepts |
| `Category` | `Rule` | The family `--only` names in full |
| `Detect` | `func(RuleCase) []ste.Finding` | Finds this rule's findings in a case |
| `Autofix` | `func(RuleCase) RuleCase` | Rewrites the case so this rule no longer detects it |
| `Cases` | `[]RuleCase` | The worked examples the harness drives |

Each rule lives in its own `rule_<category>_<name>.go` file and registers itself from `init`. No file holds a list of the rules, so a deleted rule file takes its rule with it. A `Detect` and an `Autofix` are written on the shared reads of `ruleadapt.go`:

- `caseFindings(c, id)` answers the findings one file rule reports anywhere in the case. It runs `CheckContent` and `Report` over every file of the repository that `Reads` accepts, and over the message read as a document with no path.
- `treeFindings(c, id)` answers the findings of one repository rule from `CheckTreeWith` over the case root.
- `messageFindings(c, id)` runs `CheckMessage` on every text of the case, and `messageAutofix` runs `FixMessage`.
- `caseAutofix(c, id)` runs `FixTreeWith` on the case root with `IDs` set to the one rule, and `Fix` on the message text. Both use `tombstones.DefaultMaxCommentLines`, which is `14`.
- `treeAutofix` is `caseAutofix`.

A read of an unchanged fixture is answered once for every rule that asks. `remembered` keys the findings by a SHA-256 digest of the read kind, the root, the message and every file. The cache holds at most `fixtureReadCap` entries, which is `64`, and is cleared when it fills.

## RuleCase and Materialize

A `RuleCase` is a fixture: a repository and a closing message.

| Field | Role |
|---|---|
| `Name` | Labels the case in a failure |
| `Path` and `Text` | One file of the repository and its content. With no `Path`, `Text` is the closing message |
| `Files` | The other files of the repository, by path from its root |
| `Root` | The directory `Materialize` wrote the repository under |

`Materialize(dir, c)` writes the repository under `dir`. It runs `git init -q` there, writes each file with `0o755` directories and `0o644` files, then runs `git add -A` and a commit. The commit message is `fixture`, with `--allow-empty`, `commit.gpgsign=false` and `core.hooksPath=/dev/null`. The files are committed because a rule about a committed file asks git what the tree holds. When `Path` is set, its `Text` joins `Files` under that path. Afterwards `Path` is empty, `Text` holds the message alone, `Files` is nil and `Root` is `dir`, so every rule reads one shape.

`fixtureFiles` lists every regular file under `Root` outside `.git`, sorted by absolute path. `eachText` hands every file and then the message to a repair, and writes a changed file back. `allTexts` answers every file and then the message.

## Registration

`RegisterRule` panics at init when a rule is malformed. Each panic names the rule:

- an empty `ID`
- an empty `Category`, because `--only` cannot select it
- a nil `Detect`
- a nil `Autofix`. The message says a detection with no autofix hands the reader a finding with no way out of it
- no `Cases`, because the harness has no case to prove the detection
- an `ID` registered twice

`AllRuleSpecs` answers the registry in registration order. `RuleSpecByID` answers one rule and whether the name is known, and `AllRules` (`ruleadapt.go`) answers each category in the order a rule first declared it. `IDsFor(category)` answers the IDs of a category, and `EveryID` (`repairable.go`) and `EveryRuleID` (`hooks.go`) answer every ID in the registry.

`Registered(findings)` returns the findings unchanged and panics on a finding whose ID no rule registered. The panic text is `a finding under "<id>", and no rule registers that ID`. `registeredHits` does the same for the tombstones a repair keeps. Every finding passes through `Registered` on its way out of `CheckContent` (`slopfix.go`), `CheckMessage` (`message.go`), `fixText` and `reportAll` (`fix.go`). A detection thus cannot reach a reader without the autofix and the case of its rule.

`Repairable(id)` (`repairable.go`) is true when the ID is registered and its `Autofix` is non-nil.

`ReportableIDs` lists every ID a package below the root can report, read from each package's own list and not from the registry. It is the union of `AllIDs`, `RepoIDs`, `tombstones.AllIDs`, `counts.ID`, `counts.IDSection`, `laziness.ID`, `blamelanguage.ID`, `askproperly.ID` and every `english.Patterns` entry that carries an ID.

## Rule table

A finding is an error unless its rule is in `ste.WarningIDs` or `workflow.WarningIDs`. A finding with `Severity` equal to `ste.SeverityWarning`, which is `"warning"`, is a warning (`ste.Finding.Warning`). A warning fails no check.

| Category | Rule ID | Severity |
|---|---|---|
| `repo` | `repo/agents-file` | error |
| `repo` | `repo/budget` | error |
| `repo` | `repo/package-scripts` | error |
| `repo` | `repo/binary` | error |
| `repo` | `repo/near-duplicate` | error |
| `wrap` | `wrap/hard-wrap` | error |
| `wrap` | `wrap/long-block` | error |
| `ste` | `ste/contraction` | error |
| `ste` | `ste/modal` | error |
| `ste` | `ste/semicolon` | error |
| `ste` | `ste/comma-splice` | error |
| `ste` | `ste/sentence-length` | error |
| `ste` | `ste/postdeterminer` | error |
| `ste` | `ste/count` | error |
| `ste` | `ste/instruction-length` | warning |
| `ste` | `ste/passive` | warning |
| `ste` | `ste/noun-cluster` | warning |
| `ste` | `ste/tense` | warning |
| `ste` | `ste/dictionary` | warning |
| `ste` | `ste/paragraph-length` | warning |
| `english` | `english/comma-never` | error |
| `counts` | `counts/inventory-count` | error |
| `counts` | `counts/section-number` | error |
| `tombstones` | `tombstones/date` | error |
| `tombstones` | `tombstones/change-reference` | error |
| `tombstones` | `tombstones/then-and-now-contrast` | error |
| `tombstones` | `tombstones/position-reference` | error |
| `tombstones` | `tombstones/hedged-time` | error |
| `tombstones` | `tombstones/unstated-value` | error |
| `tombstones` | `tombstones/shrug` | error |
| `tombstones` | `tombstones/unexplained-workaround` | error |
| `tombstones` | `tombstones/name-nothing-in-the-repository-defines` | error |
| `tombstones` | `tombstones/comment-volume` | error |
| `comments` | `comments/number` | error |
| `comments` | `comments/length` | error |
| `comments` | `comments/tail` | error |
| `yaml` | `yaml/comment-block` | error |
| `yaml` | `yaml/all-builds-job` | error |
| `yaml` | `yaml/neutered-gate` | error |
| `yaml` | `yaml/env-indirection` | error |
| `yaml` | `yaml/push-tags` | error |
| `yaml` | `yaml/org-action-ref` | error |
| `yaml` | `yaml/concurrency` | error |
| `yaml` | `yaml/test-in-workflow` | warning |
| `pins` | `pins/download-version` | error |
| `laziness` | `laziness/punt` | error |
| `blame` | `blame/deflection` | error |
| `ask` | `ask/prose-decision` | error |

Where each ID comes from:

- The category constants are in `fix.go`: `RuleTombstones` is `"tombstones"`. `RuleCounts` is `"counts"`, `RuleWrap` is `"wrap"`, `RuleSTE` is `"ste"`, `RuleEnglish` is `"english"`, `RuleComments` is `"comments"`, `RuleWorkflow` is `"yaml"` and `RulePins` is `"pins"`. `RuleRepo` is `"repo"` (`repo.go`). The categories `laziness`, `blame` and `ask` are written as `Rule("laziness")`, `Rule("blame")` and `Rule("ask")` in their rule files.
- The `repo` IDs are `IDAgentsFile`, `IDBudget` (`repo.go`), `IDPackageScripts` (`packagescripts.go`), `IDBinary` (`binaries.go`) and `IDNearDuplicate` (`duplicates.go`). `RepoIDs` lists the five.
- `IDHardWrap` (`slopfix.go`) and `IDLongBlock` (`longblock.go`) are the `wrap` IDs. `LongBlockCap` is `1500`.
- The `ste` IDs are constants in `ste/rules.go` and `ste/warnings.go`, and `ste/postdeterminer.go` holds `IDPostdeterminer`. The warning set `ste.WarningIDs` holds `IDInstructionLength`, `IDPassive`, `IDNounCluster`, `IDTense`, `IDDictionary` and `IDParagraphLength`. `ste.AllIDs` is the error IDs plus `ste.WarningIDs`.
- The `yaml` IDs are in `workflow/workflow.go`, `workflow/concurrency.go`, `workflow/orgref.go`, `workflow/pushtags.go` and `workflow/envinline.go`. `workflow.WarningIDs` holds `IDTestInYAML` alone.
- `tombstones` wording rules are the distinct `id` attributes of `<pattern>` entries in `english/english.xml`. `rule_tombstones_patterns.go` registers one rule per ID, in sorted order, and skips an ID whose entry group is empty. The detection reports the rule when any phrase of the entry rewrites the text. The autofix applies every phrase of the entry. The cases are the worked examples the table carries.
- `tombstones.IDVolume` is `tombstones/comment-volume` and `tombstones.IDDeadReferent` derives from the tell `a name nothing in the repository defines`. `ruleID` lowercases the tell, drops a leading `a `, `an ` or `the `, replaces spaces with hyphens and prefixes `tombstones/`.
- `counts.ID` is `counts/inventory-count` and `counts.IDSection` is `counts/section-number`. `commentfix.ID`, `commentfix.IDLength` and `commentfix.IDTail` are the three `comments` IDs. `pins.ID` is `pins/download-version`. `english.IDCommaNever` is `english/comma-never`.
- `laziness.ID`, `blamelanguage.ID` and `askproperly.ID` are the message rules. `MessageIDs` (`message.go`) names them, because a closing message is never on disk.

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

The same file holds the registry tests:

- `TestRegistrationRefusesADetectionWithoutAnAutofix` and `TestRegistrationNamesTheMissingAutofix` register a probe with no `Autofix` and expect a panic that contains `no autofix`.
- `TestRegistrationRefusesARuleWithNoCase` expects a panic for a rule with no `Cases`.
- `TestEveryCategoryRuleIsRegistered` requires every ID `IDsFor(category)` holds for every `AllRules()` category to be registered.
- `TestEveryRegisteredRuleCarriesAnAutofix` lists any registered rule with a nil `Autofix`.
- `TestEveryReportableIDIsARegisteredRule` requires every ID in `ReportableIDs` to be registered.
- `TestAFindingFromNoRegisteredRulePanics` calls `Registered` on a finding under `probe/unregistered` and expects a panic.

## The repair guarantee

`repairable_test.go` holds the claim that every rule carries a repair:

- `TestEveryRuleCarriesARepair` requires `Repairable(id)` for every ID in `EveryID`.
- `TestARepairIsClaimedRuleByRule` asserts `Repairable` for `ste/semicolon`, `wrap/hard-wrap`, `yaml/comment-block`, `yaml/neutered-gate`, `ste/passive`, `tombstones/comment-volume` and `repo/near-duplicate`.
- `TestAStaleCountIsRepairableUnderEitherID` asserts `Repairable` for `ste.IDStaleCount` and `IDInventoryCount`, because a stale count is reported under the prose ID and repaired under the counts ID.
- `TestAnUnknownRuleIsNotRepairable` asserts `Repairable("ste/not-a-real-rule")` is false.
- `TestTheRuleSetIsNotEmpty` requires `AllIDs` and `EveryID` to be non-empty. The coverage test passes on rules and not on an empty walk.

`allfix_test.go` holds `TestFixLeavesNoErrorOnAnyTree`. It builds one tree of the hardest case of each error rule through `hardCorpus`:

- Fixtures in `testdata/allfix` map to paths by `corpusFiles`: `CLAUDE.md`, `README.md`, `package.json` and `ci.yml.in`, which lands at `.github/workflows/ci.yml`.
- `AGENTS.md` repeats a sentence until its text is longer than `CharBudget + 2000`. `CharBudget` is `40_000` (`rootfiles.go`). The file has no heading. The budget repair has no section to move.
- `README.md` gains a list item over `LongBlockCap` with a parenthesis that runs past the division target.
- `main.go` holds a comment block over the `14` line cap above code longer than the cap. Plus a separate paragraph that states a count, so `comments/number` runs too.

The test runs `CheckTreeWith` first. The test requires the corpus to hold a finding of each of these IDs: `ste/sentence-length`, `ste/semicolon`, `ste/contraction`, `ste/modal`, `wrap/hard-wrap`, `wrap/long-block`, `repo/budget`, `repo/package-scripts`, `repo/agents-file` and `yaml/push-tags`. This also covers `yaml/concurrency`, `yaml/all-builds-job`, `yaml/neutered-gate`, `yaml/comment-block`, `yaml/org-action-ref`, `pins/download-version`, `tombstones/comment-volume`, `comments/length` and `comments/number`. Then it runs `FixTreeWith` and requires `Unmet` to be empty and a second `CheckTreeWith` to hold no error. `errorLines` counts a finding that is not a warning, and every kept tombstone. The test also asserts specific repaired wording in `README.md`, and that `justfile` and `docs/agents-continued.md` exist.

## The Fix loop

`Fix(req)` in `fix.go` runs `fixAll`, then limits the result to the scope of the request. `fixAll` returns the text unchanged for an exempt file (`tombstones.Borrowed` or `commentfix.IsGenerated`). Otherwise it calls `fixText`, which does this:

- It chooses the file kind with `kindOf`: `fixer.Workflow` for a workflow, `fixer.Source` for a path that is not a document, and `fixer.Document` for the rest. That kind includs an empty path.
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

- `expect.Marker` is `slopfix-expect:`. A line carrying `slopfix-expect: "text"` states what slopfix turns that line into, as a Go-quoted string. An empty string `""` states that the repair deletes the line.
- The marker counts only behind a comment opener. The openers are `<!--`, `/*`, `//`, `--`, `#` and `;`, and the closers are `-->` and `*/`. A marker with no opener before it is text.
- A string that `strconv.Unquote` rejects is an error in `Annotations.Errors`: `line N: slopfix-expect: takes a Go-quoted string, got <raw>`.
- `Parse` returns `Stripped`, the text with every annotation cut out, which is what the rules judge. `Shift` maps a byte offset of the annotated text to the same place in `Stripped`.
- `Annotations.Check(repaired)` diffs `Stripped` against the repaired text by lines, with `difflib`. It fails a line that is annotated and unchanged, a line. That is changed and unannotated, and a line whose written text differs from the annotation.

`fixAll` applies the package. A file with any annotation, or any annotation error (`Annotations.Any`), is a fixture:

- The rules run on `Stripped`. A bounded scope is shifted with `Shift`.
- `Repair.Unmet` holds the result of `Check`.
- The returned `Text` is the original text, `Changed` is false, and the scope is the original scope. A fixture is never rewritten.

`UnmetError` carries the path and the unmet lines, and `FixFile` returns it for a file on disk. `expect_test.go` proves that the annotated file is left as it was. Those proves are that an annotation the repair breaks lands in `Unmet`, and that `FixFile` returns an `UnmetError` and leaves the file on disk unchanged.

## Hooks mapping

`hooks.go` holds `hooks`, the only mapping from a hook, a gate or a build phase to the rules it runs. `Hook` has `Name`, `Event`, `Runs`, `Summary`, `Only` and `Pending`. `Only` holds a category or a rule ID. An empty `Only` is the default set.

`Selects(hook)` resolves a hook to rule IDs. A pending hook selects nothing. An entry that names a category expands to every rule in it. An entry that is not a category is added as an ID, and an empty `Only` selects `AllIDs()`.

| Name | Event | Selection |
|---|---|---|
| `no-counts-in-docs` | `PreToolUse` | category `counts` |
| `no-tombstones` | `PreToolUse` | category `tombstones` |
| `common-checks` | `PreToolUse` | the default set, which is `AllIDs()` |
| `go-toolchain comments phase` | `build` | `comments/number`, `comments/tail`, `comments/length`, `ste/sentence-length` |
| `ci check` | `build` | category `repo` |
| `no-laziness` | `Stop` | `laziness/punt` |
| `no-blame-language` | `MessageDisplay` | `blame/deflection` |
| `ask-properly` | `MessageDisplay` | `ask/prose-decision` |
| `link-all-refs` | `MessageDisplay` | pending, selects nothing |

`hooks_test.go` holds the guarantee:

- `TestEveryRuleHasAHomeAndEveryHomeNamesARealRule` requires every non-pending hook to select a non-empty set. Test also requires every selected ID to be in `EveryRuleID`, and every rule in `EveryRuleID` to be selected by some hook. A pending hook must select nothing.
- `TestAnUnhomedRuleIsCaught` requires that `ste/not-a-real-rule` is in no hook's selection.
- `TestAHookIsFoundByName` checks `FindHook` for `no-counts-in-docs` and for an unknown name.
- `TestTheDefaultSetIsTheWholeCheckPath` requires `common-checks` to have an empty `Only` and to select exactly `AllIDs()`.

`AllIDs` (`slopfix.go`) is the set `CheckContent` reports: `workflow.AllIDs`, `ste.AllIDs`, `pins.AllIDs`, `wrap/hard-wrap`, `wrap/long-block`, the three `comments` IDs and `english.AllIDs`. It holds no repository rule and no message rule. Those reach a hook through the `ci check` entry and the message entries.
