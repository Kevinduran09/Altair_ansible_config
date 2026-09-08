#!/usr/bin/env python3
"""Validate application selectors and update image tags using a YAML parser."""
import argparse
import json
import re
from pathlib import Path
from ruamel.yaml import YAML

ALIASES = {"uptime-kuma": "uptime_kuma", "uptimekuma": "uptime_kuma"}


def normalize(name):
    return ALIASES.get(name, name)


def load(path):
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)
    with Path(path).open() as stream:
        document = yaml.load(stream)
    apps = document.get("apps", {})
    if not isinstance(apps, dict) or not apps:
        raise ValueError("apps must be a non-empty mapping")
    return yaml, document, apps


def select(apps, selector):
    names = list(apps) if selector == "all" else [normalize(x.strip()) for x in selector.split(",")]
    if not names or any(name not in apps for name in names):
        raise ValueError("Unknown application; available: " + ", ".join(apps))
    disabled = [name for name in names if apps[name].get("enabled", True) is False]
    if disabled and selector != "all":
        raise ValueError("Requested application is disabled: " + ", ".join(disabled))
    return list(dict.fromkeys(name for name in names if name not in disabled))


def update_tag(path, app, tag):
    app = normalize(app)
    if re.fullmatch(r"[a-fA-F0-9]{7,40}", tag):
        tag = "sha-" + tag
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", tag):
        raise ValueError("Invalid Docker image tag")
    yaml, document, apps = load(path)
    select(apps, app)
    old = str(apps[app]["image_tag"])
    if old == tag:
        return f"NO_CHANGES app={app} tag={tag}"
    apps[app]["image_tag"] = tag
    with Path(path).open("w") as stream:
        yaml.dump(document, stream)
    return f"UPDATED app={app} old={old} new={tag}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["select", "update"])
    parser.add_argument("app")
    parser.add_argument("tag", nargs="?")
    parser.add_argument("--file", default="inventory/group_vars/all/apps.yml")
    args = parser.parse_args()
    try:
        if args.command == "select":
            names = select(load(args.file)[2], args.app)
            if not names:
                raise ValueError("No enabled applications selected")
            print(json.dumps({"apps_selected": names}))
        else:
            if args.tag is None:
                raise ValueError("update requires a tag")
            print(update_tag(args.file, args.app, args.tag))
    except (ValueError, KeyError) as error:
        parser.exit(2, str(error) + "\n")


if __name__ == "__main__":
    main()
