#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_SCRIPT="${SCRIPT_DIR}/mgba_host_bridge.py"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${GBA_BRIDGE_CONFIG:-${WORKSPACE_ROOT}/.emulator-bridge.env}"
PORT="${GBA_BRIDGE_PORT:-${MGBA_BRIDGE_PORT:-17777}}"
BRIDGE_BIND="${GBA_BRIDGE_BIND:-${MGBA_BRIDGE_BIND:-0.0.0.0}}"
RESTART_BRIDGE="${GBA_BRIDGE_RESTART:-1}"
EMULATOR="${GBA_EMULATOR:-mgba}"
EMULATOR_BIN="${GBA_EMULATOR_BIN:-${MGBA_BIN:-}}"
LOG_FILE="${GBA_BRIDGE_LOG_FILE:-/tmp/mgba-host-bridge.log}"
INIT_LOG="${WORKSPACE_ROOT}/.devcontainer/mgba-bridge-init.log"

mkdir -p "${WORKSPACE_ROOT}/.devcontainer"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] start_mgba_bridge.sh invoked" >> "${INIT_LOG}"

if [[ -f "${CONFIG_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
  set +a
  PORT="${GBA_BRIDGE_PORT:-${MGBA_BRIDGE_PORT:-${PORT}}}"
  BRIDGE_BIND="${GBA_BRIDGE_BIND:-${MGBA_BRIDGE_BIND:-${BRIDGE_BIND}}}"
  RESTART_BRIDGE="${GBA_BRIDGE_RESTART:-${RESTART_BRIDGE}}"
  EMULATOR="${GBA_EMULATOR:-${EMULATOR}}"
  EMULATOR_BIN="${GBA_EMULATOR_BIN:-${MGBA_BIN:-${EMULATOR_BIN}}}"
fi

resolve_python() {
  local candidate
  for candidate in "${PYTHON_BIN:-}" python3 python py; do
    if [[ -n "${candidate}" ]] && command -v "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

PYTHON_BIN_RESOLVED="$(resolve_python || true)"
if [[ -z "${PYTHON_BIN_RESOLVED}" ]]; then
  echo "Python not found on host; cannot start emulator bridge automatically."
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] failed: python not found" >> "${INIT_LOG}"
  exit 0
fi

is_bridge_running() {
  curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1
}

shutdown_bridge() {
  if curl -fsS -X POST "http://127.0.0.1:${PORT}/shutdown" >/dev/null 2>&1; then
    for _ in $(seq 1 20); do
      if ! is_bridge_running; then
        return 0
      fi
      sleep 0.1
    done
  fi

  if command -v lsof >/dev/null 2>&1; then
    PIDS="$(lsof -t -iTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "${PIDS}" ]]; then
      kill ${PIDS} >/dev/null 2>&1 || true
    fi
  elif command -v pkill >/dev/null 2>&1; then
    pkill -f "mgba_host_bridge.py.*--port ${PORT}" >/dev/null 2>&1 || true
  fi

  for _ in $(seq 1 20); do
    if ! is_bridge_running; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

if is_bridge_running; then
  if [[ "${RESTART_BRIDGE}" == "1" ]]; then
    echo "Restarting host emulator bridge on port ${PORT}..."
    if ! shutdown_bridge; then
      echo "Warning: could not fully stop existing bridge on port ${PORT}; continuing."
    fi
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] bridge already running on ${PORT}" >> "${INIT_LOG}"
    exit 0
  fi
fi

CMD=(
  "${PYTHON_BIN_RESOLVED}"
  -u
  "${BRIDGE_SCRIPT}"
  --host "${BRIDGE_BIND}"
  --port "${PORT}"
  --workspace-root "${WORKSPACE_ROOT}"
  --emulator "${EMULATOR}"
)

if [[ -n "${EMULATOR_BIN}" ]]; then
  CMD+=(--emulator-bin "${EMULATOR_BIN}")
fi

if command -v nohup >/dev/null 2>&1; then
  nohup "${CMD[@]}" >"${LOG_FILE}" 2>&1 < /dev/null &
else
  "${CMD[@]}" >"${LOG_FILE}" 2>&1 < /dev/null &
fi

for _ in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    echo "Host emulator bridge started on port ${PORT} (emulator: ${EMULATOR})."
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] started bridge on ${PORT} (emulator: ${EMULATOR})" >> "${INIT_LOG}"
    exit 0
  fi
  sleep 0.2
done

echo "Failed to start host emulator bridge. See ${LOG_FILE}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] failed: see ${LOG_FILE}" >> "${INIT_LOG}"
exit 0
