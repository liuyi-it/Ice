#!/usr/bin/env python3
"""Exercise production Ice Bar presentation and selection at simulated OS boundaries."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
source_root = Path(sys.argv[1]) if len(sys.argv) > 1 else root
build = root / 'build/RegressionTests'
build.mkdir(parents=True, exist_ok=True)


def methods(path, markers):
    source = (source_root / path).read_text()
    result = []
    for marker in markers:
        start = 0
        while (start := source.find(marker, start)) >= 0:
            end = source.index('\n    }', start) + len('\n    }')
            result.append(source[start:end])
            start = end
    return '\n\n'.join(result)


panel = methods('Ice/UI/IceBar/IceBar.swift', ['    func show(', '    override func close('])
manager = methods('Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift', [
    '    func iceBarItems(', '    func itemIsDirectlyClickable(',
    '    private func itemIsDirectlyClickable(', '    private func currentItem(',
    '    private func hiddenControlItemIndex(', '    private func itemIsInVisibleSection(',
])
cache = methods('Ice/MenuBar/MenuBarItems/MenuBarItemImageCache.swift', ['    func updateCacheWithoutChecks('])
display_cache = methods('Ice/MenuBar/MenuBarItems/MenuBarItemImageCache.swift', ['    func updateCache()'])
template = (root / 'Tests/IceBarTests.swift').read_text()
source = build / 'IceBarTests.swift'
source.write_text(template.replace('    // PRODUCTION_PANEL_METHODS', panel)
                  .replace('    // PRODUCTION_SELECTION_METHODS', manager)
                  .replace('    // PRODUCTION_CACHE_METHODS', cache)
                  .replace('    // PRODUCTION_CACHE_DISPLAY_METHODS', display_cache))
executable = build / 'IceBarTests'
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
                '-module-cache-path', str(build / 'ModuleCache'),
                str(source), '-o', str(executable)], check=True)
sys.exit(subprocess.run([str(executable)], timeout=15).returncode)
