#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Uso: %s <app> <sha|tag> [archivo]\n' "$0"
  printf 'Ejemplo: %s portfolio a1b2c3d4e5f6 inventory/group_vars/all/apps.yml\n' "$0"
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 1
fi

app_name="$1"
input_tag="$2"
target_file="${3:-inventory/group_vars/all/apps.yml}"

if [[ ! -f "$target_file" ]]; then
  printf 'ERROR archivo no existe: %s\n' "$target_file" >&2
  exit 3
fi

if [[ "$input_tag" == sha-* ]]; then
  image_tag="$input_tag"
else
  image_tag="sha-$input_tag"
fi

python3 - "$target_file" "$app_name" "$image_tag" <<'PY'
import pathlib
import re
import sys

file_path = pathlib.Path(sys.argv[1])
app_name = sys.argv[2]
new_tag = sys.argv[3]

content = file_path.read_text(encoding="utf-8")

block_pattern = re.compile(
    rf"(^\s{{2}}{re.escape(app_name)}:\s*\n(?:^\s{{4}}.*\n)*)",
    flags=re.MULTILINE,
)
block_match = block_pattern.search(content)
if not block_match:
    print(f"ERROR app no encontrada: {app_name}", file=sys.stderr)
    sys.exit(2)

block = block_match.group(1)
tag_pattern = re.compile(r'^(\s{4}image_tag:\s*")([^"]*)("\s*)$', flags=re.MULTILINE)
tag_match = tag_pattern.search(block)

if tag_match:
    old_tag = tag_match.group(2)
    if old_tag == new_tag:
        print(f"NO_CHANGES app={app_name} tag={new_tag}")
        sys.exit(0)
    updated_block = tag_pattern.sub(rf'\1{new_tag}\3', block, count=1)
else:
    old_tag = ""
    if not block.endswith("\n"):
        block += "\n"
    updated_block = block + f'    image_tag: "{new_tag}"\n'

updated_content = content[:block_match.start(1)] + updated_block + content[block_match.end(1):]
file_path.write_text(updated_content, encoding="utf-8")
print(f"UPDATED app={app_name} old={old_tag or '<none>'} new={new_tag} file={file_path}")
PY
