#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../src/MiloOverlay"
exec .build/release/MiloOverlay
