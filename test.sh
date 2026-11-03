#!/bin/sh
set -eu

cd "$(dirname "$0")"

xcrun python3 -m unittest Tests/test_versioning.py

TEST_BINARY=".build/AIUsageRegressionTests"
case "${1:-}" in
    --store) TEST_BINARY="${TEST_BINARY}-store"; set -- -D APP_STORE ;;
    "") set -- ;;
    *) echo "Usage: $0 [--store]" >&2; exit 2 ;;
esac
mkdir -p .build

# Compile the app's real view/controller sources as well as its pure logic.
# The executable entry point is replaced by RegressionTests.main.
for source in Sources/AIUsage/*.swift; do
    case "$source" in */AIUsageApp.swift) continue ;; esac
    set -- "$@" "$source"
done

swiftc -parse-as-library "$@" \
    Tests/RegressionTests.swift \
    Tests/ProviderFolderAccessTests.swift \
    Tests/UsageRowRenderTests.swift \
    Tests/SettingsTests.swift \
    -o "$TEST_BINARY"

# Unbundled, so point the icon lookup at the working copy rather than at the
# Resources directory build.sh would have assembled.
AI_USAGE_ICONS="$(pwd)/Resources/Icons" "$TEST_BINARY"
