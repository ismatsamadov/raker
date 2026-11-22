#!/usr/bin/env bash
# Runs the RakerKit test suites. Extra arguments go to `swift test`.
set -euo pipefail
cd "$(dirname "$0")/../Packages/RakerKit"

developer_dir="$(xcode-select -p)"
extra=()
if [[ "$developer_dir" == *CommandLineTools* ]]; then
    # With only the Command Line Tools, SwiftPM can lose track of the Swift Testing
    # macro plugin between builds; pass its location explicitly.
    extra=(-Xswiftc -plugin-path -Xswiftc "$developer_dir/usr/lib/swift/host/plugins/testing")
fi
swift test ${extra[@]+"${extra[@]}"} "$@"
