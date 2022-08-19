#!/bin/bash
#
#
set -eEuo pipefail

function genCilium {
  pushd ../cilium
  envsubst \
    < values.tmpl \
    > values.yaml
  kustomize build --enable-helm . \
    > "$ciliumFilePath"
  yamllint \
    -d "{extends: relaxed, rules: {line-length: {max: 120}}}" \
    "$ciliumFilePath"
  popd
}

function genNodes {
  for node in "${nodes[@]}" ; do
    export nodeId="${node##m900-}"
    readarray -t macs \
      < <(fmt -1 <<< "${nodeMacs[@]}" \
	    | grep "$node" \
	    | cut -f3- -d: )
    export eth0mac="${macs[0]}"
    export eth1mac="${macs[1]}"
    envsubst \
      < controlplane.tmpl \
      > "$nodeConfigDir/$node.yaml"
    talosctl validate -m metal -c "$nodeConfigDir/$node.yaml"
  done
}

function getRegistryProxyCaCrt {
  # and pad to correct indent for template
  # ca.crt is only available over http
  curl -fsSL "${registryProxy//https/http}/ca.crt" \
    | sed -e 's/^/            /'
}

# shellcheck source=node_values.sh
source "$(dirname -- "$0")/node_values.sh"
machine_registry_proxy_ca_crt="$(getRegistryProxyCaCrt)"
export machine_registry_proxy_ca_crt
genNodes
genCilium

