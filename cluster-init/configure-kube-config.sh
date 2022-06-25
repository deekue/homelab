#!/usr/bin/enb bash
#
#
set -eEuo pipefail

k8sHost="k8s.s"
kubeDir="$HOME/.kube"
kubeCfg="$kubeDir/config"
tempFile="$kubeDir/config.$(date +%Y%m%d%H%M%S)"

mkdir -p "$kubeDir"
scp "$k8sHost":/etc/rancher/k3s/k3s.yaml "$tempFile"
install -C -m 0600 --backup=t "$tempFile" "$kubeCfg"
