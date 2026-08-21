#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREPARE_SCRIPT="${SCRIPT_DIR}/prepare-random-bcc-change.sh"
BCC_SCRIPT="${SCRIPT_DIR}/project-bcc-report.sh"
SEND_SCRIPT="${SCRIPT_DIR}/send-all-reports.sh"

MODE="Random"
SELECTION="PerSpec"
PROJECT_DIR=""
SEND_REPORTS="false"
KEEP_CHANGES="false"
FORCE="false"
SUMMARY_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --selection)
      SELECTION="$2"
      shift 2
      ;;
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --send-reports)
      SEND_REPORTS="true"
      shift
      ;;
    --keep-changes)
      KEEP_CHANGES="true"
      shift
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    --summary-path)
      SUMMARY_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

for required_script in "${PREPARE_SCRIPT}" "${BCC_SCRIPT}"; do
  if [[ ! -f "${required_script}" ]]; then
    echo "Missing script: ${required_script}" >&2
    exit 1
  fi
done

WORKFLOW_START="$(date -Iseconds)"
OVERALL_EXIT_CODE=0
WORKFLOW_FAILED="false"
PREPARE_JSON_PATH="$(mktemp)"
BCC_SUMMARY_PATH="$(mktemp)"
RESTORE_JSON_PATH="$(mktemp)"
trap 'rm -f "${PREPARE_JSON_PATH}" "${BCC_SUMMARY_PATH}" "${RESTORE_JSON_PATH}"' EXIT

if [[ -n "${PROJECT_DIR}" ]]; then
  RESOLVED_PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"
else
  RESOLVED_PROJECT_DIR=""
fi

json_get() {
  local file_path="$1"
  local expression="$2"
  node -e "const fs=require('fs'); const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); const value=(function(){ return ${expression}; })(); if (value === undefined || value === null) { process.exit(0); } if (typeof value === 'object') { process.stdout.write(JSON.stringify(value)); } else { process.stdout.write(String(value)); }" "${file_path}"
}

write_workflow_summary() {
  local output_path="$1"
  local prepare_file="$2"
  local bcc_file="$3"
  local restore_file="$4"

  [[ -n "${output_path}" ]] || return 0

  mkdir -p "$(dirname "${output_path}")"
  node - "${output_path}" "${prepare_file}" "${bcc_file}" "${restore_file}" <<'NODE'
const fs = require("fs");
const path = require("path");

const [outputPath, preparePath, bccPath, restorePath] = process.argv.slice(2);
const readJson = (filePath) => {
  if (!filePath || !fs.existsSync(filePath) || fs.statSync(filePath).size === 0) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
};

const summary = {
  startedAt: process.env.WORKFLOW_START,
  completedAt: new Date().toISOString(),
  mode: process.env.MODE,
  selection: process.env.SELECTION,
  projectDir: process.env.RESOLVED_PROJECT_DIR || null,
  sendReports: process.env.SEND_REPORTS === "true",
  keepChanges: process.env.KEEP_CHANGES === "true",
  exitCode: Number(process.env.OVERALL_EXIT_CODE || "0"),
  prepare: readJson(preparePath),
  bcc: readJson(bccPath),
  send: JSON.parse(process.env.SEND_SUMMARY_JSON),
  restore: JSON.parse(process.env.RESTORE_SUMMARY_JSON)
};

fs.writeFileSync(outputPath, JSON.stringify(summary, null, 2));
NODE
}

echo "=== Preparing Changes ==="
PREPARE_ARGS=(--mode "${MODE}" --selection "${SELECTION}")
if [[ -n "${RESOLVED_PROJECT_DIR}" ]]; then
  PREPARE_ARGS+=(--search-root "${RESOLVED_PROJECT_DIR}")
fi
if [[ "${FORCE}" == "true" ]]; then
  PREPARE_ARGS+=(--force)
fi

if "${PREPARE_SCRIPT}" "${PREPARE_ARGS[@]}" >"${PREPARE_JSON_PATH}"; then
  PREPARE_SELECTION_COUNT="$(json_get "${PREPARE_JSON_PATH}" "data.selectionCount ?? 0")"
  echo "Changed specs: ${PREPARE_SELECTION_COUNT}"

  echo
  echo "=== Running BCC ==="
  BCC_ARGS=(--summary-json-path "${BCC_SUMMARY_PATH}")
  if [[ -n "${RESOLVED_PROJECT_DIR}" ]]; then
    BCC_ARGS=(--project-dir "${RESOLVED_PROJECT_DIR}" --summary-json-path "${BCC_SUMMARY_PATH}")
  fi

  if "${BCC_SCRIPT}" "${BCC_ARGS[@]}"; then
    BCC_EXIT_CODE=0
  else
    BCC_EXIT_CODE=$?
    WORKFLOW_FAILED="true"
    OVERALL_EXIT_CODE="${BCC_EXIT_CODE}"
    echo "Backward compatibility checks failed with exit code ${OVERALL_EXIT_CODE}"
  fi

  if [[ "${SEND_REPORTS}" == "true" ]]; then
    if [[ ! -f "${SEND_SCRIPT}" ]]; then
      echo "Missing script: ${SEND_SCRIPT}" >&2
      exit 1
    fi

    echo
    echo "=== Sending Reports ==="
    if [[ -n "${RESOLVED_PROJECT_DIR}" ]]; then
      if "${SEND_SCRIPT}" "${RESOLVED_PROJECT_DIR}"; then
        SEND_EXIT_CODE=0
      else
        SEND_EXIT_CODE=$?
      fi
    else
      if "${SEND_SCRIPT}"; then
        SEND_EXIT_CODE=0
      else
        SEND_EXIT_CODE=$?
      fi
    fi

    if [[ "${SEND_EXIT_CODE}" -ne 0 ]]; then
      WORKFLOW_FAILED="true"
      OVERALL_EXIT_CODE="${SEND_EXIT_CODE}"
      echo "Report sending failed with exit code ${OVERALL_EXIT_CODE}"
      SEND_STATUS="failed"
    else
      SEND_STATUS="passed"
    fi
  else
    SEND_EXIT_CODE=""
    SEND_STATUS="skipped"
  fi
