#!/usr/bin/env bash
set -euo pipefail

# Use red for error messages when stderr is a colour-capable terminal.
if [[ -t 2 ]] && tput colors &>/dev/null && [[ "$(tput colors)" -ge 8 ]]; then
  _RED="$(tput setaf 1)"
  _RESET="$(tput sgr0)"
else
  _RED=""
  _RESET=""
fi

err() {
  echo "${_RED}error: $*${_RESET}" >&2
}

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Run Release Please for this repository's workflow and composite action components.

Usage:
  run-release-please.sh --mode <mode> --components <name1,name2,...> [options]

Options:
  --components <list>  Release one or more components (comma-separated; workflows and/or actions).
  --mode <mode>        One of: pr, release, generate_workflow_config. Required.
  --dry-run            Prepare actions but do not create/update PRs or releases.
  --repo-url <owner/repo>
                       GitHub repository that contains the actions and workflows.
                       Default: Assuming the script is called from a Git repository, inferred
                       from origin remote.
  --target-branch <branch>
                       Target branch of <repo-url> for release-pr/github-release.
  --token <token>      GitHub token. Default: RELEASE_PLEASE_TOKEN or GITHUB_TOKEN env.
  --actions-root <path>
                       Root folder for composite actions within <repo-url>. Default: .github/actions.
  --release-please-config-root <path>
                       Folder within <repo-url> containing actions-config.json, actions-manifest.json
                       and workflow related config/manifest files.
                       Default: .github/release-please.
  --release-please-working-dir <path>
                       Working directory from which the release-please CLI is invoked.
                       Default: current working directory.
  --help               Show this help.

Components:
  Workflow components are identified by the presence of a pre-generated config file
  in the workflow-config directory. Run '--mode generate_workflow_config' first.
  Composite actions are not automatically discovered.
  To release an action, specify it directly via --components.

Examples:
  .github/release-please/run-release-please.sh --components docs --dry-run
  .github/release-please/run-release-please.sh --components deploy-versioned-pages --dry-run
  .github/release-please/run-release-please.sh --components docs,qnx-build,deploy-versioned-pages --mode pr
  .github/release-please/run-release-please.sh --components docs --actions-root .github/actions --dry-run
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
    exit 1
  fi
}

infer_repo_url() {
  local origin_url
  origin_url="$(git -C "${working_dir}" remote get-url origin 2>/dev/null || true)"

  if [[ -z "${origin_url}" ]]; then
    return 1
  fi

  if [[ "${origin_url}" =~ ^git@github.com:([^/]+)/([^/.]+)(\.git)?$ ]]; then
    printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "${origin_url}" =~ ^https://github.com/([^/]+)/([^/.]+)(\.git)?$ ]]; then
    printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

detect_component_type() {
  local component="$1"
  local actions_root="$2"

  # Check if it's a workflow (a pre-generated config file exists in workflow_config_dir)
  if [[ -f "${working_dir}/${workflow_config_dir}/${component}-config.json" ]]; then
    echo "workflow"
    return 0
  fi

  # Check if it's an action by folder existence
  local action_dir="${working_dir}/${actions_root}/${component}"
  if [[ -d "${action_dir}" && -f "${working_dir}/${release_please_config_root}/actions-manifest.json" ]]; then
    echo "action"
    return 0
  fi

  echo "unknown"
  return 0  # Important: return 0 so set -e doesn't exit in command substitution
}

# Verify that the on-disk <workflow>-config.json is consistent with the current
# repository state by generating a fresh copy via gen-release-please-workflow-config.sh
# and comparing (excluding the intentionally-preserved initial-version field).
# Exits with an error when the files differ.
assure_workflow_config_valid() {
  local workflow="$1"
  local existing_config="${working_dir}/${workflow_config_dir}/${workflow}-config.json"
  local tmp_config
  tmp_config="$(mktemp --suffix=.json)"

  (cd "${working_dir}" && "${_SCRIPT_DIR}/gen-release-please-workflow-config.sh" \
    --workflow "${workflow}" \
    --release-please-config-root "${release_please_config_root}" \
    --config-output-file "${tmp_config}")

  local existing_normalized fresh_normalized
  existing_normalized="$(jq 'del(.packages[".github/workflows"]["initial-version"])' "${existing_config}")"
  fresh_normalized="$(jq 'del(.packages[".github/workflows"]["initial-version"])' "${tmp_config}")"
  rm -f "${tmp_config}"

  if [[ "${existing_normalized}" != "${fresh_normalized}" ]]; then
    err "workflow config for '${workflow}' is out of date with the current repository content."
    err "The config file must be up to date before a release PR can be created."
    err "To update it, run the script with '--mode generate_workflow_config'."
    exit 8
  fi
}

# Dispatch generate_workflow_config mode: call gen-release-please-workflow-config.sh
# for each component in the provided --components list.
generate_workflow_configs() {
  local -a workflow_items
  local item trimmed

  IFS=',' read -r -a workflow_items <<< "${components}"
  for item in "${workflow_items[@]}"; do
    trimmed="$(echo "${item}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -n "${trimmed}" ]]; then
      (cd "${working_dir}" && "${_SCRIPT_DIR}/gen-release-please-workflow-config.sh" \
        --workflow "${trimmed}" \
        --release-please-config-root "${release_please_config_root}")
    fi
  done
}

