#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-local}"

resolve_project_name() {
  local name="${PROJECT_NAME:-}"

  if [[ -z "${name}" || "${name}" == *'${'* ]]; then
    local origin_url
    origin_url="$(git config --get remote.origin.url 2>/dev/null || true)"
    if [[ -n "${origin_url}" ]]; then
      name="$(basename "${origin_url}")"
      name="${name%.git}"
    fi
  fi

  if [[ -z "${name}" ]]; then
    name="$(basename "$(pwd -P)")"
  fi

  printf '%s\n' "${name}"
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

PROJECT_NAME_RESOLVED="$(resolve_project_name)"

# Shared artifact cleanup in repository root.
rm -f "./${PROJECT_NAME_RESOLVED}.gba" ./source.gba ./compile_commands.json

if [[ "${MODE}" == "host-docker" ]]; then
  CONTAINER_CMD="rm -f /source/source.gba /source/source.elf /source/source.map /source/source.sym /source/source.dis && rm -rf /source/build /source/build_debug /source/build_release /source/build_dev_debug /source/build_dev_release /source/build_host_debug /source/build_host_release"
  MAKE_ARGS=(AUTO_CLEAN_MAKE=0 compile-butano "CMD=${CONTAINER_CMD}")
  if [[ -n "${GBA_SOURCE_DIR_MOUNT:-}" ]]; then
    MAKE_ARGS+=("SOURCE_DIR_MOUNT=${GBA_SOURCE_DIR_MOUNT}")
  fi
  make "${MAKE_ARGS[@]}"
elif [[ "${MODE}" == "local" ]]; then
  rm -f source/source.gba source/source.elf source/source.map source/source.sym source/source.dis
  rm -rf \
    source/build \
    source/build_debug \
    source/build_release \
    source/build_dev_debug \
    source/build_dev_release \
    source/build_host_debug \
    source/build_host_release
else
  echo "Unknown cleanup mode: ${MODE}"
  echo "Expected: local | host-docker"
  exit 1
fi

echo "Cleanup complete (${MODE})."
