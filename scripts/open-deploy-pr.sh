#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 2 || $# -gt 4 ]]; then
  printf 'Usage: %s <app> <sha|tag> [base_branch] [file]\n' "$0" >&2
  exit 2
fi
cd "$(dirname "$0")/.."
app="$1"
tag="$2"
base="${3:-main}"
file="${4:-inventory/group_vars/all/apps.yml}"
if [[ -n "$(git status --porcelain)" ]]; then
  printf 'A clean working tree is required.\n' >&2
  exit 2
fi
gh auth status >/dev/null
git fetch origin "$base"
git switch --detach "origin/$base"
output="$(scripts/update-app-tag.sh "$app" "$tag" "$file")"
printf '%s\n' "$output"
if [[ "$output" == NO_CHANGES* ]]; then exit 0; fi
branch="deploy/$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
git switch -c "$branch"
git add -- "$file"
git -c user.name="${GIT_BOT_NAME:-altair-bot}" \
  -c user.email="${GIT_BOT_EMAIL:-altair-bot@users.noreply.github.com}" \
  commit -m "deploy($app): update image to $tag"
git push -u origin "$branch"
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
printf 'Update the image reference for %s to %s. CI validates the catalog and Compose configuration before merge.\n' "$app" "$tag" > "$body_file"
gh pr create --base "$base" --head "$branch" --title "deploy($app): update image to $tag" --body-file "$body_file"
