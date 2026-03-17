#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <status|diff|add|commit|push> [args]" >&2
  exit 1
fi

operation="$1"
case "$operation" in
  status|diff|add|commit|push) ;;
  *)
    echo "Unsupported operation: $operation" >&2
    echo "Usage: $0 <status|diff|add|commit|push> [args]" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

repos=(".")
while IFS= read -r git_dir; do
  repo_dir="$(dirname "$git_dir")"
  if [[ "$repo_dir" != "." ]]; then
    repos+=("$repo_dir")
  fi
done < <(find . -mindepth 2 -maxdepth 2 -name .git -type d | sort)

for repo in "${repos[@]}"; do
  output=$(git -C "$repo" "$operation" "${@:2}" 2>&1)

  # If clean working tree (for status), suppress entirely
  if [[ "$operation" == "status" && "$output" == *"nothing to commit, working tree clean"* ]]; then
    filtered=""
  else
    filtered="$output"
  fi

  if [[ -n "$filtered" ]]; then
    if [[ "$repo" == "." ]]; then
      echo "===== . ====="
    else
      echo "===== $repo ====="
    fi
    echo "$filtered"
    echo
  fi
done
