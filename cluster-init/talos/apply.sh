#!/bin/bash

# shellcheck source=node_values.sh
source "$(dirname -- "$0")/node_values.sh"

function applyAll {
  readarray -t nodeIPs \
    < <(yq -r '.contexts.homelab.nodes[]' "$talosConfig")

  for nodeIP in "${nodeIPs[@]}" ; do
    applyConfig "$nodeIP"
  done
}

function applyConfig {
  local -r nodeIP="${1:?arg1 is nodeIP}"
  nodeId="${nodeIP##*.}"

  talosctl apply $dryRun \
    -n "$nodeIP" \
    -f "$nodeConfigDir/m900-$nodeId.yaml"
}

function usage {
  cat <<EOF >&2
Usage: $(basename -- "$0") <target> [dry run]

  target   1-3|all
  dry run  true|false
  
EOF

  exit 1
}

if [[ "${2:-true}" == "false" ]] ; then
  dryRun=
else
  dryRun="--dry-run"
fi

case "${1:-}" in
  [1-3])
    applyConfig "${network_default_subnet}.$1"
    ;;
  all)
    applyAll
    ;;
  *)
    usage
    ;;
esac
