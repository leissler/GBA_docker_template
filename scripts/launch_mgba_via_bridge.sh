#!/usr/bin/env bash
set -euo pipefail

PORT="${MGBA_BRIDGE_PORT:-17777}"
ROM_PATH="source/source.gba"

if ! curl -fsS "http://host.docker.internal:${PORT}/health" >/dev/null 2>&1; then
  echo "mGBA host bridge is not reachable at host.docker.internal:${PORT}."
  echo "Run on host: bash scripts/start_mgba_bridge.sh"
  exit 1
fi

PAYLOAD="$(ROM_PATH="${ROM_PATH}" python3 - <<'PY'
import json
import os
print(json.dumps({"rom": os.environ["ROM_PATH"]}))
PY
)"

curl -fsS -X POST "http://host.docker.internal:${PORT}/launch" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" >/dev/null

echo "Requested host mGBA launch for ${ROM_PATH}"
