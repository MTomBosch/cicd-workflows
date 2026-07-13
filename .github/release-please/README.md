# Release Please Setup (Per Workflow)

This repository releases each workflow file in `.github/workflows/*.yml` as an independent component.

## Why This Is Different

Release Please manifest mode is path-based.
A package entry is configured for a path (typically a directory), not for an individual file.

In this repository, all releasable workflow files are located in the same directory:

- `.github/workflows/`

If we used one static `release-please-config.json` + `.release-please-manifest.json` pair in the usual way, it would not cleanly model "one workflow file = one independent release stream" because all files share the same path.

## Source of Truth in This Repository

Instead of static Release Please manifest files, this setup uses:

- `workflows.json`: catalog of releasable workflow and composite action components with their metadata.
- `versions/<component>.txt`: current version seed per workflow component.
- `<workflow>_changelog.md`: workflow-specific changelog file next to the workflow.
- `actions-config.json`: Release Please configuration for all composite actions.
- `actions-manifest.json`: Release Please manifest for all composite actions (shared, not per-action).
- `run-release-please.sh`: generates temporary config/manifest for workflows or uses the static action config/manifest files, then runs Release Please.

## Files

- `.github/release-please/workflows.json`
  - Defines each releasable workflow file (`workflowFile`) under `workflows` array.
  - Component names are derived from the workflow file name by removing the `.yml` extension.
  - Stores the component initial version (`initialVersion`) and current version (`currentVersion`).
- `.github/release-please/versions/*.txt`
  - One file per workflow component with the current known version.
  - Special seeds requested for this repo:
    - `docs` starts at `2.5.0`
    - `qnx-build` starts at `1.2.0`

- `.github/release-please/actions-config.json`
  - Central Release Please configuration for all composite actions.
  - Defines Release Please metadata (packages, release-type, component, changelog-path, etc.) for each action.
  - Statically maintained: add a new `packages` entry here when adding a new composite action.

- `.github/release-please/actions-manifest.json`
  - Shared Release Please manifest for all composite actions.
  - Tracks the current version of each composite action, keyed by the action's path under `.github/actions/`.
  - Updated by Release Please automatically after each release.
  - Statically maintained: add a new entry here when adding a new composite action.

- `.github/workflows/*_changelog.md`
  - One changelog file per workflow.
  - Naming convention: `<workflow file name without .yml>_changelog.md`.
  - Used via Release Please `changelog-path` per component.

- `scripts/release-please.sh`
  - For each selected component, creates ephemeral files:
    - temp config JSON
    - temp manifest JSON
  - Runs Release Please CLI against those temp files.
  - In dry-run mode, keeps temp files for inspection.
  - In non-dry-run mode, removes temp directory artifacts at script exit.

## How The Script Works

For a selected component, the script auto-detects its type:

- **Workflow**: component name is found in `workflows.json` under the `workflows` array with a matching `workflowFile`.
- **Action**: the component's folder exists under the actions root (default `.github/actions/<component>`) and `.github/release-please/actions-manifest.json` is present.

The `--all-workflows` flag only processes workflow components defined in `workflows.json`; actions are never auto-discovered and must be named explicitly.

### For Workflows:

1. Reads component metadata from `.github/release-please/workflows.json`.
1. Reads current version from `.github/release-please/versions/<component>.txt`.
1. Builds `exclude-paths` so only the component's workflow file and optional paired test workflow contribute release commits.
1. Generates a temporary config with these key settings:

```yaml
packages:
  .github/workflows:
release-type: simple
component: <component>
include-component-in-tag: true
tag-separator: /
include-v-in-tag: true
changelog-path: <workflow file name without .yml>_changelog.md
initial-version: <initialVersion>
version-file: ../release-please/versions/<component>.txt
```

1. Generates a temporary manifest with the current component version.
1. Executes Release Please:

   - `release-pr` (create/update release PR)
   - `github-release` (create tag + GitHub release)
   - controlled by `--mode pr|release`.

Resulting tag/release naming for workflows:

- `<workflow-name>/vX.Y.Z` (e.g., `docs/v2.5.1`)

## Releasing Actions (via --components)

Composite actions are released by specifying them directly via `--components`. Their Release Please configuration is **statically defined** in two files that live alongside the script — no temporary files are generated:

| File                                           | Purpose                                                                                 |
| ---------------------------------------------- | --------------------------------------------------------------------------------------- |
| `.github/release-please/actions-config.json`   | Package metadata for every action (release-type, changelog-path, initial-version, etc.) |
| `.github/release-please/actions-manifest.json` | Current version of every action, keyed by action path                                   |

