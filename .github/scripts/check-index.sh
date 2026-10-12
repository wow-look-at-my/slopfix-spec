#!/opt/homebrew/bin/bash
set -euo pipefail

# Fails when a spec file is missing from the README index, or the index links a file that does not exist.
specs=$(find . -maxdepth 1 -name '*.md' ! -name README.md -printf '%f\n' | sort)
linked=$(grep -oE '\]\([A-Za-z0-9._-]+\.md\)' README.md | sed -E 's/^\]\((.*)\)$/\1/' | sort -u)

unlisted=$(comm -23 <(printf '%s\n' "$specs") <(printf '%s\n' "$linked"))
dangling=$(comm -13 <(printf '%s\n' "$specs") <(printf '%s\n' "$linked"))

if [ -n "$unlisted" ]; then
	printf 'README.md does not link:\n%s\n' "$unlisted" >&2
fi
if [ -n "$dangling" ]; then
	printf 'README.md links a missing file:\n%s\n' "$dangling" >&2
fi
if [ -n "$unlisted$dangling" ]; then
	exit 1
fi
