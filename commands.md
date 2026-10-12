# Commands

A kind of check is a rule category or a hook guard, not a command of its own.

## Selecting rules with --only

`--only` takes a comma-separated list. An entry is a category, or a rule ID inside a category. A rule ID is the name the report prints beside a finding, the way a compiler names a warning.

```sh
slopfix fix --only counts            # every rule in the counts category
slopfix fix --only ste/semicolon     # that rule alone
slopfix fix --only tombstones,wrap   # two categories
slopfix fix --only ste/nosuch        # an error that names the rules ste holds
```

A rule ID turns its category on. An unknown name is an error, because a run that applies nothing reads as a clean file. There is no `--exclude`. An exemption that a caller writes is one that a caller sets to everything.

A word repair and the wrap join share a pass. A rule reads a paragraph as a sentence stream. A hand wrap hides half of it. So an `ste` rule also joins the paragraph it repairs.

## Scoping a repair to a changed line

A repair usually runs over a whole file, which in a fork cuts the parent's comments too. `--staged` and `--diff REV` scope the run to the lines the change itself introduced. The way the per-edit write hook already scopes a repair to the span an edit writes.

```sh
slopfix fix --staged                  # repair the lines this commit will add
slopfix fix --diff origin/master .    # repair the lines this branch adds
slopfix check --staged .              # fail only on a finding this commit introduces
```

The line set comes from `git diff -U0`. `--staged` runs it with `--cached`. The set is the index against HEAD. `--diff REV` runs it against `REV`. The set is the work tree against that revision. Each `-U0` hunk names the new-side range it added or changed.

Those line numbers are the selected set for that file. A file the diff created counts whole. A finding whose line is not in the set is neither reported nor repaired.

With a selector, `check` exits nonzero when a selected finding remains and zero otherwise, which is what a pre-commit hook reads. A selector needs a file or a directory argument. It cannot be combined with `--message`. A file outside the fork scope stays untouched, because the fork scope still applies on top of the selector.

## lsp

`slopfix lsp [--max-per-file N]` speaks the Language Server Protocol on stdio with full document sync. Every diagnostic is an error. The `yaml` and `ste` families rank first and `wrap` ranks last. Past the cap, the last diagnostic sent counts the rest.

`--trace` on any command prints a timing breakdown by phase.

## hook

`slopfix hook` reads any hook payload on stdin. The event on the payload picks the guards, and every guard that serves it runs. `--only` names guards, or rule categories and IDs for the write guard. `cmd/guards.go` holds the table, in run order.

- On PreToolUse the first refusal is the answer. A rewrite of the tool input reaches every guard after it, so no guard judges a command that will not run.
- On Stop, every refusal joins into one exit 2 with every reason. On MessageDisplay, the `link-refs` rewrite is the base and each note follows it.
- A refusal is an exit code. The process exits with it.
- The `write` guard repairs the text a Write, Edit or MultiEdit adds and lets the write through. It flags what the repair did not reach.
- The write guard repairs an Edit where it lands in the file. A line inside a fence therefore stays code. A `Scope` holds every rewrite inside the edit's own bytes, so a repair the file needs elsewhere never lands. The hook reports those findings instead.
- The hook prints nothing and exits 0 for anything it does not judge. That covers a bad payload, an event no guard serves, and clean text.
