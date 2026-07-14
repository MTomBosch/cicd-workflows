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

WORKFLOWS_PATH=".github/workflows"

usage() {
  cat <<'EOF'
Generate the release-please config (and optionally the manifest) for a single workflow component.

Usage:
  gen-release-please-workflow-config.sh --workflow <name> [options]

Options:
  --workflow <name>              Workflow component name (without .yml extension). Required.
  --release-please-config-root <path>
                                 Folder within the repository containing the workflow-config/
                                 subdirectory. Default: .github/release-please.
  --config-output-file <path>    Write the config JSON to this path instead of the default
                                 location. Manifest generation is skipped when this flag is set.
                                 Intended for validation use (e.g. comparing against existing file).
  --help                         Show this help.

Default output paths (relative to the current working directory):
  <release-please-config-root>/workflow-config/<name>-config.json   always written
  <release-please-config-root>/workflow-config/<name>-manifest.json created if absent
  .github/workflows/<name>_changelog.md                             created if absent
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
    exit 1
  fi
}

# Determine initial-version for a workflow with two-level fallback:
#   1. Preserve value from existing <workflow>-config.json (so re-generation never resets it)
#   2. Default to 1.0.0
get_initial_version() {
  local wf="$1"
  local existing="${working_dir}/${workflow_config_dir}/${wf}-config.json"
  local version

  if [[ -f "${existing}" ]]; then
    version="$(jq -r '.packages[".github/workflows"]["initial-version"] // empty' "${existing}" 2>/dev/null || true)"
    if [[ -n "${version}" && "${version}" != "null" ]]; then
      echo "${version}"
      return 0
    fi
  fi

  echo "1.0.0"
}

# Preserve the top-level bootstrap-sha from an existing <workflow>-config.json, if present.
# Returns an empty string when no existing file or no bootstrap-sha field is found.
get_bootstrap_sha() {
  local wf="$1"
  local existing="${working_dir}/${workflow_config_dir}/${wf}-config.json"
  local sha

  if [[ -f "${existing}" ]]; then
    sha="$(jq -r '."bootstrap-sha" // empty' "${existing}" 2>/dev/null || true)"
    if [[ -n "${sha}" && "${sha}" != "null" ]]; then
      echo "${sha}"
      return 0
    fi
  fi

  echo ""
}

# Build the exclude-paths JSON array for a workflow by scanning the workflows
# directory for all *.yml/*.yaml files and excluding the workflow itself.
compute_exclude_paths() {
  local current_wf_name="$1"
  local current_wf_file="${current_wf_name}.yml"
  local -a excludes
  local filepath filename base

  while IFS= read -r filepath; do
    filename="$(basename "${filepath}")"
    if [[ "${filename}" != "${current_wf_file}" ]]; then
      base="${filename%.*}"
      excludes+=(".github/workflows/${filename}")
      excludes+=(".github/workflows/${base}_changelog.md")
    fi
  done < <(find "${working_dir}/${WORKFLOWS_PATH}" -maxdepth 1 \( -name "*.yml" -o -name "*.yaml" \) | sort)

  if [[ ${#excludes[@]} -gt 0 ]]; then
    printf '%s\n' "${excludes[@]}" | jq -R . | jq -s .
  else
    echo "[]"
  fi
}

# Write the release-please config JSON for a workflow to the given output file.
write_workflow_config_json() {
  local wf="$1"
  local output_file="$2"
  local initial_version="${3:-}"
  local bootstrap_sha="${4:-}"
  local changelog_path="${wf}_changelog.md"
  local exclude_paths

  if [[ -z "${initial_version}" ]]; then
    initial_version="$(get_initial_version "${wf}")"
  fi
  exclude_paths="$(compute_exclude_paths "${wf}")"

  jq -n --sort-keys \
    --arg component "${wf}" \
    --arg initial_version "${initial_version}" \
    --arg changelog_path "${changelog_path}" \
    --argjson exclude_paths "${exclude_paths}" \
    --arg bootstrap_sha "${bootstrap_sha}" \
    '{
      "packages": {
        ".github/workflows": {
          "changelog-path": $changelog_path,
          "component": $component,
          "exclude-paths": $exclude_paths,
          "include-component-in-tag": true,
          "include-v-in-tag": true,
          "initial-version": $initial_version,
          "release-type": "simple",
          "tag-separator": "/"
        }
      }
    }
    | if $bootstrap_sha != "" then . + {"bootstrap-sha": $bootstrap_sha} else . end' > "${output_file}"
}

# Generate the config and, unless --config-output-file is set, the manifest as well.
generate_config() {
  local wf="$1"
  local changelog_path="${wf}_changelog.md"
  local initial_version bootstrap_sha config_file

  if [[ -n "${config_output_file}" ]]; then
    # Validation / temp-file mode: write config to the caller-specified path only.
    initial_version="$(get_initial_version "${wf}")"
    bootstrap_sha="$(get_bootstrap_sha "${wf}")"
    write_workflow_config_json "${wf}" "${config_output_file}" "${initial_version}" "${bootstrap_sha}"
    return 0
  fi

  # Normal mode: write config + manifest to their standard locations.
  mkdir -p "${working_dir}/${workflow_config_dir}"
  config_file="${working_dir}/${workflow_config_dir}/${wf}-config.json"

  mkdir -p "${working_dir}/${WORKFLOWS_PATH}"
  if [[ ! -f "${working_dir}/${WORKFLOWS_PATH}/${changelog_path}" ]]; then
    printf '# Changelog\n\n' > "${working_dir}/${WORKFLOWS_PATH}/${changelog_path}"
  fi

  initial_version="$(get_initial_version "${wf}")"
  bootstrap_sha="$(get_bootstrap_sha "${wf}")"
  write_workflow_config_json "${wf}" "${config_file}" "${initial_version}" "${bootstrap_sha}"
  echo "==> generated config: ${config_file}"

  local manifest_file="${working_dir}/${workflow_config_dir}/${wf}-manifest.json"
  if [[ ! -f "${manifest_file}" ]]; then
    jq -n \
      --arg version "${initial_version}" \
      --arg workflows_path "${WORKFLOWS_PATH}" \
      '{($workflows_path): $version}' > "${manifest_file}"
    echo "==> generated manifest: ${manifest_file}"
  else
    echo "==> manifest unchanged (already exists): ${manifest_file}"
  fi
}

main() {
  # Global state (no 'local' — accessible to all called functions)
  workflow=""
  working_dir="$(pwd)"
  release_please_config_root=".github/release-please"
  config_output_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workflow)
        workflow="${2:-}"
        shift 2
        ;;
      --release-please-config-root)
        release_please_config_root="${2:-}"
        shift 2
        ;;
      --config-output-file)
        config_output_file="${2:-}"
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

  if [[ -z "${workflow}" ]]; then
    err "--workflow is required"
    exit 2
  fi

  require_cmd jq

  workflow_config_dir="${release_please_config_root}/workflow-config"

  generate_config "${workflow}"
}

main "$@"
