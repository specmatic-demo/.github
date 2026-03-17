#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_RUNNER="${SCRIPT_DIR}/project-self-loop-test.sh"

if [[ ! -x "${PROJECT_RUNNER}" ]]; then
  echo "Missing or non-executable script: ${PROJECT_RUNNER}" >&2
  exit 1
fi

mapfile -t PROJECTS < <(
  find "${SCRIPT_DIR}" -mindepth 1 -maxdepth 1 -type d \
    ! -name ".*" \
    -exec test -f "{}/specmatic.yaml" \; \
    -print \
    | xargs -n1 basename \
    | sort
)

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
  echo "No project directories found with specmatic.yaml."
  exit 1
fi

pass=0
fail=0
PASSING_PROJECTS=()
FAILING_PROJECTS=()

# Specmatic filter expressions (from docs: STATUS, PATH, METHOD, PARAMETERS.*, CONTENT-TYPE, etc.)
# Keep these intentionally selective (no catch-all) so random selection does not exercise everything.
FILTER_POOL=(
  "STATUS = '200'"
  "STATUS >= '300'"
  "STATUS >= '400'"
  "(METHOD = 'GET') || (METHOD = 'POST')"
  "(METHOD = 'POST' || METHOD = 'PUT') || STATUS = '200'"
  "!(STATUS = '202')"
  "RESPONSE.CONTENT-TYPE = 'application/json'"
  "REQUEST-BODY.CONTENT-TYPE = 'application/json'"
)

echo "Available random Specmatic FILTER expressions:"
for i in "${!FILTER_POOL[@]}"; do
  printf '  %d. %s\n' "$((i + 1))" "${FILTER_POOL[$i]}"
done
echo

echo "Running self loop tests for ${#PROJECTS[@]} projects"
echo

for project in "${PROJECTS[@]}"; do
  project_path="${SCRIPT_DIR}/${project}"
  FILTER_INDEX=$((RANDOM % ${#FILTER_POOL[@]}))
  PROJECT_FILTER="${FILTER_POOL[$FILTER_INDEX]}"
  echo "=== ${project} ==="
  echo "FILTER: ${PROJECT_FILTER}"
  if FILTER="${PROJECT_FILTER}" "${PROJECT_RUNNER}" "${project_path}"; then
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
