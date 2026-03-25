#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-release}"
NO_BUILD="${2:-}"

case "${MODE}" in
  release|debug) ;;
  *)
    echo "Unknown mode: ${MODE}"
    echo "Expected: release | debug"
    exit 1
    ;;
esac

if [[ "${NO_BUILD}" != "--no-build" && -n "${NO_BUILD}" ]]; then
  echo "Unknown option: ${NO_BUILD}"
  echo "Usage: bash scripts/run_and_launch_rom.sh [release|debug] [--no-build]"
  exit 1
fi

if [[ "${NO_BUILD}" != "--no-build" ]]; then
  bash scripts/vscode_build.sh "${MODE}"
fi

GBA_DEBUG_FLAG="0"
if [[ "${MODE}" == "debug" ]]; then
  GBA_DEBUG_FLAG="1"
fi

bash scripts/start_mgba_bridge.sh
GBA_DEBUG="${GBA_DEBUG_FLAG}" bash scripts/launch_mgba_via_bridge.sh
