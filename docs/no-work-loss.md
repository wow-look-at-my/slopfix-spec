# no-work-loss: the destruction and provenance guard

`no-work-loss` asks questions of one parsed command. Destruction: does it destroy content that exists only in the working tree? Provenance: does it change file content without Write, Edit or NotebookEdit?

## Destruction

A command the agent runs lost the invariant: content that exists only in the working tree must never. Committed work stays in the reflog. A history rewrite is thus out of scope.

The hook preserves, then allows. It commits the at-risk paths onto the CURRENT BRANCH, where the log and the next push already look. A hidden ref is one nobody reviews.

- Every step uses a throwaway `GIT_INDEX_FILE`, seeded by `git read-tree HEAD`. The real index and the working tree never move.
- `stagedTree` commits the index entries first. `git add --force` then commits the disk content. A tree equal to its parent is dropped. No commit is therefore empty.
- `git update-ref HEAD` advances the branch. `git reset -q <commit> -- <paths>` refreshes the real index for those paths. Git hooks are off during preservation.
- A best-effort `git push --no-verify origin HEAD` follows. A push failure still allows. The report names where the content sits.
- A failed `add`, `write-tree`, `commit-tree` or `update-ref` denies. Preservation that did not happen must never read as success.

A stash entry and a ref-destroying command still deny outright. A ref under `refs/no-work-loss/` is the only copy of its content. Deleting or force-pushing it is always refused.

The incident: `git checkout master` carries a dirty tree across. `git reset --hard origin/master` then destroys it with no reflog entry. A guard on `reset --hard` alone misses the setup step.

Each verb is checked against the classes it reaches. A single dirty bit gives false positives that get a guard uninstalled.

| Command | tracked edits | untracked | ignored | stash |
|---|---|---|---|---|
| `reset --hard` | destroys | spares | spares | spares |
| `clean -fd` | spares | destroys | spares | spares |
| `clean -fdx` | spares | destroys | destroys | spares |
| `stash drop` | spares | spares | spares | destroys |
| `checkout <ref>` | destroys | spares | spares | spares |

A submodule at a commit other than its gitlink is not a tracked edit. That commit stays in the history of the submodule. The probe reads `status --porcelain=v2` and drops a submodule entry that has no modified and no untracked content.

A ref-destroying verb asks whether the content exists anywhere else:

| Verb | What must survive | How it is answered |
|---|---|---|
| `branch -D` / `-M`, `update-ref -d`, `push --delete` | the tip | another ref contains it |
| `push --force` / `+refspec` | the remote-tracking tip | an ancestor of the push, or in another ref |
| `filter-branch` | all of HEAD | `rev-list --count HEAD --not --remotes` is `0` |
| `reflog expire` / `delete` | nothing reflog-only | `fsck --unreachable --no-reflogs` finds no commit |
| `worktree remove --force` | its edits | its `status --porcelain` is empty |

- Containment uses `for-each-ref --contains`. The `--exclude` flag with `--branches` takes the name without `refs/heads/`. A full refname thus excludes nothing.
- `refs/remotes/<remote>/HEAD` aliases the overwritten branch. The check filters it out.
- `push --mirror` is always refused. A push with no local remote-tracking ref denies and names `git fetch`.

Allowed on purpose: `checkout -b`, `switch -c`, `stash pop`, `stash apply`, `commit`, `add`, `restore --staged`, unknown verbs, appends, and anything outside a repository. For unpushed commits, `stash push` and `worktree add`, see Found work.

## Found work

The invariant: work the session finds that exists only on this machine is on a remote before the session moves on. Found work is never routed around, set aside or left for later. The guard refuses nothing here. It commits and pushes the found work itself, then lets the command run.

### What is found work

A repository holds found work when any of these is true, read with `status --porcelain=v2 --branch` and `rev-list`:

- a tracked file differs from the index or the index from HEAD.
- an untracked file that git does not ignore exists.
- a submodule, at any depth, holds found work of its own.
- the branch has commits that no remote-tracking ref contains.

A linked worktree is a repository of its own here. Its found work is judged in it, not in the checkout it was added from.

### Which repositories the guard judges

The guard records each repository the session touches, the first time it is touched, in a state file for that session:

- PreToolUse on Bash. The repository of the working directory, of each `cd`, `git -C`, `--work-tree` and `GIT_DIR`, and of each path operand, resolved the same way Detection resolves them.
- PostToolUse on Read, Edit, Write, MultiEdit, NotebookEdit, Grep and Glob: the repository that holds each path the tool named.

Each recorded repository is probed on every PreToolUse and Stop. Its submodules are probed with it. No environment variable, flag, file or path turns the recording or the probe off.

### When it commits and pushes

The guard commits and pushes the found work of every recorded repository at these points, before the hook answers:

- before `git worktree add` from that repository, because a new worktree beside the work sets it aside.
- before `git stash` in any form that stores, because a stash hides the work. The stash then runs on a clean tree and stores nothing.
- before `git clone` of that repository or its remote, and before `cp -r`, `rsync` or `ditto` of its directory, because a fresh copy leaves the work behind.
- at Stop, for every recorded repository, because a turn that ends leaves the work where it found it.
- at PostToolUse on Bash, for a repository whose found work the command's output showed, such as a `git status` that listed it. Seeing the work finds it.

The commit and push use the Destruction machinery. This covers a throwaway `GIT_INDEX_FILE`, every path at risk committed onto the current branch, `update-ref`, a refresh of the real index, then `git push`. Git hooks run on the push, so the pre-push checks still judge it. A submodule is committed and pushed before its parent, and the parent's commit then records the pushed gitlink. On the remote's default branch the guard first creates a branch named for the session and commits there. This is because the default branch takes no direct push.

