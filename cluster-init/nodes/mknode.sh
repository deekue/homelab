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
kubeVipAddr="$(yq -rs '.[] 
   | select(.kind == "DaemonSet") 
   | .spec.template.spec.containers[0].env[] 
   | select(.name == "address") 
   | .value' "$kubevipFile")"
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
auto trunk0
iface trunk0 inet static
  address 192.168.40.$nodeId
  netmask 255.255.255.0
  gateway 192.168.40.254
  post-up ip link add link trunk0 name trunk0.10  type vlan id 10  || true
  post-up ip link add link trunk0 name trunk0.30  type vlan id 30  || true
  post-up ip link add link trunk0 name trunk0.100 type vlan id 100 || true
  post-up ip link set trunk0.10  up || true
  post-up ip link set trunk0.30  up || true
  post-up ip link set trunk0.100 up || true
auto storage0
iface storage0 inet manual
  # put host address on a macvlan link so host<->container works
  # required for Longhorn/iscsiadm interaction
  up ip link set storage0 up
  up ip link add shim-storage0 link storage0 type macvlan mode bridge
  up ip addr add 192.168.50.$nodeId/24 dev shim-storage0
  up ip link set shim-storage0 up
EOF

}

# https://gist.github.com/JanKoppe/83f0e273c12ecd37b997f2317d638cdc
function genNodeMacTab {
  local -r nodeId="${1:?arg1 is nodeId}"
  local onboard usb

  case "$nodeId" in
    1)
      onboard="00:23:24:b6:a4:2a"
      usb="00:e0:4c:68:20:60"
      ;;
    2)
      onboard="00:23:24:ac:f7:99"
      usb="00:e0:4c:68:4e:df"
      ;;
    3)
      onboard="00:23:24:c7:22:3a"
      usb="00:e0:4c:68:4e:16"
      ;;
  esac
  cat <<EOF | writeFilesHeader /etc/mactab "0644" "/dev/stdin"
trunk0 $onboard
storage0 $usb
EOF

}

for node in "${nodes[@]}" ; do
  echo -n "${node}..."
  nodeHostName="$node"
  nodeId="${node##*-}"
  nodeNetworkCfg="$(genNodeNetworkConfig "$nodeId")"
  nodeMacTab="$(genNodeMacTab "$nodeId")"
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
  export nodeHostName nodeProvisionSh nodeNetworkCfg nodeMacTab
  export serverToken serverPassword
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

