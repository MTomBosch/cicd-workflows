# Scripts

This folder contains two companion scripts.

## `run-release-please.sh`

Orchestrates Release Please for individual **workflow files** and **composite actions** as
independent versioned components. Designed to live in its own repository and to operate on a
**separate target repository** checked out locally, pointed at with `--working-dir`.

## `gen-release-please-workflow-config.sh`

Generates the release-please config and manifest files for a **single workflow component**.
Called by `run-release-please.sh` in `generate_workflow_config` mode and also during `pr` mode
validation, but can be invoked directly.

---

## Two-Repository Setup

```
┌─────────────────────────────────────────────┐        ┌─────────────────────────────────────────┐
│  Script repo                                │        │  Target repo  (--working-dir)            │
│  .github/release-please-script/             │        │                                          │
│    run-release-please.sh           ─────────┼───────▶│  .github/workflows/*.yml                 │
│    gen-release-please-workflow-config.sh ───┘        │  .github/release-please/                 │
│    README.md                                │        │    actions-config.json                   │
└─────────────────────────────────────────────┘        │    actions-manifest.json                 │
                                                       │    workflow-config/                      │
                                                       │      <workflow>-config.json              │
                                                       │      <workflow>-manifest.json            │
                                                       └─────────────────────────────────────────┘
```

The script reads from and writes to the target repo's working tree.
`run-release-please.sh` calls the Release Please CLI (`npx release-please`) pointing it at the
target repo on GitHub. `gen-release-please-workflow-config.sh` only reads and writes local files
and does not require a GitHub token.

---

## What the Script Does

### For workflow components

Each `*.yml` file under `.github/workflows/` in the target repo can be released as an
independent component with its own semantic version, tag, changelog, and GitHub release.

Because all workflow files share the same directory, a single static Release Please
config cannot model per-file release streams cleanly. The script instead generates
per-workflow `<workflow>-config.json` and `<workflow>-manifest.json` files in the target
repo and passes them to Release Please with `--local` mode so they are resolved from disk.

### For composite action components

Composite actions are released using two static files that must already exist in the
target repo. No files are generated at release time; Release Please reads and updates
them directly.

---

## Modes

### `generate_workflow_config`

Delegates to `gen-release-please-workflow-config.sh` once per component. Generates (or
regenerates) the per-workflow config and manifest files in the target repo.
**Run this before `pr` or `release` for any new or changed workflow.**

- Uses the names given via `--components`.
- For each workflow, `gen-release-please-workflow-config.sh` writes:
  - `<release-please-config-root>/workflow-config/<workflow>-config.json` — always overwritten;
    the `initial-version` field is preserved from the previous file if one already exists.
  - `<release-please-config-root>/workflow-config/<workflow>-manifest.json` — created once with
    `initial-version` as the starting version; left unchanged on subsequent runs.
- Creates `<working-dir>/.github/workflows/<workflow>_changelog.md` if absent.
- Does **not** call Release Please and requires no GitHub token.

### `pr`

Creates or updates a release pull request for each selected component.

- For workflows: validates that the on-disk config file is up to date with the current
  repository content (exits with code 8 if it has drifted), then calls
  `release-please release-pr`.
- For actions: calls `release-please release-pr` using the static `actions-config.json`
  and `actions-manifest.json` files.

### `release`

Creates a GitHub release (tag + release notes) for each selected component after its
release PR has been merged. Calls `release-please github-release`.

---

## Target Repository Requirements

The script expects the following structure in the target repo (paths relative to `--working-dir`):

### Always required

| Path    | Description                                                                                                                                      |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `.git/` | The target directory must be a Git repository with a configured `origin` remote pointing at GitHub (unless `--repo-url` is provided explicitly). |

### For workflow releases (`pr` / `release` modes)

| Path                                                                    | Description                                                                                                      |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `.github/workflows/<workflow>.yml`                                      | The workflow file being released.                                                                                |
| `<release-please-config-root>/workflow-config/<workflow>-config.json`   | Per-workflow Release Please configuration. Generated by `generate_workflow_config` mode.                         |
| `<release-please-config-root>/workflow-config/<workflow>-manifest.json` | Per-workflow Release Please manifest tracking the current version. Generated by `generate_workflow_config` mode. |
| `.github/workflows/<workflow>_changelog.md`                             | Changelog file for the workflow. Auto-created by `generate_workflow_config` if absent.                           |

### For workflow config generation (`generate_workflow_config` mode)

| Path                                                                  | Description                                                                             |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `.github/workflows/*.yml` / `*.yaml`                                  | Workflow files to generate config for (specified via `--components`).                   |
| `<release-please-config-root>/workflow-config/<workflow>-config.json` | Optional. If present, its `initial-version` value is preserved in the regenerated file. |

### For action releases (`pr` / `release` modes)

