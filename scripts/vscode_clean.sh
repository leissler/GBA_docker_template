#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-outputs}"

in_container() {
  [[ -f /.dockerenv ]]
}

clean_outputs() {
  if in_container; then
    bash scripts/clean_all_outputs.sh local
  else
    bash scripts/clean_all_outputs.sh host-docker
  fi
}

case "${MODE}" in
  outputs)
    clean_outputs
    ;;
  all)
    clean_outputs
    make clean-docker-stamps
    ;;
  *)
    echo "Unknown mode: ${MODE}"
    echo "Expected: outputs | all"
    exit 1
    ;;
esac
