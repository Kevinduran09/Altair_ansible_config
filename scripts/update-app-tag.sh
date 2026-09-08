#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 2 || $# -gt 3 ]]; then
  printf 'Usage: %s <app> <sha|tag> [file]\n' "$0" >&2
  exit 2
fi
exec python3 "$(dirname "$0")/app_catalog.py" update "$1" "$2" --file "${3:-inventory/group_vars/all/apps.yml}"
