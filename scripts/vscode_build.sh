#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-debug}"

in_container() {
  [[ -f /.dockerenv ]]
}

case "${MODE}" in
  debug|release)
    ;;
  *)
    echo "Unknown mode: ${MODE}"
    echo "Expected: debug | release"
    exit 1
    ;;
esac

if in_container; then
  bash scripts/build_and_copy_rom.sh "${MODE}"
  exit 0
fi

MAKE_ARGS=(AUTO_CLEAN_MAKE=0 compile-butano)
if [[ -n "${GBA_SOURCE_DIR_MOUNT:-}" ]]; then
  MAKE_ARGS+=("SOURCE_DIR_MOUNT=${GBA_SOURCE_DIR_MOUNT}")
fi

if [[ "${MODE}" == "debug" ]]; then
  CMD="make -j4 BUILD=build_host_debug USERFLAGS='-Og -g3' USERCXXFLAGS='-Og -g3'"
else
  CMD="make -j4 BUILD=build_host_release"
fi

MAKE_ARGS+=("CMD=${CMD}")
make "${MAKE_ARGS[@]}"
