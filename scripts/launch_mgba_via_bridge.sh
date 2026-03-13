#!/usr/bin/env bash
set -euo pipefail

PORT="${MGBA_BRIDGE_PORT:-17777}"
ROM_PATH="source/source.gba"
MGBA_DEBUG="${MGBA_DEBUG:-1}"
BRIDGE_HOST=""
BRIDGE_HOST_CANDIDATES=()

if [[ -n "${MGBA_BRIDGE_HOST:-}" ]]; then
  BRIDGE_HOST_CANDIDATES+=("${MGBA_BRIDGE_HOST}")
fi

BRIDGE_HOST_CANDIDATES+=(
  host.docker.internal
  gateway.docker.internal
  host.containers.internal
  docker.for.mac.host.internal
)

if command -v ip >/dev/null 2>&1; then
  DEFAULT_GATEWAY="$(ip route 2>/dev/null | awk '/^default/ {print $3; exit}')"
  if [[ -n "${DEFAULT_GATEWAY}" ]]; then
    BRIDGE_HOST_CANDIDATES+=("${DEFAULT_GATEWAY}")
  fi
fi

if [[ -r /proc/net/route ]]; then
  GW_HEX="$(awk '$2 == "00000000" { print $3; exit }' /proc/net/route)"
  if [[ "${GW_HEX}" =~ ^[0-9A-Fa-f]{8}$ ]]; then
    GW_IP="$(
      printf "%d.%d.%d.%d" \
        "0x${GW_HEX:6:2}" \
        "0x${GW_HEX:4:2}" \
        "0x${GW_HEX:2:2}" \
        "0x${GW_HEX:0:2}"
    )"
    BRIDGE_HOST_CANDIDATES+=("${GW_IP}")
  fi
fi

BRIDGE_HOST_CANDIDATES+=(
  192.168.65.1
  172.17.0.1
)

for candidate in "${BRIDGE_HOST_CANDIDATES[@]}"; do
  if curl -fsS "http://${candidate}:${PORT}/health" >/dev/null 2>&1; then
    BRIDGE_HOST="${candidate}"
    break
  fi
done

if [[ -z "${BRIDGE_HOST}" ]]; then
  echo "mGBA host bridge is not reachable on port ${PORT}."
  echo "Checked hosts: ${BRIDGE_HOST_CANDIDATES[*]}"
  echo "Run on host: bash scripts/start_mgba_bridge.sh"
  exit 1
fi

PAYLOAD="$(ROM_PATH="${ROM_PATH}" MGBA_DEBUG="${MGBA_DEBUG}" python3 - <<'PY'
import json
import os
debug_value = os.environ.get("MGBA_DEBUG", "1").strip().lower()
debug_enabled = debug_value not in ("0", "false", "no")
print(json.dumps({"rom": os.environ["ROM_PATH"], "debug": debug_enabled}))
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
