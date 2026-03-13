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

if [[ "${MODE}" == "debug" ]]; then
  CMD="make -j4 BUILD=build_host_debug USERFLAGS='-Og -g3' USERCXXFLAGS='-Og -g3'"
else
  CMD="make -j4 BUILD=build_host_release"
fi

make AUTO_CLEAN_MAKE=0 compile-butano "CMD=${CMD}"
