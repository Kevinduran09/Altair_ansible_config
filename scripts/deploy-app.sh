#!/usr/bin/env bash
set -euo pipefail
if [[ $# -eq 0 || ${1:-} == --help || ${1:-} == -h ]]; then
  printf 'Usage: %s <app|app,app|all|netdata> [limit] [playbook] [ansible args...]\n' "$0"
  exit 0
fi
cd "$(dirname "$0")/.."
app="$1"
limit_host="${2:-target}"
playbook="${3:-playbooks/apps.yml}"
extra_args=("${@:4}")
if [[ "$app" == netdata ]]; then
  exec ansible-playbook playbooks/netdata.yml --limit "$limit_host" "${extra_args[@]}"
fi
case "$playbook" in
  playbooks/apps.yml|playbooks/portfolio.yml|playbooks/uptimekuma.yml) ;;
  *) printf 'Unsupported app playbook: %s\n' "$playbook" >&2; exit 2 ;;
esac
selection="$(python3 scripts/app_catalog.py select "$app")"
exec ansible-playbook playbooks/apps.yml --limit "$limit_host" --extra-vars "$selection" "${extra_args[@]}"
