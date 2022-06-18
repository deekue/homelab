#!/usr/bin/env bash
#
# QaD script to generate node yaml configs from templates

set -eEuo pipefail

nodes=(m900-1 m900-2 m900-3)
provisionFile="provision.sh"
kubevipFile="../kube-vip/kube-vip-ds.yaml"
primaryTemplate="primary-node.tmpl"
memberTemplate="member-node.tmpl"

function encode {
  local -r input="${1:?arg1 is input file}"
  gzip -9c "$input" \
    | python3 -m base64 \
    | sed -e 's/^/    /'
}

for node in "${nodes[@]}" ; do
  nodeHostName="$node"
  nodeProvisionSh="$(encode "${provisionFile}")"
  export nodeHostName nodeProvisionSh
  if [[ "$node" == "m900-1" ]] ; then
    primaryNodeKubeVipCfg="$(encode "${kubevipFile}")"
    export primaryNodeKubeVipCfg
    template="$primaryTemplate"
  else
    template="$memberTemplate"
  fi
  envsubst < "${template}" > "${node}.yaml"
done

