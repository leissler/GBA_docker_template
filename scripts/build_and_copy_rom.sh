#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-release}"
JOBS="${BUILD_JOBS:-4}"

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

has_stale_deps() {
  if ! ls source/build/*.d >/dev/null 2>&1; then
    return 1
  fi

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue
    if [[ ! -e "${dep}" ]]; then
      return 0
    fi
  done < <(
    awk '{for(i=1;i<=NF;i++){t=$i; gsub(/\\$/, "", t); gsub(/:$/, "", t); if(t ~ /^\//) print t}}' source/build/*.d 2>/dev/null | sort -u
  )

  return 1
}

if has_stale_deps; then
  echo "Detected stale dependency paths; running clean..."
  make -C source clean
fi

if [[ "${MODE}" == "debug" ]]; then
  make -C source -j"${JOBS}" USERFLAGS='-Og -g3' USERCXXFLAGS='-Og -g3'
else
  make -C source -j"${JOBS}"
fi

if [[ ! -f source/source.gba ]]; then
  echo "Build succeeded but source/source.gba was not found."
  exit 1
fi

PROJECT_NAME_RESOLVED="$(resolve_project_name)"
cp -f source/source.gba "./${PROJECT_NAME_RESOLVED}.gba"
echo "Created ./${PROJECT_NAME_RESOLVED}.gba"
