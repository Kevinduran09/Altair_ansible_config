#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Uso: %s <app_tag> [limit] [playbook] [args_extra...]\n' "$0"
  printf 'Ejemplo: %s portfolio target playbooks/apps.yml -vv\n' "$0"
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

app_tag="$1"
limit_host="${2:-target}"
playbook_file="${3:-playbooks/apps.yml}"

if [[ ! -f "$playbook_file" ]]; then
  printf 'ERROR playbook no existe: %s\n' "$playbook_file" >&2
  exit 3
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  printf 'ERROR ansible-playbook no está disponible en PATH\n' >&2
  exit 8
fi

extra_args=()
if [[ $# -gt 3 ]]; then
  extra_args=("${@:4}")
fi

printf 'Deploy app=%s limit=%s playbook=%s\n' "$app_tag" "$limit_host" "$playbook_file"
ansible-playbook "$playbook_file" --limit "$limit_host" --tags "$app_tag" "${extra_args[@]}"