run_component() {
  local component="$1"
  local actions_root="$2"

  # Detect component type
  local component_type
  component_type="$(detect_component_type "${component}" "${actions_root}")"

  if [[ "${component_type}" == "unknown" ]]; then
    err "unknown component '${component}' (not found in workflows or actions)"
    exit 5
  fi

  local config_file manifest_file
  local config_file_arg manifest_file_arg

  if [[ "${component_type}" == "workflow" ]]; then
    config_file="${workflow_config_dir}/${component}-config.json"
    manifest_file="${workflow_config_dir}/${component}-manifest.json"

    if [[ "${mode}" == "pr" ]]; then
      assure_workflow_config_valid "${component}"
    fi

    if [[ "${dry_run}" == "true" ]]; then
      echo "==> config: ${config_file}"
      echo "==> manifest: ${manifest_file}"
    fi
  else
    # For actions, use original files from repository
    local action_dir="${working_dir}/${actions_root}/${component}"
    local actions_config_json="${release_please_config_root}/actions-config.json"
    local actions_manifest_json="${release_please_config_root}/actions-manifest.json"

    config_file="${actions_config_json}"
    manifest_file="${actions_manifest_json}"

    if [[ "${dry_run}" == "true" ]]; then
      echo "==> using original config: ${config_file}"
      echo "==> using original manifest: ${manifest_file}"
    fi
  fi

  # release-please expects config/manifest paths relative to working-dir.
  # Build them directly from the known relative base paths rather than stripping
  # a prefix from absolute paths, which is fragile.
  if [[ "${component_type}" == "workflow" ]]; then
    config_file_arg="${workflow_config_dir}/${component}-config.json"
    manifest_file_arg="${workflow_config_dir}/${component}-manifest.json"
  else
    config_file_arg="${release_please_config_root}/actions-config.json"
    manifest_file_arg="${release_please_config_root}/actions-manifest.json"
  fi

  local -a base_args
  base_args=(
    "--repo-url" "${repo_url}"
    "--config-file" "${config_file_arg}"
    "--manifest-file" "${manifest_file_arg}"
  )

  if [[ -n "${token}" ]]; then
    base_args+=("--token" "${token}")
  fi
  if [[ -n "${target_branch}" ]]; then
    base_args+=("--target-branch" "${target_branch}")
  fi
  if [[ "${dry_run}" == "true" ]]; then
    base_args+=("--dry-run")
    base_args+=("--debug")
    base_args+=("--trace")
  fi

  echo "==> component=${component} type=${component_type} mode=${mode} dry-run=${dry_run}"

  if [[ "${mode}" == "pr" ]]; then
    echo "==> running release-please release-pr for component=${component}"
    echo "==> base_args: ${base_args[*]}"
    if [[ -n "${HTTP_PROXY:-}" ]]; then
      NODE_USE_ENV_PROXY=1 env -C "${release_please_working_dir}" npx --yes release-please release-pr "${base_args[@]}"
    else
      env -C "${release_please_working_dir}" npx --yes release-please release-pr "${base_args[@]}"
    fi
  fi

  if [[ "${mode}" == "release" ]]; then
    echo "==> running release-please github-release for component=${component}"
    echo "==> base_args: ${base_args[*]}"
    if [[ -n "${HTTP_PROXY:-}" ]]; then
      NODE_USE_ENV_PROXY=1 env -C "${release_please_working_dir}" npx --yes release-please github-release "${base_args[@]}"
    else
      env -C "${release_please_working_dir}" npx --yes release-please github-release "${base_args[@]}"
    fi
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --components)
        components="${2:-}"
        shift 2
        ;;
      --mode)
        mode="${2:-}"
        shift 2
        ;;
      --actions-root)
        actions_root="${2:-}"
        shift 2
        ;;
      --release-please-config-root)
        release_please_config_root="${2:-}"
        shift 2
        ;;
      --release-please-working-dir)
        release_please_working_dir="${2:-}"
        shift 2
        ;;
      --dry-run)
        dry_run="true"
        shift
        ;;
      --repo-url)
        repo_url="${2:-}"
        shift 2
        ;;
      --target-branch)
        target_branch="${2:-}"
        shift 2
        ;;
      --token)
        token="${2:-}"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        err "unknown argument: $1"
        usage
        exit 2
        ;;
    esac
  done
}