| Path                                                 | Description                                                                                             |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `<actions-root>/<action-name>/`                      | The composite action directory. Must exist for the action to be recognised.                             |
| `<release-please-config-root>/actions-config.json`   | Static Release Please configuration for all composite actions. Manually maintained.                     |
| `<release-please-config-root>/actions-manifest.json` | Shared Release Please manifest for all composite actions. Updated by Release Please after each release. |

Default values: `<actions-root>` = `.github/actions`, `<release-please-config-root>` = `.github/release-please`.

---

## CLI Reference

```
run-release-please.sh --mode <mode> --components <name1,name2,...> [options]
```

| Option                                | Description                                                                                                    | Default                                                      |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `--mode <mode>`                       | **Required.** One of: `pr`, `release`, `generate_workflow_config`.                                             | —                                                            |
| `--components <list>`                 | Comma-separated component names (workflows and/or actions). Required.                                          | —                                                            |
| `--repo-url <owner/repo>`             | GitHub repository identifier for the target repo.                                                              | inferred from `origin` remote                                |
| `--target-branch <branch>`            | Target branch for PRs and releases.                                                                            | inferred from current branch via `git branch --show-current` |
| `--token <token>`                     | GitHub token for Release Please API calls.                                                                     | `$RELEASE_PLEASE_TOKEN` or `$GITHUB_TOKEN`                   |
| `--release-please-config-root <path>` | Folder inside the target repo containing action config/manifest files and the `workflow-config/` subdirectory. | `.github/release-please`                                     |
| `--actions-root <path>`               | Root folder for composite action directories inside the target repo.                                           | `.github/actions`                                            |
| `--dry-run`                           | Generate configs and validate, but do not create or update PRs or releases.                                    | false                                                        |
| `--help`                              | Print usage and exit.                                                                                          | —                                                            |

### Component detection (`run-release-please.sh`)

- **Workflow**: a `<workflow>-config.json` file exists under `<release-please-config-root>/workflow-config/`.
- **Action**: a directory `<actions-root>/<name>/` exists AND `<release-please-config-root>/actions-manifest.json` is present.
- **Unknown** (exit 5): neither condition is met.

---

## `gen-release-please-workflow-config.sh` CLI Reference

```
gen-release-please-workflow-config.sh --workflow <name> [options]
```

| Option                                | Description                                                                                              | Default                  |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------ |
| `--workflow <name>`                   | **Required.** Workflow component name (without `.yml` extension).                                        | —                        |
| `--release-please-config-root <path>` | Folder containing the `workflow-config/` subdirectory.                                                   | `.github/release-please` |
| `--config-output-file <path>`         | Write config JSON to this path instead of the default location. Manifest generation is skipped when set. | —                        |
| `--help`                              | Print usage and exit.                                                                                    | —                        |

---

## Typical Workflow

```bash
# Step 1 — first-time setup or after adding/removing workflow files:
#   generate config files for the selected workflows in the target repo
run-release-please.sh \
  --mode generate_workflow_config \
  --components docs,qnx-build \
  --working-dir /path/to/target-repo

# Step 2 — after merging feature commits, create/update release PRs:
run-release-please.sh \
  --mode pr \
  --components docs,qnx-build \
  --working-dir /path/to/target-repo \
  --repo-url owner/target-repo \
  --token "$GITHUB_TOKEN"

# Step 3 — after the release PR is merged, create GitHub releases:
run-release-please.sh \
  --mode release \
  --components docs,qnx-build \
  --working-dir /path/to/target-repo \
  --repo-url owner/target-repo \
  --token "$GITHUB_TOKEN"
```

---

## Tag and Release Naming

| Component type   | Pattern                  | Example                         |
| ---------------- | ------------------------ | ------------------------------- |
| Workflow         | `<workflow-name>/vX.Y.Z` | `docs/v2.5.1`                   |
| Composite action | `<action-name>/vX.Y.Z`   | `deploy-versioned-pages/v1.0.1` |

---

## Exit Codes

| Code | Meaning                                                                                                                  |
| ---- | ------------------------------------------------------------------------------------------------------------------------ |
| 0    | Success                                                                                                                  |
| 1    | Required external command not found (`jq`, `git`, or `npx` missing)                                                      |
| 2    | Invalid or missing CLI argument (unknown flag, `--mode` absent/invalid, or `--components` absent/empty)                  |
| 3    | Repository URL cannot be inferred from the git remote and was not provided via `--repo-url`                              |
| 4    | GitHub token not available (neither `--token`, `RELEASE_PLEASE_TOKEN`, nor `GITHUB_TOKEN` is set)                        |
| 5    | Unknown component: not recognised as a workflow (no config file in `workflow-config`) or an action (no action folder)    |
| 6    | Workflow config file missing — run `--mode generate_workflow_config` first                                               |
| 7    | Workflow manifest file missing — run `--mode generate_workflow_config` first                                             |
| 8    | Workflow config file is out of date with current repository content — run `--mode generate_workflow_config` to update it |
