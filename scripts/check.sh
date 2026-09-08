#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
repo_root="$PWD"
yamllint .
python3 -m pytest -q tests
for script in scripts/*.sh; do bash -n "$script"; done
# Isolate syntax checking from Vault auto-discovery while using real non-secret vars.
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/group_vars/all"
cp tests/inventory/hosts.yml "$fixture/hosts.yml"
for file in inventory/group_vars/all/*.yml; do
  case "$file" in *vault.yml) continue ;; esac
  cp "$file" "$fixture/group_vars/all/"
done
cp tests/vars.yml "$fixture/group_vars/all/zz-ci.yml"
for playbook in playbooks/*.yml; do
  ansible-playbook -i "$fixture/hosts.yml" "$playbook" --syntax-check
 done
# Lint a temporary copy so ansible-lint never tries to decrypt production inventory.
mkdir -p "$fixture/repo"
cp -R roles playbooks requirements.yml ansible.cfg .ansible-lint .yamllint "$fixture/repo/"
cp -R "$fixture/group_vars" "$fixture/repo/"
cp "$fixture/hosts.yml" "$fixture/repo/hosts.yml"
(
  cd "$fixture/repo"
  ANSIBLE_INVENTORY="$fixture/repo/hosts.yml" ANSIBLE_COLLECTIONS_PATH="$repo_root/.ansible/collections" \
    ansible-lint --offline playbooks/*.yml roles/*/tasks/*.yml roles/*/handlers/*.yml roles/*/defaults/*.yml
)
ansible-playbook -i tests/inventory/hosts.yml tests/render.yml
ansible-playbook -i tests/inventory/hosts.yml tests/proxy-check.yml --check
for script in .ansible/rendered/backup/*.sh; do bash -n "$script"; done
