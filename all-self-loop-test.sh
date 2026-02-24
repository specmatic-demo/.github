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

echo "Running self loop tests for ${#PROJECTS[@]} projects"
echo

for project in "${PROJECTS[@]}"; do
  project_path="${SCRIPT_DIR}/${project}"
  echo "=== ${project} ==="
  if "${PROJECT_RUNNER}" "${project_path}"; then
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
