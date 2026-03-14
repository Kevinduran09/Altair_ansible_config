#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Uso: %s --event <evento> --project <proyecto> --run-url <url> [opciones]\n' "$0"
  printf 'Opciones:\n'
  printf '  --tag <tag>                (default: n/a)\n'
  printf '  --status <estado>          (default: info) [success|failed|started|warning|info]\n'
  printf '  --pr-url <url_pr>          (default: vacio)\n'
  printf '  --actor <actor>            (default: github-actions[bot])\n'
  printf '  --environment <env>        (default: altair)\n'
  printf '  --extra <texto>            (default: vacio)\n'
  printf '  --webhook-url <url>        (default: DISCORD_WEBHOOK_URL)\n'
  printf '  --dry-run                  imprime payload y no envia\n'
  printf '  -h, --help                 muestra ayuda\n'
}

event=""
project=""
tag="n/a"
status="info"
run_url=""
pr_url=""
actor="github-actions[bot]"
environment="altair"
extra=""
webhook_url="${DISCORD_WEBHOOK_URL:-}"
dry_run="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)
      event="${2:-}"
      shift 2
      ;;
    --project)
      project="${2:-}"
      shift 2
      ;;
    --tag)
      tag="${2:-}"
      shift 2
      ;;
    --status)
      status="${2:-}"
      shift 2
      ;;
    --run-url)
      run_url="${2:-}"
      shift 2
      ;;
    --pr-url)
      pr_url="${2:-}"
      shift 2
      ;;
    --actor)
      actor="${2:-}"
      shift 2
      ;;
    --environment)
      environment="${2:-}"
      shift 2
      ;;
    --extra)
      extra="${2:-}"
      shift 2
      ;;
    --webhook-url)
      webhook_url="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR argumento desconocido: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$event" || -z "$project" || -z "$run_url" ]]; then
  printf 'ERROR faltan argumentos requeridos (--event, --project, --run-url)\n' >&2
  usage
  exit 1
fi

if [[ "$dry_run" != "true" && -z "$webhook_url" ]]; then
  printf 'ERROR webhook no definido. Usa --webhook-url o DISCORD_WEBHOOK_URL\n' >&2
  exit 2
fi

case "$status" in
  success)
    color=5763719
    ;;
  failed)
    color=15548997
    ;;
  started)
    color=15105570
    ;;
  warning)
    color=16776960
    ;;
  *)
    color=3447003
    ;;
esac

title="Altair CI/CD | ${event}"
description="Evento ${event} para ${project} en ${environment}"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

payload="$({
  python3 - "$title" "$description" "$project" "$event" "$tag" "$actor" "$run_url" "$pr_url" "$environment" "$extra" "$timestamp" "$color" <<'PY'
import json
import sys

title = sys.argv[1]
description = sys.argv[2]
project = sys.argv[3]
event = sys.argv[4]
tag = sys.argv[5]
actor = sys.argv[6]
run_url = sys.argv[7]
pr_url = sys.argv[8]
environment = sys.argv[9]
extra = sys.argv[10]
timestamp = sys.argv[11]
color = int(sys.argv[12])

pr_value = f"[Ver PR]({pr_url})" if pr_url else "N/A"
extra_value = extra if extra else "N/A"

payload = {
    "embeds": [
        {
            "title": title,
            "description": description,
            "color": color,
            "fields": [
                {"name": "Proyecto", "value": project, "inline": True},
                {"name": "Evento", "value": event, "inline": True},
                {"name": "Tag", "value": tag, "inline": True},
                {"name": "Entorno", "value": environment, "inline": True},
                {"name": "Actor", "value": actor, "inline": True},
                {"name": "Run", "value": f"[Ver workflow]({run_url})", "inline": False},
                {"name": "PR", "value": pr_value, "inline": False},
                {"name": "Extra", "value": extra_value, "inline": False},
            ],
            "footer": {"text": "Altair Notifications"},
            "timestamp": timestamp,
        }
    ]
}

print(json.dumps(payload, ensure_ascii=True))
PY
})"

if [[ "$dry_run" == "true" ]]; then
  printf '%s\n' "$payload"
  exit 0
fi

curl -sS -X POST "$webhook_url" \
  -H "Content-Type: application/json" \
  --data "$payload"

printf 'OK notificacion enviada: event=%s project=%s status=%s\n' "$event" "$project" "$status"
