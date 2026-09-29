#!/usr/bin/env python3
"""Compile real movement methods against a simulated WindowServer/event boundary."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
build = root / 'build' / 'RegressionTests'
build.mkdir(parents=True, exist_ok=True)
source = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift'
text = source.read_text()
methods = []
for name in ('getEndPoint', 'getFallbackPoint', 'getTargetItem', 'itemHasCorrectPosition',
             'moveItemWithoutRestoringMouseLocation', 'performMove', 'waitForCorrectPosition'):
    marker = f'    private func {name}('
    if name == 'waitForCorrectPosition' and marker not in text:
        continue  # Allows the pre-fix method to demonstrate the regression.
    start = text.index(marker)
    end = text.index('\n    }', start) + len('\n    }')
    methods.append(text[start:end])
template = (root / 'Tests/MenuBarMoveTests.swift').read_text()
call = 'try await performMove(item: item, to: .leftOfItem(target)'
if 'private func performMove(item: MenuBarItem, to destination: MoveDestination, timeout:' in text:
    call += ', timeout: timeout'
call += ')'
generated = template.replace('    // PRODUCTION_MOVE_METHODS', '\n\n'.join(methods))
generated = generated.replace('// PRODUCTION_MOVE_CALL', call)
path = build / 'MenuBarMoveTests.swift'
path.write_text(generated)
executable = build / 'MenuBarMoveTests'
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-module-cache-path',
                str(build / 'ModuleCache'), str(root / 'Ice/Utilities/TaskTimeout.swift'), str(path),
                '-o', str(executable)], check=True)
sys.exit(subprocess.run([str(executable)], timeout=20).returncode)
