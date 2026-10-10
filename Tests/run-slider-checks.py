#!/usr/bin/env python3
"""Render IceSlider against the CompactSlider module from a completed Debug build."""
from pathlib import Path
import json
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
products = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'build/DerivedData/Build/Products/Debug'
build = root / 'build/RegressionTests'
build.mkdir(parents=True, exist_ok=True)
module = products / 'CompactSlider.o'
if not module.is_file():
    sys.exit('Run the documented Debug build before checking the slider.')
executable = build / 'IceSliderTests'
subprocess.run([
    'xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
    '-target', 'arm64-apple-macos14.0', '-module-cache-path', str(build / 'ModuleCache'),
    '-I', str(products), str(root / 'Ice/UI/IceUI/IceSlider.swift'),
    str(root / 'Tests/IceSliderTests.swift'), str(module), '-o', str(executable),
], check=True)
process = subprocess.Popen([str(executable)])
result = process.wait(timeout=20)
if result:
    sys.exit(result)
if '--check-runtime-issues' in sys.argv:
    logs = subprocess.check_output([
        '/usr/bin/log', 'show', '--last', '2m', '--style', 'json',
        '--predicate', f'processIdentifier == {process.pid} AND subsystem == "com.apple.runtime-issues"',
    ], text=True)
    issues = json.loads(logs)
    if issues:
        for issue in issues:
            print('FAIL:', issue.get('eventMessage'))
        sys.exit(1)
    print('PASS: slider measurement and rendering emit no SwiftUI runtime issues')
