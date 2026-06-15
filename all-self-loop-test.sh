#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_RUNNER="${SCRIPT_DIR}/project-self-loop-test.sh"
FEDERATED_PROVIDER_PROJECTS=(
  "catalog-service"
  "pricing-service"
  "notification-service"
  "web-bff"
)

if [[ ! -x "${PROJECT_RUNNER}" ]]; then
  echo "Missing or non-executable script: ${PROJECT_RUNNER}" >&2
  exit 1
fi

run_project_script_from_dir() {
  local project_path="$1"
  local script_name="$2"

  bash -c "cd \"$1\" && bash \"./$2\"" _ "${project_path}" "${script_name}"
}

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

pass=0
fail=0
PASSING_PROJECTS=()
FAILING_PROJECTS=()

# Specmatic filter expressions (from docs: STATUS, PATH, METHOD, PARAMETERS.*, CONTENT-TYPE, etc.)
# The loop intentionally randomizes among valid filters per project so demo runs show different slices
# without producing empty suites from inapplicable filters.
FILTER_CATALOG=(
  "STATUS = '200'"
  "STATUS >= '300'"
  "STATUS >= '400'"
  "(METHOD = 'GET') || (METHOD = 'POST')"
  "(METHOD = 'POST' || METHOD = 'PUT') || STATUS = '200'"
  "!(STATUS = '202')"
  "RESPONSE.CONTENT-TYPE = 'application/json'"
  "REQUEST-BODY.CONTENT-TYPE = 'application/json'"
)

build_allowed_filter_pool() {
  local project="$1"
  case "$project" in
    analytics-pipeline)
      printf '%s\n' \
        "STATUS = '200'" \
        "(METHOD = 'GET') || (METHOD = 'POST')" \
        "RESPONSE.CONTENT-TYPE = 'application/json'"
      ;;
    customer-service)
      printf '%s\n' \
        "STATUS = '200'" \
        "(METHOD = 'GET') || (METHOD = 'POST')" \
        "(METHOD = 'POST' || METHOD = 'PUT') || STATUS = '200'" \
        "RESPONSE.CONTENT-TYPE = 'application/json'" \
        "REQUEST-BODY.CONTENT-TYPE = 'application/json'"
      ;;
    inventory-projection-service)
      printf '%s\n' \
        "STATUS = '200'" \
        "(METHOD = 'GET') || (METHOD = 'POST')" \
        "RESPONSE.CONTENT-TYPE = 'application/json'"
      ;;
    inventory-sync-service)
      printf '%s\n' \
        "(METHOD = 'GET') || (METHOD = 'POST')" \
        "(METHOD = 'POST' || METHOD = 'PUT') || STATUS = '200'" \
        "RESPONSE.CONTENT-TYPE = 'application/json'" \
        "REQUEST-BODY.CONTENT-TYPE = 'application/json'"
      ;;
    notification-service)
      printf '%s\n' \
        "STATUS = '200'" \
        "(METHOD = 'GET') || (METHOD = 'POST')" \
        "(METHOD = 'POST' || METHOD = 'PUT') || STATUS = '200'" \
        "RESPONSE.CONTENT-TYPE = 'application/json'" \
        "REQUEST-BODY.CONTENT-TYPE = 'application/json'"
      ;;
    returns-service)
      printf '%s\n' \
        "STATUS = '200'" \
        "(METHOD = 'GET') || (METHOD = 'POST')" \
        "(METHOD = 'POST' || METHOD = 'PUT') || STATUS = '200'" \
        "RESPONSE.CONTENT-TYPE = 'application/json'" \
        "REQUEST-BODY.CONTENT-TYPE = 'application/json'"
      ;;
    shipping-service)
      printf '%s\n' \
        "STATUS = '200'" \
        "(METHOD = 'GET') || (METHOD = 'POST')" \
        "(METHOD = 'POST' || METHOD = 'PUT') || STATUS = '200'" \
        "RESPONSE.CONTENT-TYPE = 'application/json'" \
        "REQUEST-BODY.CONTENT-TYPE = 'application/json'"
      ;;
    *)
      printf '%s\n' "${FILTER_CATALOG[@]}"
      ;;
  esac
}

echo "Available random Specmatic FILTER expressions:"
for i in "${!FILTER_CATALOG[@]}"; do
  printf '  %d. %s\n' "$((i + 1))" "${FILTER_CATALOG[$i]}"
done
echo

echo "Running self loop tests for ${#PROJECTS[@]} projects"
echo

(
  cd central-contract-repository
  ./ci.sh
)

for project in "${FEDERATED_PROVIDER_PROJECTS[@]}"; do
  project_path="${SCRIPT_DIR}/${project}"
  central_repo_script="${project_path}/ci_central_repo_report.sh"

  if [[ ! -f "${central_repo_script}" ]]; then
    continue
  fi

  echo "=== ${project} central repo report ==="
  echo "Runner: ${project}/ci_central_repo_report.sh"
  run_project_script_from_dir "${project_path}" "ci_central_repo_report.sh"
  echo
done

if [[ -n "${SEND_REPORT:-}" ]]; then
  echo "Waiting 120 seconds for central repo builds to be processed before running service builds..."
  sleep 120
  echo
fi

for project in "${PROJECTS[@]}"; do
  project_path="${SCRIPT_DIR}/${project}"
  project_ci_script="${project_path}/ci.sh"
  mapfile -t PROJECT_FILTER_POOL < <(build_allowed_filter_pool "${project}")
  FILTER_INDEX=$((RANDOM % ${#PROJECT_FILTER_POOL[@]}))
  PROJECT_FILTER="${PROJECT_FILTER_POOL[$FILTER_INDEX]}"
  echo "=== ${project} ==="
  echo "FILTER: ${PROJECT_FILTER}"
  if [[ -f "${project_ci_script}" ]]; then
    echo "Runner: ${project}/ci.sh"
    run_cmd=(run_project_script_from_dir "${project_path}" "ci.sh")
  else
    echo "Runner: ${PROJECT_RUNNER}"
    run_cmd=("${PROJECT_RUNNER}" "${project_path}")
  fi

  if FILTER="${PROJECT_FILTER}" "${run_cmd[@]}"; then
    pass=$((pass + 1))
    PASSING_PROJECTS+=("${project}")
  else
    fail=$((fail + 1))
    FAILING_PROJECTS+=("${project}")
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

if [[ ${fail} -ne 0 ]]; then
  exit 1
fi
