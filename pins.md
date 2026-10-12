# pins: a download URL that names a release

`pins/download-version` (`pins.ID`) rejects a `dl.pazer.build` URL that carries a `v` query parameter. The rule is one `RuleSpec` in `rule_pins_downloadversion.go`, with category `RulePins`. Its code lives in the `pins` package, in `pins/pins.go`.

A `dl.pazer.build` URL with no `v` serves the newest published build on the default branch of the project. A URL with `v` names one release. It breaks when that release is gone. The finding is an error. It has a repair.

## Detection

`pins.Check` reads text and answers one finding per pinned URL.

1. `scan` splits the text on newlines and runs `downloadURL` over each line. The pattern is `dl\.pazer\.build/` followed by any run of these: a `${{ ... }}` expression of any content up to the first `}`, or a character that is not whitespace, a double or single quote, a backtick, `<`, `>`, `(`, `)`, `[`, `]` or a backslash. A URL ends at the first such character. Trailing punctuation such as a period belongs to the match.
2. For each match, `scan` unescapes HTML entities with `html.UnescapeString`, prefixes `https://`, and parses the result with `net/url`. A match that does not parse is skipped.
3. A match is pinned when `Query().Has("v")` is true. The key must be exactly `v`. A key such as `vv` or `version_hint` does not count, and neither does `v=1` in the fragment. A `v` with no value counts.

The URL is read in every kind of file. A document, a source file and a workflow all go through `pins.CheckPath`, which `CheckContent` in `slopfix.go` calls for every path. `fix.go` calls it again so that `Fix` reports a URL it did not repair. Code strings count, and so does text in a comment.

The finding carries these fields.

- `Line` is the line of the URL, counted from one.
- `ID` is `pins/download-version`.
- `Rule` is `a dl.pazer.build URL pins a release with v=`.
- `Detail` is the matched text, starting at `dl.pazer.build/`.
- `Fix` is `Drop the v parameter. The URL then serves the newest build on the default branch, and branch= names another branch`.

Every pinned URL on a line is its own finding.

## What is not flagged

- A URL on any other host, such as `static.pazer.build`.
- A `dl.pazer.build` URL with query keys other than `v`, or with a `branch` key.
- A `v` that sits only in the fragment.
- Text such as `v=10` with no `dl.pazer.build` URL.
- A test file. `pins.IsTest` is true for a path. This holds with a `__tests__` or `testdata` directory, or whose base name matches `_test.` plus an extension. `.test.` or `.spec.` plus an extension, or `test_` plus a name ending `.py`. A test asserts the exact URL that the code under test builds. `CheckPath` answers nothing for such a path. The repair skips it too.

An empty path is not a test.

## Repair

`pins.Edits` answers one edit per pinned URL that `unpinned` can rewrite. The edit replaces the matched bytes. It records the old text in `Cut`.

`unpinned` has routes.

- The standard route builds the query with `net/url`. It deletes the `v` key and every value of it, and writes the query back with `Encode`. `Encode` sorts the keys by name, so the other parameters come out in key order. The scheme prefix is trimmed again. The fragment stays.
- The textual route runs when the raw query holds `$`, `{` or `}`, or the raw text holds `&amp;`. `Encode` will escape a template such as `${OS}`. It will write `&` where the text held `&amp;`. `textually` therefore cuts the `v` field from the raw text with `querySeparator`, which matches `&amp;` or `&`. It keeps every other byte and the separators as written. A field is the `v` field when its key, unescaped, is `v`. If no `?` is in the raw URL, no edit is made. If nothing changes, no edit is made.

When the last parameter goes, the `?` goes too. A URL such as `https://dl.pazer.build/a#top` becomes `https://dl.pazer.build/a#top`.

Worked examples of the standard route, from `pins/testdata/repair.urls`: a query with `v`, `os` and `arch` becomes the query `arch` then `os`. A query with multiple `v` keys loses both.

Worked examples of the textual route, from `pins/testdata/mangle.urls`: a URL with `${OS}`, `${V}` and `${ARCH}` keeps the order of the remaining fields. An HTML-escaped separator survives. A URL whose `v` value is a workflow expression loses the whole query.

## The gate

`pins.Gate` admits only the edits that `Edits` derives from the same source. An edit passes when its start, end and text equal one of those edits. Any other edit is refused with the reason `it is not the rewrite of a dl.pazer.build URL without its v parameter`. After the splice the count of `dl.pazer.build` URLs that `scan` finds must equal the count before. The ordinary comment of the source gate admits edits only, so this gate stands beside it.

## Registration

The fixer label `pins/download-version`, family `pins`, rule `pins/download-version`, and `Place` `1000`. It reads `fixer.Source`, `fixer.Document` and `fixer.Workflow` files, so it runs on every kind of file. It calls `ApplyThrough(Gate, Edits(text))`, and it skips a test path.

`pins.AllIDs` is the set of the rule id. `AllIDs()` in `slopfix.go` unions it with the workflow and STE ids.

## Tests

The fixtures live in `pins/testdata`, which the walk skips, so this repository's own check does not report them. `detect.urls` has one pinned URL per line. `twice.urls` has two on one line. `repair.urls` and `mangle.urls` hold an input and its repair on each line, split by a tab. `fetch.sh` and `fetch.fixed.sh` hold a whole script and its repair. The test `TestGateRefusesAnyOtherEdit` shows that an edit outside the URL rewrite is refused.
