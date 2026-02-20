#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../src/MiloOverlay"
echo "Building MiloOverlay (debug)..."
swift build
echo "Running..."
exec .build/debug/MiloOverlay
