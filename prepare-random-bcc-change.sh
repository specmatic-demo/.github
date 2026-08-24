#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_SCRIPT="${SCRIPT_DIR}/scripts/random-openapi-bcc-change.mjs"

MODE="Random"
SELECTION="Single"
SEARCH_ROOT="."
DRY_RUN="false"
RESTORE="false"
FORCE="false"
INDEX="-1"

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
    --search-root)
      SEARCH_ROOT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --restore)
      RESTORE="true"
      shift
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    --index)
      INDEX="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${NODE_SCRIPT}" ]]; then
  echo "Missing script: ${NODE_SCRIPT}" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required to prepare randomized OpenAPI BCC changes." >&2
  exit 1
fi

ARGS=("${NODE_SCRIPT}")

if [[ "${RESTORE}" == "true" ]]; then
  ARGS+=("restore")
else
  if [[ "${SEARCH_ROOT}" = /* || "${SEARCH_ROOT}" =~ ^[A-Za-z]:[\\/] ]]; then
    RESOLVED_SEARCH_ROOT="${SEARCH_ROOT}"
  else
    RESOLVED_SEARCH_ROOT="${SCRIPT_DIR}/${SEARCH_ROOT}"
  fi

  ARGS+=(
    "apply"
    "--search-root" "${RESOLVED_SEARCH_ROOT}"
    "--mode" "$(printf '%s' "${MODE}" | tr '[:upper:]' '[:lower:]')"
    "--selection" "$(printf '%s' "${SELECTION}" | tr '[:upper:]' '[:lower:]')"
  )

  if [[ "${DRY_RUN}" == "true" ]]; then
    ARGS+=("--dry-run")
  fi

  if [[ "${FORCE}" == "true" ]]; then
    ARGS+=("--force")
  fi

  if [[ "${INDEX}" -ge 0 ]]; then
    ARGS+=("--index" "${INDEX}")
  fi
fi

node "${ARGS[@]}"
exit_code=$?
if [[ "${exit_code}" -ne 0 ]]; then
  echo "Randomized OpenAPI BCC preparation failed with exit code ${exit_code}" >&2
  exit "${exit_code}"
fi
