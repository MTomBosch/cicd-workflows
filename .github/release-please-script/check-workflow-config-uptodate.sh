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
Check that the on-disk Release Please config file for a workflow component is consistent
with the current repository state wrt to the "exclude-paths" field.

Intended to be run in the target repository on every workflow file change, e.g. as a CI
check, to ensure the workflow-specific Release Please configuration files are valid and
up to date before a release PR is created.

Usage:
  check-workflow-config-uptodate.sh --workflow <name> [options]

Options:
  --workflow <name>              Workflow component name (without .yml extension). Required.
  --release-please-config-root <path>
                                 Folder containing the workflow-config/ subdirectory.
                                 Default: .github/release-please.
  --help                         Show this help.

Exit codes:
  0  Config file is up to date.
  1  Required external command not found (jq).
  2  Missing required argument.
  8  Config file is out of date with the current repository content.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
    exit 1
  fi
}

parse_args() {
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

main() {
  workflow=""
  release_please_config_root=".github/release-please"
  working_dir="$(pwd)"

  parse_args "$@"

  if [[ -z "${workflow}" ]]; then
    err "--workflow is required"
    exit 2
  fi

  require_cmd jq

  local workflow_config_dir="${release_please_config_root}/workflow-config"
  local existing_config="${working_dir}/${workflow_config_dir}/${workflow}-config.json"
  local tmp_config
  local existing_exclude_paths_file
  local fresh_exclude_paths_file
  tmp_config="$(mktemp --suffix=.json)"
  # I only want a unique temp file name but no existing file when running the gen-release-please-workflow-config.sh script, so I remove the file if it exists.
  rm -f "${tmp_config}"
  existing_exclude_paths_file="$(mktemp --suffix=.json)"
  fresh_exclude_paths_file="$(mktemp --suffix=.json)"

  # Ensure temporary files are removed on every exit path.
  cleanup() {
    rm -f "${tmp_config}" "${existing_exclude_paths_file}" "${fresh_exclude_paths_file}"
  }
  #trap cleanup EXIT

  (cd "${working_dir}" && "${_SCRIPT_DIR}/gen-release-please-workflow-config.sh" \
    --workflow "${workflow}" \
    --release-please-config-root "${release_please_config_root}" \
    --config-output-file "${tmp_config}")

  local existing_exclude_paths fresh_exclude_paths
  existing_exclude_paths="$(jq -c '(.packages[".github/workflows"]["exclude-paths"] // []) | sort' "${existing_config}")"
  fresh_exclude_paths="$(jq -c '(.packages[".github/workflows"]["exclude-paths"] // []) | sort' "${tmp_config}")"

  # Persist normalized values so patch output contains only the compared field.
  jq '(.packages[".github/workflows"]["exclude-paths"] // []) | sort' "${existing_config}" > "${existing_exclude_paths_file}"
  jq '(.packages[".github/workflows"]["exclude-paths"] // []) | sort' "${tmp_config}" > "${fresh_exclude_paths_file}"

  if [[ "${existing_exclude_paths}" != "${fresh_exclude_paths}" ]]; then
    err "workflow config for '${workflow}' is out of date with the current repository content."
    err "The exclude-paths field must be up to date before a release PR can be created."
    err "To update it, run gen-release-please-workflow-config.sh directly."
    err "Delta for exclude-paths (patch format):"

    diff -u \
      --label "${existing_config}" \
      --label "${tmp_config}" \
      "${existing_exclude_paths_file}" \
      "${fresh_exclude_paths_file}" >&2 || true
    exit 8
  fi

  echo "workflow config for '${workflow}' is up to date."
}

main "$@"
