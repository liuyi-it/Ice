#!/usr/bin/env python3
"""Check real WindowInfo parsing and status-item classification with recorded fixtures."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
build = root / 'build/RegressionTests'
build.mkdir(parents=True, exist_ok=True)
source = build / 'WindowInfoTests.swift'
source.write_text((root / 'Ice/Utilities/WindowInfo.swift').read_text() + '\n' +
                  (root / 'Tests/WindowInfoTests.swift').read_text())
executable = build / 'WindowInfoTests'
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
                '-module-cache-path', str(build / 'ModuleCache'),
                str(root / 'Ice/MenuBar/MenuBarItems/MenuBarItemInfo.swift'),
                str(source), '-o', str(executable)], check=True)
sys.exit(subprocess.run([str(executable)], timeout=10).returncode)
