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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
WORKFLOWS_JSON="${REPO_ROOT}/.github/release-please/workflows.json"
TMP_ROOT="${REPO_ROOT}/.github/release-please/tmp"
WORKFLOWS_PATH=".github/workflows"

usage() {
  cat <<'EOF'
Run Release Please for this repository's workflow and composite action components.

Usage:
  scripts/release-please.sh --component <name> [options]
  scripts/release-please.sh --components <name1,name2,...> [options]
  scripts/release-please.sh --all-workflows [options]

Options:
  --component <name>   Release only one component (workflow or action).
  --components <list>  Release comma-separated component list (workflows and/or actions).
  --all-workflows      Release all components (workflows and actions).
  --mode <mode>        One of: pr, release, both. Default: both.
  --dry-run            Prepare actions but do not create/update PRs or releases.
  --repo-url <owner/repo>
                       GitHub repository. Default: inferred from origin remote.
  --target-branch <branch>
                       Target branch for release-pr/github-release.
  --token <token>      GitHub token. Default: RELEASE_PLEASE_TOKEN or GITHUB_TOKEN env.
  --actions-root <path>
                       Root folder for composite actions. Default: .github/actions.
  --help               Show this help.

Components:
  Workflows are defined in .github/release-please/workflows.json under "workflows".
  Composite actions are not automatically discovered via workflows.json.
  To release an action, specify it directly via --component or --components.

Examples:
  .github/release-please/run-release-please.sh --component docs --dry-run
  .github/release-please/run-release-please.sh --component deploy-versioned-pages --dry-run
  .github/release-please/run-release-please.sh --components docs,qnx-build,deploy-versioned-pages --mode pr
  .github/release-please/run-release-please.sh --all-workflows --repo-url eclipse-score/cicd-workflows --target-branch main
  .github/release-please/run-release-please.sh --component docs --actions-root .github/actions --dry-run
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
  origin_url="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"

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

  # Check if it's a workflow
  local workflow_check="$(jq -r --arg component "${component}" '.workflows[] | select(.workflowFile == ($component + ".yml")) | .workflowFile' "${WORKFLOWS_JSON}" 2>/dev/null || echo "")"
  if [[ -n "${workflow_check}" && "${workflow_check}" != "null" ]]; then
    echo "workflow"
    return 0
  fi

  # Check if it's an action by folder existence
  local action_dir="${REPO_ROOT}/${actions_root}/${component}"
  if [[ -d "${action_dir}" && -f "${action_dir}/release-please-manifest.json" ]]; then
    echo "action"
    return 0
  fi

  echo "unknown"
  return 0  # Important: return 0 so set -e doesn't exit in command substitution
}

build_workflow_files() {
  local workflowFile="$1"
  local tmp_config="$2"
  local tmp_manifest="$3"

  # Derive component name from workflowFile by removing the .yml extension
  local component="${workflowFile%.yml}"
  local workflow_base="${component}"

  local initial_version version_file current_version exclude_paths changelog_path

  initial_version="$(jq -r --arg workflowFile "${workflowFile}" '.workflows[] | select(.workflowFile == $workflowFile) | .initialVersion' "${WORKFLOWS_JSON}")"
  current_version="$(jq -r --arg workflowFile "${workflowFile}" '.workflows[] | select(.workflowFile == $workflowFile) | .currentVersion' "${WORKFLOWS_JSON}")"

  if [[ -z "${initial_version}" || "${initial_version}" == "null" ]]; then
    err "unknown workflowFile '${workflowFile}' in ${WORKFLOWS_JSON}"
    exit 1
  fi

  current_version="$(jq -r --arg component "${component}" '.workflows[] | select(.component == $component) | .currentVersion' "${WORKFLOWS_JSON}")"
  # `version-file` is resolved relative to package path `.github/workflows`.
  version_file="../release-please/versions/${component}.txt"

  changelog_path="${workflow_base}_changelog.md"
  mkdir -p "${REPO_ROOT}/.github/workflows"
  if [[ ! -f "${REPO_ROOT}/${WORKFLOWS_PATH}/${changelog_path}" ]]; then
    cat > "${REPO_ROOT}/${WORKFLOWS_PATH}/${changelog_path}" <<EOF
# Changelog

EOF
  fi

  # Exclude all workflow and changelog files except this component.
  exclude_paths="$(jq -c \
    --arg workflowFile "${workflowFile}" \
    '[
      (.workflows[] | select(.workflowFile != $workflowFile) | ".github/workflows/" + .workflowFile),
      (.workflows[] | select(.workflowFile != $workflowFile) | ".github/workflows/" + (.workflowFile | sub("\\.yml$"; "_changelog.md")))
    ] | flatten | unique' \
    "${WORKFLOWS_JSON}")"

  jq -n \
    --arg component "${component}" \
    --arg initial_version "${initial_version}" \
    --arg version_file "${version_file}" \
    --arg changelog_path "${changelog_path}" \
    --argjson exclude_paths "${exclude_paths}" \
    '{
      "packages": {
        ".github/workflows": {
          "release-type": "simple",
          "component": $component,
          "include-component-in-tag": true,
          "include-v-in-tag": true,
          "tag-separator": "/",
          "changelog-path": $changelog_path,
          "initial-version": $initial_version,
          "version-file": $version_file,
          "exclude-paths": $exclude_paths
        }
      }
    }' > "${tmp_config}"

  jq -n --arg version "${current_version}" --arg workflows_path "${WORKFLOWS_PATH}" '{($workflows_path): $version}' > "${tmp_manifest}"
}

