#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"
"$ROOT/build/Bagad Billi.app/Contents/MacOS/BagadBilli" --self-test
