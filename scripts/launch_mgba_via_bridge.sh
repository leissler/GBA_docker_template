#!/usr/bin/env bash
set -euo pipefail

PORT="${MGBA_BRIDGE_PORT:-17777}"
ROM_PATH="source/source.gba"
BRIDGE_HOST=""

for candidate in host.docker.internal gateway.docker.internal; do
  if curl -fsS "http://${candidate}:${PORT}/health" >/dev/null 2>&1; then
    BRIDGE_HOST="${candidate}"
    break
  fi
done

if [[ -z "${BRIDGE_HOST}" ]]; then
  echo "mGBA host bridge is not reachable on port ${PORT}."
  echo "Run on host: bash scripts/start_mgba_bridge.sh"
  exit 1
fi

PAYLOAD="$(ROM_PATH="${ROM_PATH}" python3 - <<'PY'
import json
import os
print(json.dumps({"rom": os.environ["ROM_PATH"]}))
PY
)"

TMP_RESPONSE="$(mktemp)"
HTTP_CODE="$(curl -sS -o "${TMP_RESPONSE}" -w "%{http_code}" -X POST "http://${BRIDGE_HOST}:${PORT}/launch" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")"

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "mGBA bridge launch failed (HTTP ${HTTP_CODE}):"
  cat "${TMP_RESPONSE}"
  rm -f "${TMP_RESPONSE}"
  exit 1
fi

rm -f "${TMP_RESPONSE}"

echo "Requested host mGBA launch for ${ROM_PATH}"
