#!/bin/bash

if [[ "${1:-false}" == "true" ]] ; then
  dryRun=
else
  dryRun="--dry-run"
fi

# shellcheck source=node_values.sh
source "$(dirname -- "$0")/node_values.sh"

readarray -t nodeIPs \
  < <(yq -r '.contexts.homelab.nodes[]' "$talosConfig")

for nodeIP in "${nodeIPs[@]}" ; do
  nodeId="${nodeIP##*.}"
  talosctl apply $dryRun \
    -n "$nodeIP" \
    -f "$nodeConfigDir/m900-$nodeId.yaml"
done
