#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../src/clawIsland"
echo "Building clawIsland (debug)..."
swift build
echo "Running..."
exec .build/debug/clawIsland
