#!/usr/bin/env python3
"""Exercise the production settings sidebar and check its runtime diagnostics."""
from pathlib import Path
import json
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
build = root / 'build/RegressionTests'
build.mkdir(parents=True, exist_ok=True)
executable = build / 'SettingsNavigationTests'
sources = [
    'Ice/Main/Navigation/AppNavigationState.swift',
    'Ice/Main/Navigation/NavigationIdentifiers/NavigationIdentifier.swift',
    'Ice/Main/Navigation/NavigationIdentifiers/SettingsNavigationIdentifier.swift',
    'Ice/UI/ViewModifiers/RemoveSidebarToggle.swift',
    'Ice/Settings/SettingsView.swift',
    'Tests/SettingsNavigationTests.swift',
]
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
                '-module-cache-path', str(build / 'ModuleCache'),
                *[str(root / path) for path in sources], '-o', str(executable)], check=True)
process = subprocess.Popen([str(executable)])
result = process.wait(timeout=20)
if result:
    sys.exit(result)
logs = json.loads(subprocess.check_output([
    '/usr/bin/log', 'show', '--last', '2m', '--style', 'json', '--predicate',
    f'processIdentifier == {process.pid} AND (subsystem == "com.apple.runtime-issues" '
    'OR (subsystem == "com.apple.AppKit" AND category == "WarnOnce"))',
], text=True))
if logs:
    for row in logs:
        print('FAIL:', row.get('eventMessage', '').split('\n')[0])
    sys.exit(1)
print('PASS: settings navigation emits no SwiftUI or AppKit layout warnings')
