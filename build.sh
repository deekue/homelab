#!/usr/bin/env bash
#
#
set -eEuo pipefail

function retrieveKubeConfig {
  k8sHost="k8s.s"
  kubeDir="$HOME/.kube"
  kubeCfg="$kubeDir/config"
  tempFile="$kubeDir/config.$(date +%Y%m%d%H%M%S)"

  mkdir -p "$kubeDir"
  scp "$k8sHost":/etc/rancher/k3s/k3s.yaml "$tempFile"
  install -C -m 0600 --backup=t "$tempFile" "$kubeCfg"
}

function restoreSealedSecretsMasterKey {
  kubectl apply -f "${1:?arg1 is Sealed Secrets master key}"
  # get the key to test for successful apply
  kubectl -n kube-system get secret sealed-secrets-keysnghr
}

function applyArgoCdAppOfApps {
  kubectl apply -f "${1:?arg1 is cluster-apps.yaml}"
}

# main
retrieveKubeConfig
restoreSealedSecretsMasterKey "${1:-sealed-secrets-master-key-secret.yaml}"
applyArgoCdAppOfApps "${2:-cluster-apps.yaml}"

