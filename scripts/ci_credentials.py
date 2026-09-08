#!/usr/bin/env python3
"""Write ephemeral deployment credentials without shell interpolation."""
import os
from pathlib import Path


def main():
    required = ["ANSIBLE_VAULT_PASSWORD", "ANSIBLE_SSH_PRIVATE_KEY", "ANSIBLE_SSH_KNOWN_HOSTS"]
    missing = [name for name in required if not os.environ.get(name, "").strip()]
    if missing:
        raise SystemExit("Missing deployment secrets: " + ", ".join(missing))
    directory = Path(os.environ["RUNNER_TEMP"]) / "altair-credentials"
    directory.mkdir(mode=0o700, exist_ok=True)
    values = {
        "vault": os.environ["ANSIBLE_VAULT_PASSWORD"],
        "id_ed25519": os.environ["ANSIBLE_SSH_PRIVATE_KEY"].replace("\r\n", "\n").replace("\\n", "\n"),
        "known_hosts": os.environ["ANSIBLE_SSH_KNOWN_HOSTS"],
    }
    for name, value in values.items():
        path = directory / name
        path.touch(mode=0o600)
        path.chmod(0o600)
        path.write_text(value.rstrip("\n") + "\n")
    with open(os.environ["GITHUB_ENV"], "a") as env:
        env.write(f"ANSIBLE_VAULT_PASSWORD_FILE={directory}/vault\n")
        env.write(f"ANSIBLE_PRIVATE_KEY_FILE={directory}/id_ed25519\n")
        env.write(f"ANSIBLE_SSH_COMMON_ARGS=-o StrictHostKeyChecking=yes -o UserKnownHostsFile={directory}/known_hosts\n")


if __name__ == "__main__":
    main()
