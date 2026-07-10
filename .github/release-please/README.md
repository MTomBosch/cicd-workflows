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
- `.github/actions/<action-name>/release-please-manifest.json`: Release Please manifest for each composite action.
- `run-release-please.sh`: generates temporary config/manifest for workflows or copies action configs, then runs Release Please.

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
  - Defines Release Please metadata (packages, release-type, component, etc.).
  - Shared across all composite action components to ensure consistent Release Please behavior.

- `.github/actions/<action-name>/release-please-manifest.json`
  - Release Please manifest for an individual composite action.
  - Tracks the current version of the specific composite action.
  - One manifest file per action folder.

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

For a selected component, the script first auto-detects whether it's a **workflow**:

- **Workflow**: Component name exists in `workflows.json` under the `workflows` array with a `workflowFile`.

The `--all-workflows` flag only processes workflow components defined in `workflows.json`.

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
   - controlled by `--mode pr|release|both`.

Resulting tag/release naming for workflows:

- `<workflow-name>/vX.Y.Z` (e.g., `docs/v2.5.1`)

## Manual Action Release (via --component or --components)

Composite actions can still be released manually by specifying them directly via `--component` or `--components`. When an action is specified:

1. Uses the Release Please configuration and manifest files directly from the repository (no temp files):
   - Central config: `.github/release-please/actions-config.json`
   - Per-action manifest: `.github/actions/<action-name>/release-please-manifest.json`
1. Executes Release Please:

   - `release-pr` (create/update release PR)
   - `github-release` (create tag + GitHub release)
   - controlled by `--mode pr|release|both`.

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
.github/release-please/run-release-please.sh --component docs --dry-run
```

Run one composite action manually in dry-run mode (actions are not auto-discovered):

```bash
.github/release-please/run-release-please.sh --component deploy-versioned-pages --dry-run
```

Run one workflow component normally:

```bash
.github/release-please/run-release-please.sh --component qnx-build --mode both
```

Run an explicit list of components (workflows and/or actions manually specified):

```bash
.github/release-please/run-release-please.sh --components docs,qnx-build,deploy-versioned-pages --mode both
```

Run all workflow components in dry-run mode (--all-workflows only processes workflows):

```bash
.github/release-please/run-release-please.sh --all-workflows --dry-run
```

Useful options:

- `--component <name>` — Release a single component (workflow or action)
- `--components <name1,name2,...>` — Release multiple components (mixed workflows and actions)
- `--all-workflows` — Release all workflow components (not actions)
- `--mode pr|release|both` — Release Please operation mode (default: both)
- `--dry-run` — Prepare configs but don't create/update PRs or releases
- `--repo-url <owner/repo>` — GitHub repository (auto-detected from origin if not provided)
- `--target-branch <branch>` — Target branch for PRs/releases
- `--token <token>` — GitHub token (defaults to `RELEASE_PLEASE_TOKEN` or `GITHUB_TOKEN` env var)
- `--actions-root <path>` — Root folder for composite actions (default: `.github/actions`)

## Component Validation and Mixed Types

When using `--components` with multiple items, the script validates all components upfront:

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
.github/release-please/run-release-please.sh --component deploy-versioned-pages --actions-root .github/my-actions --dry-run
```

## GitHub Actions Integration

The workflow `.github/workflows/release-please.yml` uses one job and loops components by calling:

```bash
bash .github/release-please/run-release-please.sh --all-workflows ...
```

For manual runs (`workflow_dispatch`), a comma-separated `components` input can be provided to target only selected components.

This keeps local execution and CI behavior aligned and avoids duplicated release logic.
