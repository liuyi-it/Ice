#!/usr/bin/env python3
"""Verify that a built Ice.app cannot load the removed Sparkle updater."""

import argparse
import plistlib
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Path to the built Ice.app")
    args = parser.parse_args()
    contents = args.app / "Contents"
    with (contents / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    executable = contents / "MacOS" / info["CFBundleExecutable"]
    linked_libraries = subprocess.check_output(
        ["otool", "-L", str(executable)], text=True
    )

    failures = []
    update_keys = sorted(key for key in info if key.startswith(("SU", "SPU")))
    if update_keys:
        failures.append(f"Update configuration is still present: {update_keys}")
    if "sparkle" in linked_libraries.lower():
        failures.append("The executable still links Sparkle")

    helper_names = {"autoupdate", "updater.app", "downloader.xpc", "installer.xpc"}
    for path in contents.rglob("*"):
        if "sparkle" in path.name.lower() or path.name.lower() in helper_names:
            failures.append(f"Bundled updater: {path.relative_to(args.app)}")

    if failures:
        parser.exit(1, "\n".join(f"FAIL: {failure}" for failure in failures) + "\n")
    print(f"PASS: {args.app} contains no updater configuration, linkage or helpers")


if __name__ == "__main__":
    main()
