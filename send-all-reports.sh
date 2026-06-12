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

send_report_for_repo() {
  local repo_path="$1"
  local repo_name
  repo_name="$(basename "${repo_path}")"

  if ! has_report_files "${repo_path}"; then
    echo "${C_YELLOW}Skipping ${repo_name}: no generated Specmatic reports found${C_RESET}"
    SKIPPED_PROJECTS+=("${repo_name}")
    return 0
  fi

  echo "${C_BLUE}Sending reports for ${repo_name}${C_RESET}"
  (
    cd "${repo_path}"
    "${SPECMATIC_CMD[@]}" send-report \
      --repo-id="$(gh api 'repos/{owner}/{repo}' --jq .id)" \
      --repo-name="$(gh repo view --json name -q .name)" \
      --repo-url="$(gh repo view --json url --jq .url)" \
      --branch-name main
  )
}

send_federated_central_repo_report_for_repo() {
  local repo_path="$1"
  local repo_name
  local central_repo_script="${repo_path}/ci_central_repo_report.sh"
  repo_name="$(basename "${repo_path}")"

  if [[ ! -f "${central_repo_script}" ]]; then
    echo "${C_YELLOW}Skipping ${repo_name} central repo report: ci_central_repo_report.sh not found${C_RESET}"
    SKIPPED_PROJECTS+=("${repo_name} central-repo")
    return 0
  fi

  if ! has_federated_central_repo_report_files "${repo_path}"; then
    echo "${C_YELLOW}Skipping ${repo_name} central repo report: no generated federated central repo report found${C_RESET}"
    SKIPPED_PROJECTS+=("${repo_name} central-repo")
    return 0
  fi

  echo "${C_BLUE}Sending federated central repo report for ${repo_name}${C_RESET}"
  (
    cd "${repo_path}"
    SEND_REPORT=1 bash ./ci_central_repo_report.sh
  )
}

pass=0
fail=0
PASSING_PROJECTS=()
FAILING_PROJECTS=()
SKIPPED_PROJECTS=()

echo "Sending report artifacts for $(( ${#PROJECTS[@]} + 1 )) repos"
echo

if send_report_for_repo "${SCRIPT_DIR}/central-contract-repository"; then
  pass=$((pass + 1))
  PASSING_PROJECTS+=("central-contract-repository")
else
  fail=$((fail + 1))
  FAILING_PROJECTS+=("central-contract-repository")
fi
echo

for project in "${FEDERATED_PROVIDER_PROJECTS[@]}"; do
  echo "=== ${project} central repo report ==="
  if send_federated_central_repo_report_for_repo "${SCRIPT_DIR}/${project}"; then
    if [[ " ${SKIPPED_PROJECTS[*]} " == *" ${project} central-repo "* ]]; then
      :
    else
      pass=$((pass + 1))
      PASSING_PROJECTS+=("${project} central-repo")
    fi
  else
    fail=$((fail + 1))
    FAILING_PROJECTS+=("${project} central-repo")
  fi
  echo
done

for project in "${PROJECTS[@]}"; do
  echo "=== ${project} ==="
  if send_report_for_repo "${SCRIPT_DIR}/${project}"; then
    if [[ " ${SKIPPED_PROJECTS[*]} " == *" ${project} "* ]]; then
      :
    else
      pass=$((pass + 1))
      PASSING_PROJECTS+=("${project}")
    fi
  else
    fail=$((fail + 1))
    FAILING_PROJECTS+=("${project}")
  fi
  echo
done

echo "SUMMARY: PASS=${pass} FAIL=${fail} SKIP=${#SKIPPED_PROJECTS[@]} TOTAL=$(( ${#PROJECTS[@]} + ${#FEDERATED_PROVIDER_PROJECTS[@]} + 1 ))"
echo "Sent reports:"
if [[ ${#PASSING_PROJECTS[@]} -eq 0 ]]; then
  echo "  (none)"
else
  printf '  - %s\n' "${PASSING_PROJECTS[@]}"
fi

echo "Skipped repos:"
if [[ ${#SKIPPED_PROJECTS[@]} -eq 0 ]]; then
  echo "  (none)"
else
  printf '  - %s\n' "${SKIPPED_PROJECTS[@]}"
fi

echo "Failed repos:"
if [[ ${#FAILING_PROJECTS[@]} -eq 0 ]]; then
  echo "  (none)"
else
  printf '  - %s\n' "${FAILING_PROJECTS[@]}"
fi

if [[ ${fail} -ne 0 ]]; then
  exit 1
fi