A branch with no upstream is pushed with one set.

The work found is committed whoever wrote it: another session, an agent, a hook, or this session. The commit message names the guard and the paths.

When a commit or push cannot complete (no remote, a rejected push, a git error), the hook answers with the reason and the exact commands that finish the job. That commit is for the agent to run next. It never suggests a stash, a worktree, a reset, a clone or a discard. At Stop that answer refuses the stop, because the work is not yet on a remote.

### Worktrees keep working

The guard must not cost a working worktree flow:

- `git worktree add` from a repository that holds no found work passes unchanged, at any path and with any branch. From a repository that holds found work, it runs after the commit and push above.
- Before a `git worktree add` whose path lies inside the repository, such as `<repo>/.claude/worktrees/<branch>`, the guard appends the path's top directory pattern to `$(git rev-parse --git-common-dir)/info/exclude`. This happens when no line there already ignores it. For that layout the pattern is `/.claude/worktrees/`. A worktree inside its repository is therefore never untracked content of the repository, and a `git add .` never records it.
- The guard judges a worktree as its own repository: its work is committed and pushed in it, on its own branch.

### The embedded repository

A `git add` that will record a gitlink for a path `.gitmodules` does not list is rewritten. The guard adds the path to `info/exclude`. The guard drops it from the add, then commits and pushes the embedded repository's own found work in that repository. The parent never records a gitlink nobody declared, and the work inside still reaches a remote.

## Detection

- Chains, pipes, subshells, bodies and command substitutions are each evaluated.
- A `cd` carries forward across `&&`, `||`, `;` and brace blocks. A pipe stage, a subshell and a conditional body get a copy. `git -C` and `--work-tree` apply too.
- Wrappers resolve to their program, with value-taking flags understood: `env`, `sudo`, `doas`, `command`, `builtin`, `exec`, `nohup`, `nice`, `ionice`, `setsid`, `stdbuf`, `timeout`, `xargs`. A leading `\` and an absolute path.
- Short flags unbundle. A `--flag=value` registers as `--flag`.
- Git aliases resolve from `git config`, including `!shell` aliases. Self-reference stops at depth `3`.

Ambiguity denies. That covers an unparseable command with a destructive verb, an operand that is not static (`rm $TARGET`, `cd -`), and a relocated `GIT_DIR`. A script FILE that the walk follows is judged on its static paths only.

A device target such as `/dev/null`, and a descriptor other than stdout, cannot empty a file. The provenance half still judges every descriptor. It thus refuses `echo x 2> tracked.go`.

A destructive verb fails closed on a panic, a git error or the `3`-second git timeout. Everything else fails open. A killed binary lets the command run, because a hook cannot make itself mandatory. `clean-bash` rewrites `rm`. This hook sees the original command. Where both fire, the deny wins.

## Provenance

Any change to file content in the working tree goes through Write, Edit or NotebookEdit. The verdict follows from the shape of the write:

| Shape | Example | Denies when |
|---|---|---|
| named path | `> x.go`, `cp a x.go` | the path is in a guarded root and not under a build directory |
| whole directory | `patch`, `tar -x`, `git apply` | the directory holds or sits in a guarded root |
| opaque | `node -e`, a GitHub API commit | always |

- Routes include editors, `busybox` applets, every file redirect, `tee`, `dd of=`, `truncate -s`, `sponge`, `xxd -r`, `sort -o`, `split`, compressors without `-c`, `zip`, `docker cp`, `yq -i` and `ln`.
- `ln -s` passes when its target is a relative path to a file in the same tree, outside a build directory. No edit tool makes a symlink, and that link adds no text. A target that leaves the tree, or a link through a link that leaves it, is still a write. `ln -f` over a file with an edit keeps the edit first, like `mv`.
- `cp`, `mv`, `install`, `rsync` and `scp` test the source side. A plain `mv old.go new.go` thus passes.
- `git apply`, `git am` and `rebase` are refused. `git merge`, `git pull`, `git cherry-pick` and `git revert` pass, because git already holds what they land. `git commit-tree` passes too: it wraps a tree the store already holds and changes no file.
- Indirection is followed: `sh -c`, aliases, script files, `find -exec`, functions and wrappers.
- `sh tool` on an APE binary is a call of `tool`, not a script. The walk judges its arguments and never parses the machine code.
- A long in-place flag (`--in-place`, `--write`) counts for any program. `allowedFormatter` lists. The tools that rewrite by design. `jq` has an empty flag set on purpose.
- A subagent spawn with a tool grant or a permissive `permissionMode` is refused. The live settings files are refused to every tool.
- The session scratchpad is the temporary directory that does not deny.

A Write over a path that git holds and the disk does not is refused, however the path was emptied. A deletion committed on the branch, or in the last `10` commits, holds the path too. The hook restores the file with `git restore --worktree` first, from the index, HEAD or the parent of the deleting commit. A file in the recycle bin comes back the same way, through `recycler restore` with the newest item's ID. No route lets Write replace a file that existed. The refusal names the Edit tool.

It prices the evasion in Claude tokens from `transcript_path`. The price is every tool call that names the file since its last Read or Edit, plus this Write. The changed lines are subtracted. `echo x > new-file` is refused too, because creating a file is what Write is for.

## See also

- [clean-bash](clean-bash.md) for the guard that rewrites `rm`
- [hook-guards](hook-guards.md) for the guard table
- [auto-allow](auto-allow.md) for the guard after this on PreToolUse
