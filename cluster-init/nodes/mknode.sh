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

function genNodeNetworkConfig {
  local -r nodeId="${1:?arg1 is nodeId}"

  # https://github.com/billimek/homelab-infrastructure/issues/14
  # adding the 'vlan' pkg would make this easier
  # https://wiki.alpinelinux.org/wiki/Vlan
  cat <<EOF | writeFilesHeader /etc/network/interfaces "0644" "/dev/stdin"
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet manual
  up ip link set eth0 up
  up ip link add link eth0 name eth0.10  type vlan id 10  || true
  up ip link add link eth0 name eth0.30  type vlan id 30  || true
  up ip link add link eth0 name eth0.40  type vlan id 40  || true
  up ip link add link eth0 name eth0.100 type vlan id 100 || true
  up ip link set eth0.10  up || true
  up ip link set eth0.30  up || true
  up ip link set eth0.100 up || true
auto eth0.40
iface eth0.40 inet static
  address 192.168.40.$nodeId
  netmask 255.255.255.0
  gateway 192.168.40.254
EOF

}

for node in "${nodes[@]}" ; do
  echo -n "${node}..."
  nodeHostName="$node"
  nodeId="${node##*-}"
  nodeNetworkCfg="$(genNodeNetworkConfig "$nodeId")"
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
  export nodeHostName nodeProvisionSh serverToken serverPassword nodeNetworkCfg
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

