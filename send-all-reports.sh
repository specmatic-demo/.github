#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./specmatic-loop-common.sh
source "${SCRIPT_DIR}/specmatic-loop-common.sh"

FEDERATED_PROVIDER_PROJECTS=(
  "catalog-service"
  "pricing-service"
  "notification-service"
  "web-bff"
)

init_specmatic_cmd
init_colors

mapfile -t DISCOVERED_PROJECTS < <(
  find "${SCRIPT_DIR}" -mindepth 1 -maxdepth 1 -type d \
    ! -name ".*" \
    -exec test -f "{}/specmatic.yaml" \; \
    -print \
    | xargs -n1 basename \
    | sort
)

if [[ ${#DISCOVERED_PROJECTS[@]} -eq 0 ]]; then
  echo "No project directories found with specmatic.yaml."
  exit 1
fi

PROJECTS=()

for project in "${FEDERATED_PROVIDER_PROJECTS[@]}"; do
  if printf '%s\n' "${DISCOVERED_PROJECTS[@]}" | grep -qx "${project}"; then
    PROJECTS+=("${project}")
  fi
done

for project in "${DISCOVERED_PROJECTS[@]}"; do
  skip="false"
  for prioritized in "${FEDERATED_PROVIDER_PROJECTS[@]}"; do
    if [[ "${project}" == "${prioritized}" ]]; then
      skip="true"
      break
    fi
  done

  if [[ "${skip}" == "false" ]]; then
    PROJECTS+=("${project}")
  fi
done

has_report_files() {
  local repo_path="$1"
  local report_dir="${repo_path}/build/reports/specmatic"

  [[ -d "${report_dir}" ]] || return 1
  find "${report_dir}" -type f | grep -q .
}

has_federated_central_repo_report_files() {
  local repo_path="$1"
  local report_dir="${repo_path}/specs/build/reports/specmatic"

  [[ -d "${report_dir}" ]] || return 1
  find "${report_dir}" -type f | grep -q .
}

echo "Reports are posted automatically by Specmatic during test, mock, and central-contract-repo-report runs."

if [[ ${fail} -ne 0 ]]; then
  exit 1
fi
