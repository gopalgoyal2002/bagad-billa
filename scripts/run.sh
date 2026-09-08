#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -x "$ROOT/build/Bagad Billi.app/Contents/MacOS/BagadBilli" ]]; then
  "$ROOT/scripts/build.sh"
fi
open "$ROOT/build/Bagad Billi.app"