new_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    tr -d '\n' < /proc/sys/kernel/random/uuid
    return 0
  fi

  # Fallback when /proc is unavailable.
  date +%s%N
}

cleanup_release_please_temps() {
  if [[ -d "${TMP_ROOT}" ]]; then
    find "${TMP_ROOT}" -maxdepth 1 -mindepth 1 -exec rm -rf {} + 2>/dev/null || true
  fi
}

run_component() {
  local component="$1"
  local actions_root="$2"

  # Detect component type
  local component_type
  component_type="$(detect_component_type "${component}" "${actions_root}")"

  if [[ "${component_type}" == "unknown" ]]; then
    err "unknown component '${component}' (not found in workflows or actions)"
    exit 1
  fi

  local workflowFile uuid timestamp tmp_dir tmp_config tmp_manifest config_file manifest_file

  if [[ "${component_type}" == "workflow" ]]; then
    workflowFile="${component}.yml"
    # Verify the workflowFile exists in workflows.json
    local check="$(jq -r --arg workflowFile "${workflowFile}" '.workflows[] | select(.workflowFile == $workflowFile) | .workflowFile' "${WORKFLOWS_JSON}")"
    if [[ -z "${check}" || "${check}" == "null" ]]; then
      err "unknown workflowFile '${workflowFile}' in ${WORKFLOWS_JSON}"
      exit 1
    fi

    # Create temp files for workflows
    uuid="$(new_uuid)"
    timestamp="$(date +%Y%m%d%H%M%S)"
    tmp_dir="${TMP_ROOT}/${component}.${timestamp}.${uuid}"
    mkdir -p "${tmp_dir}"
    tmp_config="${tmp_dir}/config.${component}.json"
    tmp_manifest="${tmp_dir}/manifest.${component}.json"

    build_workflow_files "${component}.yml" "${tmp_config}" "${tmp_manifest}"
    config_file="${tmp_config}"
    manifest_file="${tmp_manifest}"

    if [[ "${dry_run}" == "true" ]]; then
      echo "==> dry-run temp config: ${tmp_config}"
      echo "==> dry-run temp manifest: ${tmp_manifest}"
    fi
  else
    # For actions, use original files from repository
    local action_dir="${REPO_ROOT}/${actions_root}/${component}"
    local central_config="${SCRIPT_DIR}/actions-config.json"
    local source_manifest="${action_dir}/release-please-manifest.json"

    # Verify action files are present (folder already checked in detect_component_type)
    if [[ ! -f "${central_config}" ]]; then
      err "missing central config file at ${central_config}"
      exit 1
    fi

    if [[ ! -f "${source_manifest}" ]]; then
      err "missing manifest file for action '${component}' at ${source_manifest}"
      exit 1
    fi

    config_file="${central_config}"
    manifest_file="${source_manifest}"

    if [[ "${dry_run}" == "true" ]]; then
      echo "==> using original config: ${config_file}"
      echo "==> using original manifest: ${manifest_file}"
    fi
  fi

  local -a base_args
  base_args=(
    "--repo-url" "${repo_url}"
    "--config-file" "${config_file}"
    "--manifest-file" "${manifest_file}"
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

  if [[ "${mode}" == "pr" || "${mode}" == "both" ]]; then
    echo "==> running release-please release-pr for component=${component}"
    echo "==> base_args: ${base_args[*]}"
    npx --yes release-please release-pr "${base_args[@]}"
  fi

  if [[ "${mode}" == "release" || "${mode}" == "both" ]]; then
    echo "==> running release-please github-release for component=${component}"
    echo "==> base_args: ${base_args[*]}"
    npx --yes release-please github-release "${base_args[@]}"
  fi
}

require_cmd jq
require_cmd git
require_cmd npx

component=""
components=""
run_all="false"
mode="both"
dry_run="false"
repo_url=""
target_branch=""
token="${RELEASE_PLEASE_TOKEN:-${GITHUB_TOKEN:-}}"
actions_root=".github/actions"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --component)
      component="${2:-}"
      shift 2
      ;;
    --components)
      components="${2:-}"
      shift 2
      ;;
    --all-workflows)
      run_all="true"
      shift
      ;;
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --actions-root)
      actions_root="${2:-}"
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

