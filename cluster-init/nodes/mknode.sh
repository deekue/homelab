#!/usr/bin/env bash
#
# QaD script to generate node yaml configs from templates

set -eEuo pipefail

nodes=(m900-1 m900-2 m900-3)
nodeTemplate="member-node.tmpl"
provisionShFile="provision.sh"
provisionShDestPath="/root/provision.sh"
k3sManifestDir="/var/lib/rancher/k3s/server/manifests"
kubevipFile="../kube-vip/kube-vip-ds.yaml"
kubevipFileDestPath="${k3sManifestDir}/kube-vip-ds.yaml"
kubevipCloudControllerDir="../kube-vip-cloud-provider"
kubevipCCFile="${kubevipCloudControllerDir}/kube-vip-cloud-controller.yaml"
kubevipCCFileDestPath="${k3sManifestDir}/kube-vip-cloud-controller.yaml"
kubevipCCConfigMapFile="${kubevipCloudControllerDir}/configmap.yaml"
kubevipCCConfigMapFileDestPath="${k3sManifestDir}/kube-vip-cloud-controller-configmap.yaml"
kubeVipAddr="192.168.40.10"  # TODO get VIP addr from $kubevipFile
kubeVipHostname="k8s.s.chaosengine.net"
serverToken="SECRETSQUIRREL"  # TODO update before prod
# shellcheck disable=SC2016
serverPassword='$1$ZDYMI7GJ$0F0YZRwBXP4l3CQItcXMg/'  # update with `openssl passwd -1`

function writeFilesHeader {
  local -r path="${1:?arg1 is path}"
  local -r permissions="${2:?arg2 is permissions}"
  local -r input="${3:?arg3 is input file}"

  cat <<EOF
  # yamllint disable-line rule:line-length
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
  primaryNodeKubeVipCcCfg=
  primaryNodeKubeVipCcCm=
  if [[ "$node" == "m900-1" ]] ; then
    echo -n "primary..."
    primaryNodeKubeVipCfg="$(writeFilesHeader \
      "$kubevipFileDestPath" "0644" "${kubevipFile}")"
    primaryNodeKubeVipCcCfg="$(writeFilesHeader \
      "$kubevipCCFileDestPath" "0644" "${kubevipCCFile}")"
    primaryNodeKubeVipCcCm="$(writeFilesHeader \
      "$kubevipCCConfigMapFileDestPath" "0644" "${kubevipCCConfigMapFile}")"
    # shellcheck disable=SC2089
    primaryNodeClusterInit='- "--cluster-init"'
  else
    server_url="server_url: https://${kubeVipAddr}:6443"
  fi
  # export to appease shellcheck, and catch missing vars
  export nodeHostName nodeProvisionSh serverToken serverPassword
  export kubeVipAddr kubeVipHostname
  export primaryNodeKubeVipCfg primaryNodeKubeVipCcCfg primaryNodeKubeVipCcCm
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

