#!/usr/bin/env bash
#
# QaD script to generate node yaml configs from templates

set -eEuo pipefail

nodes=(m900-1 m900-2 m900-3)
nodeTemplate="member-node.tmpl"
provisionShFile="provision.sh"
provisionShDestPath="/root/provision.sh"
kubevipFile="../kube-vip/kube-vip-ds.yaml"
kubevipFileDestPath="/var/lib/rancher/k3s/server/manifests/kube-vip-ds.yaml"
# TODO get VIP addr from $kubevipFile
kubeVipAddr="192.168.40.10"
kubeVipHostname="k8s.s.chaosengine.net"
serverToken="SECRETSQUIRREL"  # TODO update before prod
serverPassword="k3os"  # TODO update before prod `openssl passwd -1`

function writeFilesHeader {
  local -r path="${1:?arg1 is path}"
  local -r permissions="${2:?arg2 is permissions}"
  local -r input="${3:?arg3 is input file}"

  cat <<EOF
  - path: ${path}
    owner: root:root
    permissions: '${permissions}'
    encoding: gz+base64
    content: |
EOF
  gzip -9c "$input" \
    | python3 -m base64 \
    | sed -e 's/^/      /'
}


for node in "${nodes[@]}" ; do
  echo -n "${node}..."
  nodeHostName="$node"
  nodeProvisionSh="$(writeFilesHeader "$provisionShDestPath" "0744" "${provisionShFile}")"
  primaryNodeClusterInit=
  server_url=
  primaryNodeKubeVipCfg=
  if [[ "$node" == "m900-1" ]] ; then
    echo -n "primary..."
    primaryNodeKubeVipCfg="$(writeFilesHeader "$kubevipFileDestPath" "0644" "${kubevipFile}")"
    # shellcheck disable=SC2089
    primaryNodeClusterInit='- "--cluster-init"'
  else
    server_url="server_url: https://${kubeVipAddr}:6443"
  fi
  # export to appease shellcheck, and catch missing vars
  export nodeHostName nodeProvisionSh serverToken serverPassword
  export kubeVipAddr kubeVipHostname
  export primaryNodeKubeVipCfg
  # shellcheck disable=SC2090
  export primaryNodeClusterInit  # we want the string literal, not tokenized
  export server_url  # secondary only
  envsubst \
    < "${nodeTemplate}" \
    | sed -e '/^ *$/ d' \
    > "${node}.yaml"
  yamllint "${node}.yaml"
  echo "done."
done

