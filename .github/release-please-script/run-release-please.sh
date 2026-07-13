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
  run-release-please.sh --mode <mode> --components <type>:<name>[,<type>:<name>,...] [options]

Options:
  --components <list>  Release one or more components (comma-separated). Each entry must be
                       prefixed with a type: 'w:<name>' for a workflow component or
                       'a:<name>' for a composite action component.
  --mode <mode>        One of: pr, release. Required.
  --dry-run            Prepare actions but do not create/update PRs or releases.
  --repo-url <owner/repo>
                       GitHub repository that contains the actions and workflows.
                       Default: Assuming the script is called from a Git repository, inferred
                       from origin remote.
  --target-branch <branch>
                       Target branch of <repo-url> for release-pr/github-release.
  --token <token>      GitHub token. Default: RELEASE_PLEASE_TOKEN or GITHUB_TOKEN env.
  --release-please-config-root <path>
                       Folder within <repo-url> containing actions-config.json, actions-manifest.json
                       and workflow related config/manifest files.
                       Default: .github/release-please.
  --release-please-working-dir <path>
                       Working directory from which the release-please CLI is invoked.
                       Default: current working directory.
  --help               Show this help.

Components:
  Each component must be specified as <type>:<name> where type is:
    w  — workflow component. Config and manifest files are read from
         <release-please-config-root>/workflow-config/<name>-config.json and
         <release-please-config-root>/workflow-config/<name>-manifest.json.
    a  — composite action component. Config and manifest files are read from
         <release-please-config-root>/actions-config.json and
         <release-please-config-root>/actions-manifest.json.

Examples:
  .github/release-please/run-release-please.sh --components w:docs --dry-run
  .github/release-please/run-release-please.sh --components a:deploy-versioned-pages --dry-run
  .github/release-please/run-release-please.sh --components w:docs,w:qnx-build,a:deploy-versioned-pages --mode pr
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

run_component() {
  local component_spec="$1"

  # Parse <type>:<name> format
  local component_type component_name
  component_type="${component_spec%%:*}"
  component_name="${component_spec#*:}"

  local config_file_arg manifest_file_arg

  if [[ "${component_type}" == "w" ]]; then
    config_file_arg="${workflow_config_dir}/${component_name}-config.json"
    manifest_file_arg="${workflow_config_dir}/${component_name}-manifest.json"

    if [[ "${dry_run}" == "true" ]]; then
      echo "==> config: ${config_file_arg}"
      echo "==> manifest: ${manifest_file_arg}"
    fi
  else
    config_file_arg="${release_please_config_root}/actions-config.json"
    manifest_file_arg="${release_please_config_root}/actions-manifest.json"

    if [[ "${dry_run}" == "true" ]]; then
      echo "==> using original config: ${config_file_arg}"
      echo "==> using original manifest: ${manifest_file_arg}"
    fi
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

  echo "==> component=${component_name} type=${component_type} mode=${mode} dry-run=${dry_run}"

  if [[ "${mode}" == "pr" ]]; then
    echo "==> running release-please release-pr for component=${component_name}"
    echo "==> base_args: ${base_args[*]}"
    if [[ -n "${HTTP_PROXY:-}" ]]; then
      NODE_USE_ENV_PROXY=1 env -C "${release_please_working_dir}" npx --yes release-please release-pr "${base_args[@]}"
    else
      env -C "${release_please_working_dir}" npx --yes release-please release-pr "${base_args[@]}"
    fi
  fi

  if [[ "${mode}" == "release" ]]; then
    echo "==> running release-please github-release for component=${component_name}"
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
    err "--mode is required; must be one of: pr, release"
    exit 2
  fi

  if [[ "${mode}" != "pr" && "${mode}" != "release" ]]; then
    err "--mode must be one of: pr, release"
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
  local item trimmed_item comp_type comp_name has_errors="false"

  IFS=',' read -r -a component_items <<< "${components}"
  valid_components=()

  # Validate all components upfront before processing any
  for item in "${component_items[@]}"; do
    trimmed_item="$(echo "${item}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "${trimmed_item}" ]] && continue

    comp_type="${trimmed_item%%:*}"
    comp_name="${trimmed_item#*:}"

    if [[ "${comp_type}" != "a" && "${comp_type}" != "w" ]]; then
      err "invalid component spec '${trimmed_item}': type must be 'a' (action) or 'w' (workflow)"
      has_errors="true"
    elif [[ -z "${comp_name}" || "${comp_name}" == "${trimmed_item}" ]]; then
      err "invalid component spec '${trimmed_item}': format must be <type>:<name>"
      has_errors="true"
    else
      valid_components+=("${trimmed_item}")
    fi
  done

  if [[ "${has_errors}" == "true" ]]; then
    exit 5
  fi

  for trimmed_item in "${valid_components[@]}"; do
    run_component "${trimmed_item}"
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

  resolve_defaults
  run_selected_components
}

main "$@"
