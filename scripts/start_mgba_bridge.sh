#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_SCRIPT="${SCRIPT_DIR}/mgba_host_bridge.py"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PORT="${MGBA_BRIDGE_PORT:-17777}"
BRIDGE_BIND="${MGBA_BRIDGE_BIND:-0.0.0.0}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
LOG_FILE="${TMPDIR:-/tmp}/mgba-host-bridge.log"
INIT_LOG="${WORKSPACE_ROOT}/.devcontainer/mgba-bridge-init.log"

mkdir -p "${WORKSPACE_ROOT}/.devcontainer"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] start_mgba_bridge.sh invoked" >> "${INIT_LOG}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "mGBA host bridge auto-start is currently configured for macOS only; skipping."
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] skipped: non-macOS host" >> "${INIT_LOG}"
  exit 0
fi

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "Python not found on host (${PYTHON_BIN}); cannot start mGBA bridge."
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] failed: python not found (${PYTHON_BIN})" >> "${INIT_LOG}"
  exit 0
fi

if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] bridge already running on ${PORT}" >> "${INIT_LOG}"
  exit 0
fi

"${PYTHON_BIN}" "${BRIDGE_SCRIPT}" --host "${BRIDGE_BIND}" --port "${PORT}" --workspace-root "${WORKSPACE_ROOT}" >"${LOG_FILE}" 2>&1 &

for _ in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    echo "mGBA host bridge started on port ${PORT}."
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] started bridge on ${PORT}" >> "${INIT_LOG}"
    exit 0
  fi
  sleep 0.2
done

echo "Failed to start mGBA host bridge. See ${LOG_FILE}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] failed: see ${LOG_FILE}" >> "${INIT_LOG}"
exit 0
