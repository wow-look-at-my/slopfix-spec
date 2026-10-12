# slopfix

slopfix is the single filter every document passes through. `check` reports what every rule rejects in a file or a tree. `fix` repairs what a rewrite can repair, and reports the rest. The hooks and CI both shell out to the same binary, so all three agree.

This repository holds the specification. Each page states one rule family, one package, or one part of the pipeline.

## The pages

| Page | Covers |
|---|---|
| [rules](docs/rules.md) | the registry, the rule table, the common test and the hooks mapping |
| [commands](docs/commands.md) | the `slopfix` commands and `--only` |
| [ste-simplified-technical-english](docs/ste-simplified-technical-english.md) | the Simplified Technical English rules |
| [counts](docs/counts.md) | a stated count and a cited section number in a document |
| [inventory-list](docs/inventory-list.md) | an enumeration of what the code holds |
| [tombstones](docs/tombstones.md) | a comment about a state the code has left |
| [comments](docs/comments.md) | the comment rules of a source file |
| [yaml-workflow-and-action-manifest-rules](docs/yaml-workflow-and-action-manifest-rules.md) | the workflow and action manifest rules |
| [english](docs/english.md) | `english/comma-never` and the prose table |
| [pins](docs/pins.md) | a download URL that names a release |
| [repo-what-a-repository-keeps](docs/repo-what-a-repository-keeps.md) | the rules that judge the tree |
| [markdown](docs/markdown.md) | the document model and the wrap rules |
| [cardinal](docs/cardinal.md) | is this number a count |
| [syntax](docs/syntax.md) | the sentence parser |
| [edit-the-only-way-a-repair-writes](docs/edit-the-only-way-a-repair-writes.md) | the gates a repair writes through |
| [hook-guards](docs/hook-guards.md) | the `slopfix hook` guards |
| [clean-bash](docs/clean-bash.md) | the Bash rewriter |
| [auto-allow](docs/auto-allow.md) | the permission table |
| [no-work-loss](docs/no-work-loss.md) | the destruction and provenance guard |
| [message-rules](docs/message-rules.md) | the rules that judge a closing message |
| [fork-scope](docs/fork-scope.md) | a fork is checked on its own lines |
| [ratchet](docs/ratchet.md) | the default branch judges a branch |
| [ci-action](docs/ci-action.md) | the composite action and the CI workflow |

## The rule registry

[rules](docs/rules.md) is the source of truth for every rule ID and its severity. A detection reaches a reader only with the repair that answers it and the worked case that proves both. The registry refuses to start a binary that holds a rule without all three.

## How a repair writes

A repair never returns a rewritten copy of a file. It returns byte ranges with replacement text, and a gate checks each before it lands. [edit](docs/edit-the-only-way-a-repair-writes.md) holds the gate contract.

## Reading the pages

A rule ID is the name a report prints, such as `counts/inventory-count`. A threshold is a named constant in the code, such as `LongBlockCap`, and the page carries its value. A page names the source files it documents in a table where the code lives.
