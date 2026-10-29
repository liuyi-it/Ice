#!/usr/bin/env python3
"""Compile the production layout manager against simulated app boundaries."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
source_root = Path(sys.argv[1]) if len(sys.argv) > 1 else root
build = source_root / 'build' / 'RegressionTests'
build.mkdir(parents=True, exist_ok=True)
executable = build / 'MenuBarLayoutTests'
subprocess.run([
    'xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
    '-module-cache-path', str(build / 'ModuleCache'),
    str(source_root / 'Ice/MenuBar/MenuBarItems/MenuBarLayoutConfiguration.swift'),
    str(source_root / 'Ice/MenuBar/MenuBarItems/MenuBarLayoutManager.swift'),
    str(root / 'Tests/MenuBarLayoutTests.swift'), '-o', str(executable),
], check=True)
sys.exit(subprocess.run([str(executable), *sys.argv[2:]], timeout=40).returncode)
