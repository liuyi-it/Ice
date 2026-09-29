#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build="$project_root/build/RegressionTests"
mkdir -p "$test_build"

xcrun swiftc -swift-version 5 -module-cache-path "$test_build/ModuleCache" \
    "$project_root/Ice/Events/MouseState.swift" \
    "$project_root/Ice/Events/EventMonitors/LocalEventMonitor.swift" \
    "$project_root/Ice/Events/EventMonitors/GlobalEventMonitor.swift" \
    "$project_root/Ice/Events/EventMonitors/UniversalEventMonitor.swift" \
    "$project_root/Ice/Utilities/TaskTimeout.swift" \
    "$project_root/Ice/Utilities/AsyncSerialQueue.swift" \
    "$project_root/Tests/RegressionTests.swift" \
    -o "$test_build/RegressionTests"

"$test_build/RegressionTests"

python3 "$project_root/Tests/run-movement-checks.py"