validate_args() {
  if [[ -z "${mode}" ]]; then
    err "--mode is required; must be one of: pr, release, generate_workflow_config"
    exit 2
  fi

  if [[ "${mode}" != "pr" && "${mode}" != "release" && "${mode}" != "generate_workflow_config" ]]; then
    err "--mode must be one of: pr, release, generate_workflow_config"
    exit 2
  fi

  if [[ -z "${components}" ]]; then
    err "provide --components <name1,name2,...>"
    exit 2
  fi
}

resolve_defaults() {
  if [[ -z "${repo_url}" ]]; then
    repo_url="$(infer_repo_url || true)"
  fi

  if [[ -z "${repo_url}" ]]; then
    err "cannot infer --repo-url from origin remote; provide --repo-url <owner/repo>"
    exit 3
  fi

  if [[ -z "${target_branch}" ]]; then
    target_branch="$(git -C "${working_dir}" branch --show-current 2>/dev/null || true)"
  fi

  if [[ -z "${token}" ]]; then
    err "no GitHub token available; provide --token <token>, or set RELEASE_PLEASE_TOKEN or GITHUB_TOKEN"
    exit 4
  fi
}

run_selected_components() {
  local -a component_items valid_components
  local item trimmed_item comp_type has_errors="false"

  IFS=',' read -r -a component_items <<< "${components}"
  valid_components=()

  # Validate all components upfront before processing any
  for item in "${component_items[@]}"; do
    trimmed_item="$(echo "${item}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "${trimmed_item}" ]] && continue

    comp_type="$(detect_component_type "${trimmed_item}" "${actions_root}")"
    if [[ "${comp_type}" == "unknown" ]]; then
      err "unknown component '${trimmed_item}' (not found in workflows or actions)"
      has_errors="true"
    else
      valid_components+=("${trimmed_item}")
    fi
  done

  if [[ "${has_errors}" == "true" ]]; then
    exit 5
  fi

  for trimmed_item in "${valid_components[@]}"; do
    run_component "${trimmed_item}" "${actions_root}"
  done
}

main() {
  # Global state (no 'local' — accessible to all called functions)
  components=""
  mode=""
  dry_run="false"
  repo_url=""
  target_branch=""
  token="${RELEASE_PLEASE_TOKEN:-${GITHUB_TOKEN:-}}"
  actions_root=".github/actions"
  working_dir="$(pwd)"
  release_please_config_root=".github/release-please"
  release_please_working_dir=""

  require_cmd jq
  require_cmd git
  require_cmd npx

  parse_args "$@"
  workflow_config_dir="${release_please_config_root}/workflow-config"
  [[ -z "${release_please_working_dir}" ]] && release_please_working_dir="${working_dir}"
  validate_args

  # generate_workflow_config only touches local files — no token or repo-url needed
  if [[ "${mode}" != "generate_workflow_config" ]]; then
    resolve_defaults
  fi

  if [[ "${mode}" == "generate_workflow_config" ]]; then
    generate_workflow_configs
  else
    run_selected_components
  fi
}

main "$@"
