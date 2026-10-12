# ci-action

slopfix ships a composite GitHub Action at the repository root (`action.yml`). Its own workflow (`.github/workflows/ci.yml`) builds the binary, checks the tree, runs the ratchet, runs the action. And on the default branch asks cc-marketplace to package the build.

## The action

`action.yml` has the name `slopfix` and the description `Download slopfix and check the whole checkout with every rule`. It is a composite action (`runs.using: composite`) of multiple steps, in this order.

| Step id | Runs | Condition |
|---|---|---|
| `claim` | `wow-look-at-my/actions@run-once#latest` with `name: slopfix-check` | always |
| `download` | `wow-look-at-my/buildhost/.github/actions/buildhost-download@master` with `project: slopfix` | `steps.claim.outputs.first != 'false'` |
| `check` | the downloaded binary, `check .` | `steps.claim.outputs.first != 'false'` |

The step goes after the checkout, because `check .` reads the working directory.

### The claim

Several org actions call this action, so one workflow run can reach it from many jobs. The check reads the same tree in every job, so one job of the run does it. The `claim` step calls the `run-once` action with the name `slopfix-check`. A job that wins the claim runs the download and the check. A job that loses it gets `first` equal to `false`, and the `download` and `check` steps skip.

`TestActionClaimsTheCheckOncePerRun` in `action_test.go` holds this:

- the first step has the id `claim`
- its `uses` is exactly `wow-look-at-my/actions@run-once#latest`
- its `with.name` is exactly `slopfix-check`
- the steps with the ids `download` and `check` both exist, and each `if` contains `steps.claim.outputs.first != 'false'`

### The download

The `download` step uses the buildhost action `buildhost-download` at `@master`, with `project: slopfix`. It publishes the path of the binary as `steps.download.outputs.path`. The binary is the published build of the default branch from buildhost. The step reads no input of this action.

### The check

The `check` step has the id `check` and runs in `bash` with `GITHUB_TOKEN` set to `${{ github.token }}`. The check reads the repository from the API to tell whether it is a fork, and a private repository needs the token.

The script has a couple of lines:

```
if [ "$RUNNER_OS" = Windows ]; then exec "${{ steps.download.outputs.path }}" check .; fi
exec sh "${{ steps.download.outputs.path }}" check .
```

On Windows the binary runs directly. On every other runner it runs through `sh`, because a binfmt handler on an ubuntu runner refuses a direct exec of the APE binary. `TestActionRunsTheBinaryThroughShOnUnix` requires the `check` step's `run` to contain `sh "${{ steps.download.outputs.path }}" check .`.

The command is always `check .` with every rule. The action never repairs. A job that repairs its own checkout and then passes enforced nothing.

### No inputs

The action declares no `inputs` key. A path list, a rule list or a raw command line will let a caller set the gate to nothing. `TestActionHasNoInputThatNarrowsTheCheck` parses `action.yml` and fails the build when `inputs` holds any name. The file carries a comment that says the same.

## The workflow

`.github/workflows/ci.yml` is named `CI`.

Triggers: `push` with `branches: ['**']`, and `workflow_dispatch`.

Concurrency:

- `group` is `gha_${{ github.repository }}_${{ github.workflow }}_${{ github.ref != 'refs/heads/master' && github.ref || github.run_id }}`. A push to `master` gets a group of its own by run id, and any other branch shares one group per ref.
- `cancel-in-progress` is `${{ github.ref != 'refs/heads/master' }}`. A new push cancels the branch's running workflow, and a `master` run is never cancelled.

Permissions: `id-token: write`, `contents: write`, `actions: read`, `checks: read`, `deployments: write` and `artifact-metadata: write`. These are the grants go-toolchain needs for its release step.

The workflow has one job, `build`, on `ubuntu-latest`. It must not be named `all-builds`, because `yaml/all-builds-job` rejects that name. The steps run in this order:

1. `actions/checkout@v4` with `submodules: recursive`. The checkout holds the `spec` submodule and the grammar submodules.
2. `Install the dats sandbox backend`. It runs `apt-get update`, `apt-get install -y bubblewrap`, and `sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`. go-toolchain runs the `dats/` suites after the build, and `dats` needs a sandbox backend. Otherwise, the suites run on the runner itself.
3. `wow-look-at-my/go-toolchain@master` with `generate: 165003bec91c`. The input approves the `//go:generate` directives, and editing a single directive fails the build with the new value. The step builds `build/slopfix`, runs the tests with the coverage gate, and runs the `dats/` suites.
4. `./build/slopfix check .` with `GITHUB_TOKEN` set to `${{ github.token }}`. The fork check reads the repository from the API, and an anonymous call shares the runner IP's rate limit.
5. `./build/slopfix ratchet`. The ratchet judges this branch by the default branch's guarantee. It reads the default branch's `.github/ratchet`. A branch cannot change what judges it. [ratchet.md](ratchet.md) holds the detail.
6. `uses: ./` with `permission: contents`. This runs the action at the root, so a break in the action fails its own repository first. The action takes no input, so `permission: contents` is not read by it.
7. `Ship this build in the marketplace`, described below.

A step that fails ends the job, and a failed `check .` or `ratchet` therefore stops the ship step.

## Shipping to cc-marketplace

cc-marketplace packages this binary inside its `slopfix` plugin. A publish of this repository therefore reaches no user until that plugin is packaged again, so each master build asks cc-marketplace to do it.

The last step is:

```
- name: Ship this build in the marketplace
  if: github.ref == 'refs/heads/master'
  uses: wow-look-at-my/cc-marketplace/.github/actions/ship@master
  with:
    plugins: slopfix
```

- The step runs only on `refs/heads/master`. A branch build ships nothing.
- The step uses the `ship` action of cc-marketplace at `@master`, and passes `plugins: slopfix`. The action itself lives in the cc-marketplace repository, and this repository holds no other part of the dispatch.
- The workflow file names no token, secret, `release.yml` dispatch or `publish` flag. The step passes only the plugin name. `AGENTS.md` describes a dispatch of `release.yml` with `publish: true` using the secret `CC_MARKETPLACE_DISPATCH_TOKEN`. That is a description of the `ship` action's behavior. The spec does not restate it because the workflow here does not show it. No `CC_CARRY` name appears in the repository.

## Files

| Path | Role |
|---|---|
| `action.yml` | the composite action: claim, download, check |
| `action_test.go` | the three tests that hold the action: no inputs, `sh` on Unix, one claim per run |
| `.github/workflows/ci.yml` | the build, the tree check, the ratchet, the action run and the marketplace ship |
| `.github/ratchet` | the ratchet entry point: `go run ./cmd/ratchet` |

