"""Validate role option names against the installed modules' documented API."""
import json
from pathlib import Path
import subprocess

from ruamel.yaml import YAML

ROOT = Path(__file__).resolve().parents[1]


def test_role_module_options_match_installed_collections():
    invocations = []

    def walk(value, path):
        if isinstance(value, list):
            for item in value:
                walk(item, path)
        elif isinstance(value, dict):
            for key, options in value.items():
                if isinstance(key, str) and key.startswith(("ansible.builtin.", "ansible.posix.", "community.")):
                    if isinstance(options, dict):
                        invocations.append((path, key, options))
                elif key in ("block", "rescue", "always"):
                    walk(options, path)

    yaml = YAML(typ="safe")
    for path in sorted((ROOT / "roles").glob("*/tasks/*.yml")) + sorted((ROOT / "roles").glob("*/handlers/*.yml")):
        walk(yaml.load(path.read_text()), path.relative_to(ROOT))
    modules = sorted({module for _, module, _ in invocations})
    result = subprocess.run(["ansible-doc", "--json", *modules], cwd=ROOT, capture_output=True, text=True, check=True)
    docs = json.loads(result.stdout)
    for path, module, options in invocations:
        if module == "ansible.builtin.set_fact":
            # This module deliberately accepts arbitrary variable names.
            continue
        documented = docs[module]["doc"].get("options", {})
        allowed = set(documented)
        for spec in documented.values():
            allowed.update(spec.get("aliases", []))
        unknown = set(options) - allowed
        assert not unknown, f"{path}: {module} has unknown options {sorted(unknown)}"