else
  PREPARE_EXIT_CODE=$?
  WORKFLOW_FAILED="true"
  OVERALL_EXIT_CODE="${PREPARE_EXIT_CODE}"
  echo "Randomized change preparation failed with exit code ${OVERALL_EXIT_CODE}"
  SEND_EXIT_CODE=""
  SEND_STATUS="not-run"
fi

echo
echo "=== Restoring Originals ==="
if [[ "${KEEP_CHANGES}" != "true" ]]; then
  if "${PREPARE_SCRIPT}" --restore >"${RESTORE_JSON_PATH}"; then
    RESTORE_SKIPPED="$(json_get "${RESTORE_JSON_PATH}" "Boolean(data.skipped)")"
    if [[ "${RESTORE_SKIPPED}" == "true" ]]; then
      RESTORE_STATUS="skipped"
    else
      RESTORE_STATUS="restored"
    fi
    RESTORE_EXIT_CODE=0
  else
    RESTORE_EXIT_CODE=$?
    RESTORE_STATUS="failed"
    if [[ "${WORKFLOW_FAILED}" != "true" ]]; then
      OVERALL_EXIT_CODE="${RESTORE_EXIT_CODE}"
    fi
  fi
else
  RESTORE_EXIT_CODE=""
  RESTORE_STATUS="kept"
  printf '%s\n' '{"restoredFiles":[]}' >"${RESTORE_JSON_PATH}"
fi

if [[ -f "${PREPARE_JSON_PATH}" && -s "${PREPARE_JSON_PATH}" ]]; then
  CHANGED_COUNT="$(json_get "${PREPARE_JSON_PATH}" "data.selectionCount ?? 0")"
else
  CHANGED_COUNT=0
fi

if [[ -f "${BCC_SUMMARY_PATH}" && -s "${BCC_SUMMARY_PATH}" ]]; then
  BCC_TOTAL="$(json_get "${BCC_SUMMARY_PATH}" "data.total ?? 0")"
  BCC_PASS="$(json_get "${BCC_SUMMARY_PATH}" "data.pass ?? 0")"
  BCC_FAIL="$(json_get "${BCC_SUMMARY_PATH}" "data.fail ?? 0")"
else
  BCC_TOTAL=0
  BCC_PASS=0
  BCC_FAIL=0
fi

SEND_SUMMARY_JSON="$(node -e 'const enabled=process.argv[1]==="true"; const status=process.argv[2]; const exitCode=process.argv[3]; const data={enabled,status}; if (exitCode) data.exitCode=Number(exitCode); process.stdout.write(JSON.stringify(data));' "${SEND_REPORTS}" "${SEND_STATUS}" "${SEND_EXIT_CODE}")"
RESTORE_SUMMARY_JSON="$(node -e 'const attempted=process.argv[1]==="true"; const status=process.argv[2]; const exitCode=process.argv[3]; const restoredFiles=JSON.parse(process.argv[4]); const data={attempted,status,restoredFiles}; if (exitCode) data.exitCode=Number(exitCode); process.stdout.write(JSON.stringify(data));' "$([[ "${KEEP_CHANGES}" == "true" ]] && echo false || echo true)" "${RESTORE_STATUS}" "${RESTORE_EXIT_CODE}" "$(json_get "${RESTORE_JSON_PATH}" "data.restoredFiles ?? []")")"

export WORKFLOW_START MODE SELECTION RESOLVED_PROJECT_DIR SEND_REPORTS KEEP_CHANGES OVERALL_EXIT_CODE SEND_SUMMARY_JSON RESTORE_SUMMARY_JSON
write_workflow_summary "${SUMMARY_PATH}" "${PREPARE_JSON_PATH}" "${BCC_SUMMARY_PATH}" "${RESTORE_JSON_PATH}"

echo
echo "=== Workflow Summary ==="
echo "Changed specs: ${CHANGED_COUNT}"
echo "BCC targets: ${BCC_TOTAL} total, ${BCC_PASS} passed, ${BCC_FAIL} failed"
if [[ "${SEND_REPORTS}" == "true" ]]; then
  echo "Report sending: ${SEND_STATUS}"
fi
echo "Restore: ${RESTORE_STATUS}"
if [[ -n "${SUMMARY_PATH}" ]]; then
  echo "Summary file: ${SUMMARY_PATH}"
fi

exit "${OVERALL_EXIT_CODE}"