if [[ "${mode}" != "pr" && "${mode}" != "release" && "${mode}" != "both" ]]; then
  err "--mode must be one of: pr, release, both"
  exit 2
fi

if [[ ! -f "${WORKFLOWS_JSON}" ]]; then
  err "missing ${WORKFLOWS_JSON}"
  exit 1
fi

selection_count=0
if [[ "${run_all}" == "true" ]]; then
  selection_count=$((selection_count + 1))
fi
if [[ -n "${component}" ]]; then
  selection_count=$((selection_count + 1))
fi
if [[ -n "${components}" ]]; then
  selection_count=$((selection_count + 1))
fi

if [[ "${selection_count}" -gt 1 ]]; then
  err "use exactly one of --all-workflows, --component, or --components"
  exit 2
fi

if [[ "${selection_count}" -eq 0 ]]; then
  err "provide --all-workflows, --component <name>, or --components <name1,name2,...>"
  exit 2
fi

if [[ -z "${repo_url}" ]]; then
  repo_url="$(infer_repo_url || true)"
fi

if [[ -z "${repo_url}" ]]; then
  err "cannot infer --repo-url from origin remote; provide --repo-url <owner/repo>"
  exit 2
fi

if [[ -z "${token}" ]]; then
  err "no GitHub token available; provide --token <token>, or set RELEASE_PLEASE_TOKEN or GITHUB_TOKEN"
  exit 2
fi

if [[ "${dry_run}" != "true" ]]; then
  trap cleanup_release_please_temps EXIT
fi

if [[ "${run_all}" == "true" ]]; then
  # Run all workflows (--all-workflows does not process actions)
  while IFS= read -r item; do
    run_component "${item}" "${actions_root}"
  done < <(jq -r '.workflows[].workflowFile | sub("\\.yml$"; "")' "${WORKFLOWS_JSON}")
elif [[ -n "${components}" ]]; then
  # Split comma-separated list and validate all components first
  IFS=',' read -r -a component_items <<< "${components}"
  valid_components=()
  has_errors="false"

  for item in "${component_items[@]}"; do
    trimmed_item="$(echo "${item}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "${trimmed_item}" ]]; then
      continue
    fi

    # Validate component type
    comp_type="$(detect_component_type "${trimmed_item}" "${actions_root}")"
    if [[ "${comp_type}" == "unknown" ]]; then
      err "unknown component '${trimmed_item}' (not found in workflows or actions)"
      has_errors="true"
    else
      valid_components+=("${trimmed_item}")
    fi
  done

  # Exit if there were any validation errors
  if [[ "${has_errors}" == "true" ]]; then
    exit 1
  fi

  # Process all valid components
  for trimmed_item in "${valid_components[@]}"; do
    run_component "${trimmed_item}" "${actions_root}"
  done
else
  # Pass component name directly (run_component handles detection)
  run_component "${component}" "${actions_root}"
fi
