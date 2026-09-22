#!/usr/bin/env bash

init_specmatic_cmd() {
  if command -v specmatic-enterprise >/dev/null 2>&1; then
    SPECMATIC_CMD=(specmatic-enterprise)
    return
  fi

  local jar_path="${HOME}/.specmatic/specmatic-enterprise.jar"
  if [[ ! -f "$jar_path" ]]; then
    echo "specmatic-enterprise not found in PATH and jar not found at $jar_path" >&2
    exit 1
  fi

  local java_opts="${JAVA_OPTS:-}"
  # shellcheck disable=SC2206
  SPECMATIC_CMD=(java -Djava.awt.headless=true $java_opts -jar "$jar_path")
}

init_colors() {
  if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
  else
    C_RESET=''
    C_BLUE=''
    C_CYAN=''
    C_GREEN=''
    C_RED=''
    C_YELLOW=''
  fi
}

prefix_output() {
  local color="$1"
  local label="$2"
  sed -u "s/^/${color}[${label}]${C_RESET} /"
}

stop_background_process() {
  local pid="${1:-}"
  local graceful_signal="${2:-TERM}"
  if [[ -n "$pid" ]]; then
    terminate_process_tree "$pid" "$graceful_signal"

    local deadline=$((SECONDS + 30))
    while process_tree_running "$pid" && (( SECONDS < deadline )); do
      sleep 0.2
    done

    if process_tree_running "$pid"; then
      terminate_process_tree "$pid" KILL
    fi

    wait "$pid" >/dev/null 2>&1 || true
  fi
}

process_tree_running() {
  local pid="$1"
  local child_pid
  local process_running=1

  if kill -0 "$pid" >/dev/null 2>&1; then
    process_running=0
  fi

  while IFS= read -r child_pid; do
    [[ -n "$child_pid" ]] || continue
    if process_tree_running "$child_pid"; then
      return 0
    fi
  done < <(pgrep -P "$pid" 2>/dev/null || true)

  return "$process_running"
}

terminate_process_tree() {
  local pid="$1"
  local signal="$2"
  local child_pid

  while IFS= read -r child_pid; do
    [[ -n "$child_pid" ]] || continue
    terminate_process_tree "$child_pid" "$signal"
  done < <(pgrep -P "$pid" 2>/dev/null || true)

  kill -"$signal" "$pid" >/dev/null 2>&1 || true
}
