#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../src/clawIsland"
echo "Building clawIsland (release)..."
swift build -c release
echo "✅ Built: .build/release/clawIsland"
