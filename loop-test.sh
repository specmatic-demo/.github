#!/usr/bin/env bash
set -euo pipefail

CONTRACTS_DIR="."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./specmatic-loop-common.sh
source "${SCRIPT_DIR}/specmatic-loop-common.sh"

init_specmatic_cmd

mapfile -t SPEC_FILES < <(find "$CONTRACTS_DIR" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.proto" -o -name "*.graphql" \) | sort)

if [[ ${#SPEC_FILES[@]} -eq 0 ]]; then
  echo "No spec files found under $CONTRACTS_DIR"
  exit 1
fi

pass=0
fail=0
current_mock_pid=""

init_colors

cleanup() {
  trap - EXIT INT TERM
  stop_background_process "${current_mock_pid}"
}
trap cleanup EXIT INT TERM

echo "Running ${#SPEC_FILES[@]} spec files"
echo

for spec in "${SPEC_FILES[@]}"; do
  echo "${C_BLUE}=== $spec ===${C_RESET}"
  "${SPECMATIC_CMD[@]}" mock "$spec" \
    > >(prefix_output "$C_CYAN" "mock") \
    2> >(prefix_output "$C_CYAN" "mock" >&2) &
  current_mock_pid=$!

  sleep 3

  if "${SPECMATIC_CMD[@]}" test "$spec" 2>&1 | prefix_output "$C_BLUE" "test"; then
    test_exit=0
  else
    test_exit=$?
  fi

  stop_background_process "$current_mock_pid"
  current_mock_pid=""

  if [[ $test_exit -eq 0 ]]; then
    echo "${C_GREEN}RESULT: PASS${C_RESET}"
    pass=$((pass + 1))
  else
    echo "${C_RED}RESULT: FAIL (exit $test_exit)${C_RESET}"
    fail=$((fail + 1))
  fi

  echo
done

echo "${C_YELLOW}SUMMARY: PASS=$pass FAIL=$fail TOTAL=${#SPEC_FILES[@]}${C_RESET}"

if [[ $fail -ne 0 ]]; then
  exit 1
fi
