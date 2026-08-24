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

PROJECT_DIR=""
LIST_TARGETS="false"
JSON_OUTPUT="false"
SUMMARY_JSON_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --list-targets)
      LIST_TARGETS="true"
      shift
      ;;
    --json)
      JSON_OUTPUT="true"
      shift
      ;;
    --summary-json-path)
      SUMMARY_JSON_PATH="$2"
      shift 2
      ;;
    *)
      if [[ -z "${PROJECT_DIR}" ]]; then
        PROJECT_DIR="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

init_specmatic_cmd
init_colors

json_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "${value}"
}

write_json_file() {
  local output_path="$1"
  local content="$2"
  [[ -n "${output_path}" ]] || return 0
  mkdir -p "$(dirname "${output_path}")"
  printf '%s\n' "${content}" >"${output_path}"
}

snapshot_report_files() {
  local report_dir="$1"
  local report_file
  shopt -s globstar nullglob
  for report_file in "${report_dir}"/**/* "${report_dir}"/*; do
    [[ -f "${report_file}" ]] || continue
    printf '%s\n' "${report_file#"${report_dir}/"}"
  done
  shopt -u globstar nullglob
}

run_bcc_for_project() {
  local project_dir="$1"
  local project_name spec_search_root report_dir before_snapshot after_snapshot report_file exit_code

  project_dir="$(cd "${project_dir}" && pwd)"
  project_name="${project_dir##*/}"
  report_dir="${project_dir}/build/reports/specmatic/backward_compatibility"

  if [[ -d "${project_dir}/specs" ]]; then
    spec_search_root="${project_dir}/specs"
  elif [[ "${project_name}" == "central-contract-repository" && -d "${project_dir}/contracts" ]]; then
    spec_search_root="${project_dir}/contracts"
  else
    echo "No supported spec root found in ${project_dir}. Expected specs/ or central-contract-repository/contracts/" >&2
    return 1
  fi

  echo "${C_BLUE}Project: ${project_name}${C_RESET}"
  echo "${C_BLUE}Working directory: ${project_dir}${C_RESET}"
  echo "${C_BLUE}Spec search root: ${spec_search_root}${C_RESET}"
  echo "${C_BLUE}Using Specmatic command: ${SPECMATIC_CMD[*]}${C_RESET}"
  echo "${C_BLUE}Expected BCC report directory: ${report_dir}${C_RESET}"

  before_snapshot=""
  if [[ -d "${report_dir}" ]]; then
    before_snapshot="$(snapshot_report_files "${report_dir}")"
  fi

  cd "${project_dir}"
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="safe.directory"
  export GIT_CONFIG_VALUE_0="${project_dir}"

  echo "${C_BLUE}Running backward compatibility check from ${project_dir}${C_RESET}"
  if "${SPECMATIC_CMD[@]}" backward-compatibility-check 2>&1 | prefix_output "$C_GREEN" "bcc"; then
    echo "${C_GREEN}Backward compatibility check completed${C_RESET}"
    exit_code=0
  else
    exit_code=$?
    echo "${C_RED}Backward compatibility check failed with exit ${exit_code}${C_RESET}" >&2
  fi

  echo
  echo "${C_BLUE}Report files under ${report_dir}:${C_RESET}"
  if [[ -d "${report_dir}" ]]; then
    shopt -s globstar nullglob
    report_found="false"
    for report_file in "${report_dir}"/**/* "${report_dir}"/*; do
      [[ -f "${report_file}" ]] || continue
      report_found="true"
      echo "  - ${report_file}"
    done
    shopt -u globstar nullglob
    if [[ "${report_found}" != "true" ]]; then
      echo "  (no files found)"
    fi
  else
    echo "  (report directory not found)"
  fi

  after_snapshot=""
  if [[ -d "${report_dir}" ]]; then
    after_snapshot="$(snapshot_report_files "${report_dir}")"
  fi

  echo
  if [[ "${before_snapshot}" != "${after_snapshot}" ]]; then
    echo "${C_GREEN}Report directory changed during BCC execution${C_RESET}"
  else
    echo "${C_YELLOW}No report directory changes detected during BCC execution${C_RESET}"
  fi

  return "${exit_code}"
}

discover_projects() {
  local discovered_projects=()
  local ordered_projects=()
  local project

  while IFS= read -r project; do
    [[ -n "${project}" ]] || continue
    discovered_projects+=("${project}")
  done < <(
    for project_dir in "${SCRIPT_DIR}"/*; do
      [[ -d "${project_dir}" ]] || continue
      project="$(basename "${project_dir}")"
      [[ "${project}" == .* ]] && continue

      if [[ -d "${project_dir}/specs" ]] && find "${project_dir}/specs" -type f -name openapi.yaml | grep -q .; then
        printf '%s\n' "${project}"
      elif [[ "${project}" == "central-contract-repository" && -d "${project_dir}/contracts" ]] && find "${project_dir}/contracts" -type f -name openapi.yaml | grep -q .; then
        printf '%s\n' "${project}"
      fi
    done | sort
  )

  if [[ ${#discovered_projects[@]} -eq 0 ]]; then
    echo "No BCC target directories found with OpenAPI specs." >&2
    exit 1
  fi

  for project in "${FEDERATED_PROVIDER_PROJECTS[@]}"; do
    if printf '%s\n' "${discovered_projects[@]}" | grep -qx "${project}"; then
      ordered_projects+=("${project}")
    fi
  done

  for project in "${discovered_projects[@]}"; do
    if ! printf '%s\n' "${FEDERATED_PROVIDER_PROJECTS[@]}" | grep -qx "${project}"; then
      ordered_projects+=("${project}")
    fi
  done

  printf '%s\n' "${ordered_projects[@]}"
}

mapfile -t PROJECTS < <(discover_projects)

if [[ "${LIST_TARGETS}" == "true" ]]; then
  if [[ "${JSON_OUTPUT}" == "true" ]]; then
    printf '[\n'
    for i in "${!PROJECTS[@]}"; do
      printf '  %s' "$(json_string "${PROJECTS[$i]}")"
      if (( i < ${#PROJECTS[@]} - 1 )); then
        printf ','
      fi
      printf '\n'
    done
    printf ']\n'
  else
    printf '%s\n' "${PROJECTS[@]}"
  fi
  exit 0
fi

if [[ -n "${PROJECT_DIR}" ]]; then
  RESOLVED_PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"
  if run_bcc_for_project "${RESOLVED_PROJECT_DIR}"; then
    EXIT_CODE=0
  else
    EXIT_CODE=$?
  fi

  SUMMARY_CONTENT="$(cat <<EOF
{
  "mode": "single",
  "total": 1,
  "pass": $([[ "${EXIT_CODE}" -eq 0 ]] && echo 1 || echo 0),
  "fail": $([[ "${EXIT_CODE}" -eq 0 ]] && echo 0 || echo 1),
  "targets": [
    {
      "name": $(json_string "$(basename "${RESOLVED_PROJECT_DIR}")"),
      "path": $(json_string "${RESOLVED_PROJECT_DIR}"),
      "exitCode": ${EXIT_CODE},
      "status": $([[ "${EXIT_CODE}" -eq 0 ]] && printf '"passed"' || printf '"failed"')
    }
  ]
}
EOF
)"
  write_json_file "${SUMMARY_JSON_PATH}" "${SUMMARY_CONTENT}"

  if [[ "${EXIT_CODE}" -ne 0 ]]; then
    echo "BCC runner failed for ${RESOLVED_PROJECT_DIR} with exit code ${EXIT_CODE}"
    exit "${EXIT_CODE}"
  fi
  exit 0
fi

pass=0
fail=0
PASSING_PROJECTS=()
FAILING_PROJECTS=()
TARGET_SUMMARIES=()

echo "Running backward compatibility checks for ${#PROJECTS[@]} projects"
echo

for project in "${PROJECTS[@]}"; do
  project_path="${SCRIPT_DIR}/${project}"
  echo "=== ${project} ==="
  echo "Runner: ${SCRIPT_DIR}/project-bcc-report.sh"
  if run_bcc_for_project "${project_path}"; then
    exit_code=0
    pass=$((pass + 1))
    PASSING_PROJECTS+=("${project}")
    TARGET_SUMMARIES+=("{\"name\":$(json_string "${project}"),\"path\":$(json_string "$(cd "${project_path}" && pwd)"),\"exitCode\":0,\"status\":\"passed\"}")
  else
    exit_code=$?
    fail=$((fail + 1))
    FAILING_PROJECTS+=("${project}")
    TARGET_SUMMARIES+=("{\"name\":$(json_string "${project}"),\"path\":$(json_string "$(cd "${project_path}" && pwd)"),\"exitCode\":${exit_code},\"status\":\"failed\"}")
    echo "BCC runner failed for $(cd "${project_path}" && pwd) with exit code ${exit_code}"
  fi
  echo
done

echo "SUMMARY: PASS=${pass} FAIL=${fail} TOTAL=${#PROJECTS[@]}"
echo "Passing projects:"
if [[ ${#PASSING_PROJECTS[@]} -eq 0 ]]; then
  echo "  (none)"
else
  printf '  - %s\n' "${PASSING_PROJECTS[@]}"
fi

echo "Failing projects:"
if [[ ${#FAILING_PROJECTS[@]} -eq 0 ]]; then
  echo "  (none)"
else
  printf '  - %s\n' "${FAILING_PROJECTS[@]}"
fi

TARGETS_JSON=""
for i in "${!TARGET_SUMMARIES[@]}"; do
  TARGETS_JSON+="${TARGET_SUMMARIES[$i]}"
  if (( i < ${#TARGET_SUMMARIES[@]} - 1 )); then
    TARGETS_JSON+=","
  fi
done

SUMMARY_CONTENT="$(cat <<EOF
{
  "mode": "all",
  "total": ${#PROJECTS[@]},
  "pass": ${pass},
  "fail": ${fail},
  "passingProjects": [$(for i in "${!PASSING_PROJECTS[@]}"; do json_string "${PASSING_PROJECTS[$i]}"; [[ $i -lt $((${#PASSING_PROJECTS[@]} - 1)) ]] && printf ','; done)],
  "failingProjects": [$(for i in "${!FAILING_PROJECTS[@]}"; do json_string "${FAILING_PROJECTS[$i]}"; [[ $i -lt $((${#FAILING_PROJECTS[@]} - 1)) ]] && printf ','; done)],
  "targets": [${TARGETS_JSON}]
}
EOF
)"
write_json_file "${SUMMARY_JSON_PATH}" "${SUMMARY_CONTENT}"

if [[ ${fail} -ne 0 ]]; then
  exit 1
fi
