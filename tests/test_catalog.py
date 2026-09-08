import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest
from ruamel.yaml import YAML

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("catalog", ROOT / "scripts/app_catalog.py")
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


@pytest.fixture
def apps_file(tmp_path):
    path = tmp_path / "apps.yml"
    path.write_text('# keep this comment\napps:\n  portfolio:\n    image_tag: "old"\n  uptime_kuma:\n    image_tag: "2.1.3"\n  disabled:\n    enabled: false\n    image_tag: "old"\n')
    return path


def test_multi_app_selection_and_alias(apps_file):
    apps = catalog.load(apps_file)[2]
    assert catalog.select(apps, "portfolio,uptime-kuma") == ["portfolio", "uptime_kuma"]
    assert catalog.select(apps, "all") == ["portfolio", "uptime_kuma"]


@pytest.mark.parametrize("name", ["missing", "disabled", "", "all,missing", "portfolio;touch /tmp/no"])
def test_reject_invalid_selection(apps_file, name):
    with pytest.raises(ValueError):
        catalog.select(catalog.load(apps_file)[2], name)


@pytest.mark.parametrize("tag,expected", [("2.1.3", "2.1.3"), ("latest", "latest"), ("abcdef0123", "sha-abcdef0123"), ("sha-abcdef0123", "sha-abcdef0123")])
def test_updates_real_tags_and_commit_shas(apps_file, tag, expected):
    catalog.update_tag(apps_file, "uptime-kuma", tag)
    assert catalog.load(apps_file)[2]["uptime_kuma"]["image_tag"] == expected
    assert "# keep this comment" in apps_file.read_text()
    assert catalog.load(apps_file)[2]["portfolio"]["image_tag"] == "old"
    assert catalog.update_tag(apps_file, "uptime_kuma", tag).startswith("NO_CHANGES")


@pytest.mark.parametrize("tag", ['bad"tag', "a\nb", "$(touch /tmp/no)", "v1/tag", "x" * 129])
def test_reject_invalid_tag_without_writing(apps_file, tag):
    original = apps_file.read_bytes()
    with pytest.raises(ValueError):
        catalog.update_tag(apps_file, "portfolio", tag)
    assert apps_file.read_bytes() == original


def test_deploy_alias_reaches_correct_playbook(tmp_path):
    executable = tmp_path / "ansible-playbook"
    executable.write_text('#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
    executable.chmod(0o755)
    env = dict(os.environ, PATH=str(tmp_path) + os.pathsep + os.environ["PATH"])
    result = subprocess.run(["bash", "scripts/deploy-app.sh", "uptime-kuma", "target", "playbooks/apps.yml", "--check"], cwd=ROOT, env=env, capture_output=True, text=True, check=True)
    args = json.loads(result.stdout)
    assert args[0] == "playbooks/apps.yml"
    assert json.loads(args[args.index("--extra-vars") + 1]) == {"apps_selected": ["uptime_kuma"]}
    assert "--check" in args


def test_credentials_are_literal_private_and_missing_secrets_fail(tmp_path):
    env_file = tmp_path / "env"
    values = dict(os.environ, RUNNER_TEMP=str(tmp_path), GITHUB_ENV=str(env_file), ANSIBLE_VAULT_PASSWORD='a$()"b', ANSIBLE_SSH_PRIVATE_KEY='line1\\nline2', ANSIBLE_SSH_KNOWN_HOSTS='example.invalid ssh-ed25519 fake')
    subprocess.run([sys.executable, "scripts/ci_credentials.py"], cwd=ROOT, env=values, check=True)
    credentials = tmp_path / "altair-credentials"
    assert (credentials / "vault").read_text() == 'a$()"b\n'
    assert (credentials / "id_ed25519").read_text() == 'line1\nline2\n'
    assert all(p.stat().st_mode & 0o777 == 0o600 for p in credentials.iterdir())
    values.pop("ANSIBLE_SSH_KNOWN_HOSTS")
    result = subprocess.run([sys.executable, "scripts/ci_credentials.py"], cwd=ROOT, env=values, capture_output=True, text=True)
    assert result.returncode != 0
    assert 'a$()"b' not in result.stderr


def test_catalog_has_templates_and_unique_persistent_projects():
    apps = catalog.load(ROOT / "inventory/group_vars/all/apps.yml")[2]
    assert len({app["deploy_dir"] for app in apps.values()}) == len(apps)
    assert len({app["container_name"] for app in apps.values()}) == len(apps)
    for name in apps:
        assert (ROOT / f"roles/apps/templates/{name}/docker-compose.yml.j2").exists()
