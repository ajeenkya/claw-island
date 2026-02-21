#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../src/clawIsland"
exec .build/release/clawIsland
