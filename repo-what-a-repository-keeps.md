# repo: what a repository keeps

These rules judge the tree. Only a walk whose root holds `.git` reaches them. `check` reports them. `fix` applies them.

Both rules fetch a remote schema, once for each walk, and an XSD's imports with it. A schema that does not load, by a network error or any status but OK, is a finding. It is never a pass. The JSON Schema meta-schemas need no fetch, because the validator carries them.

The document rules walk what the other repository rules walk, so `testdata`, `node_modules`, a submodule and a nested clone stay out. `repo/binary` reads every tracked file, the large ones included.

A body that `AGENTS.md` already holds is not appended again. The import line is never copied into the file it imports. A `CLAUDE.md` that is a symlink stays.

Every other markdown file is left alone. The budget covers only the files that every request loads.