When adding a new composite action, add a `packages` entry to `actions-config.json` and a version entry to `actions-manifest.json` — no other file changes are needed.

When an action component is selected, the script:

1. Verifies the action folder exists under the actions root and that `actions-manifest.json` is present.
1. Passes the static `actions-config.json` and `actions-manifest.json` directly to Release Please (no temp files).
1. Executes Release Please:

   - `release-pr` (create/update release PR)
   - `github-release` (create tag + GitHub release)
   - controlled by `--mode pr|release`.

Resulting tag/release naming for actions:

- `<action-name>/vX.Y.Z` (e.g., `deploy-versioned-pages/v1.0.1`)

## Why `release-please-config.json` and `.release-please-manifest.json` Are Not Committed

These two files are intentionally not committed because this repo needs per-file releases from a single shared directory.

A single static config+manifest pair is not usable as the primary model here because:

- Release Please manifest entries are path-oriented.
- All workflow components live under the same path.
- We need runtime, component-specific filtering (`exclude-paths`) and version seeds.

Therefore, the script generates component-scoped temporary config/manifest files per run.

## Local Usage

Run one workflow component in dry-run mode:

```bash
.github/release-please/run-release-please.sh --components docs --dry-run
```

Run one composite action manually in dry-run mode:

```bash
.github/release-please/run-release-please.sh --components deploy-versioned-pages --dry-run
```

Run one workflow component — create/update the release PR:

```bash
.github/release-please/run-release-please.sh --components qnx-build --mode pr
```

Run one workflow component — create the GitHub release after the PR is merged:

```bash
.github/release-please/run-release-please.sh --components qnx-build --mode release
```

Run an explicit list of components (workflows and/or actions):

```bash
.github/release-please/run-release-please.sh --components docs,qnx-build,deploy-versioned-pages --mode pr
```

Run all workflow components in dry-run mode (--all-workflows only processes workflows):

```bash
.github/release-please/run-release-please.sh --all-workflows --dry-run
```

Useful options:

- `--components <name1,name2,...>` — Release one or more components (comma-separated; workflows and/or actions)
- `--all-workflows` — Release all workflow components (not actions)
- `--mode pr|release` — Release Please operation mode. Required.
- `--dry-run` — Prepare configs but don't create/update PRs or releases
- `--repo-url <owner/repo>` — GitHub repository (auto-detected from origin if not provided)
- `--target-branch <branch>` — Target branch for PRs/releases
- `--token <token>` — GitHub token (defaults to `RELEASE_PLEASE_TOKEN` or `GITHUB_TOKEN` env var)
- `--actions-root <path>` — Root folder for composite actions (default: `.github/actions`)

## Component Validation and Mixed Types

When using `--components`, the script validates all components upfront:

1. **Validation Phase**: Each component is checked to determine if it's a workflow, action, or invalid.
2. **Error Reporting**: Any invalid components are reported immediately with clear error messages.
3. **Early Exit**: If any components are invalid, the script exits without processing any components.
4. **Processing Phase**: Only valid components are processed (both workflows and actions can be mixed).

Example with mixed types:

```bash
# This validates docs (workflow), deploy-versioned-pages (action), and qnx-build (workflow)
# All three are valid, so all three are processed
.github/release-please/run-release-please.sh --components "docs,deploy-versioned-pages,qnx-build" --dry-run

# This tries to process docs (workflow), invalid-comp (error), and deploy-versioned-pages (action)
# Since invalid-comp is not found, the script exits before processing anything
.github/release-please/run-release-please.sh --components "docs,invalid-comp,deploy-versioned-pages" --dry-run
```

This ensures you get clear feedback about which components are problematic before the script attempts any operations.

### Using `--actions-root`

By default, composite actions are expected in `.github/actions/`. If your composite actions are stored in a different location, use the `--actions-root` option:

```bash
.github/release-please/run-release-please.sh --components deploy-versioned-pages --actions-root .github/my-actions --dry-run
```

## GitHub Actions Integration

The workflow `.github/workflows/release-please.yml` uses one job and loops components by calling:

```bash
bash .github/release-please/run-release-please.sh --all-workflows ...
```

For manual runs (`workflow_dispatch`), a comma-separated `components` input can be provided to target only selected components.

This keeps local execution and CI behavior aligned and avoids duplicated release logic.
