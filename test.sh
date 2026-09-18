#!/bin/sh
set -eu

cd "$(dirname "$0")"

xcrun python3 -m unittest Tests/test_versioning.py

TEST_BINARY=".build/AIUsageRegressionTests"
mkdir -p .build

swiftc -parse-as-library \
    Sources/AIUsage/Report.swift \
    Sources/AIUsage/OpenRouter.swift \
    Sources/AIUsage/OpenRouterKeychain.swift \
    Sources/AIUsage/Cursor.swift \
    Sources/AIUsage/CursorKeychain.swift \
    Sources/AIUsage/WorkSchedule.swift \
    Sources/AIUsage/Pace.swift \
    Sources/AIUsage/Fetcher.swift \
    Sources/AIUsage/BrandGlyph.swift \
    Sources/AIUsage/StatusIcon.swift \
    Tests/RegressionTests.swift \
    -o "$TEST_BINARY"

# Unbundled, so point the icon lookup at the working copy rather than at the
# Resources directory build.sh would have assembled.
AI_USAGE_ICONS="$(pwd)/Resources/Icons" "$TEST_BINARY"
