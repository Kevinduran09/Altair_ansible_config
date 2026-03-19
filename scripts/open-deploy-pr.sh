#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Uso: %s <app> <sha|tag> [base_branch] [archivo]\n' "$0"
  printf 'Ejemplo: %s portfolio a1b2c3d4e5f6 main inventory/group_vars/all/apps.yml\n' "$0"
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 || $# -gt 4 ]]; then
  usage
  exit 1
fi

app_name="$1"
input_tag="$2"
base_branch="${3:-main}"
target_file="${4:-inventory/group_vars/all/apps.yml}"

if [[ "$input_tag" == sha-* ]]; then
  deploy_tag="$input_tag"
else
  deploy_tag="sha-$input_tag"
fi

short_sha="${deploy_tag#sha-}"
short_sha="${short_sha:0:12}"
branch_name="deploy/${app_name}-sha-${short_sha}"

if ! command -v gh >/dev/null 2>&1; then
  printf 'ERROR gh CLI no está instalado o no está en PATH\n' >&2
  exit 6
fi

if ! gh auth status >/dev/null 2>&1; then
  printf 'ERROR gh no está autenticado. Ejecuta: gh auth login\n' >&2
  exit 6
fi

update_output="$("$(dirname "$0")/update-app-tag.sh" "$app_name" "$deploy_tag" "$target_file")"
printf '%s\n' "$update_output"

if [[ "$update_output" == NO_CHANGES* ]]; then
  printf 'Sin cambios para commitear. No se crea PR.\n'
  exit 0
fi

git checkout -B "$branch_name"
git add "$target_file"

if git diff --cached --quiet; then
  printf 'No hay cambios staged. No se crea PR.\n'
  exit 0
fi

git config user.name "${GIT_BOT_NAME:-altair-bot}"
git config user.email "${GIT_BOT_EMAIL:-altair-bot@users.noreply.github.com}"

commit_msg="deploy(${app_name}): actualizar imagen a ${deploy_tag}"
git commit -m "$commit_msg"
git push -u origin "$branch_name"

existing_pr_url="$(gh pr list \
  --base "$base_branch" \
  --head "$branch_name" \
  --state open \
  --json url \
  --jq '.[0].url // ""')"

if [[ -n "$existing_pr_url" ]]; then
  printf 'PR ya existente: %s\n' "$existing_pr_url"
  exit 0
fi

pr_title="$commit_msg"
pr_body="## Summary
- Actualiza \`apps.${app_name}.image_tag\` a \`${deploy_tag}\`.
- Cambio generado automáticamente para flujo GitOps CD.
"

pr_url="$(gh pr create \
  --base "$base_branch" \
  --head "$branch_name" \
  --title "$pr_title" \
  --body "$pr_body")"

printf 'PR creada: %s\n' "$pr_url"
