#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../src/MiloOverlay"
echo "Building MiloOverlay (release)..."
swift build -c release
echo "✅ Built: .build/release/MiloOverlay"
