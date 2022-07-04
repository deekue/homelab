#!/usr/bin/env bash
#
# TODO make this idempotent
set -eEuo pipefail

k8sHost="rancher@192.168.40.1"
k8sVip="192.168.40.10"
kubeDir="$HOME/.kube"
kubeCfg="$kubeDir/config"

function retrieveKubeConfig {
  tempFile="$kubeDir/config.$(date +%Y%m%d%H%M%S)"

  mkdir -p "$kubeDir"
  scp "$k8sHost":/etc/rancher/k3s/k3s.yaml "$tempFile"
  updateKubeConfigServer "${k8sHost##*@}" "$tempFile"
  install -C -m 0600 --backup=t "$tempFile" "$kubeCfg"
}

function updateKubeConfigServer {
  local -r addr="${1:?arg1 is server address}"
  local -r kubeConfig="${2:?arg2 is kube/config}"

  # server: https://192.168.40.10:6443
  sed -i '/^\( *server: https:..\).*:6443$/ s//\1'$addr':6443/' "$kubeConfig"
}

function restoreSealedSecretsMasterKey {
  kubectl apply -f "${1:?arg1 is Sealed Secrets master key}"
  # get the key to test for successful apply
  kubectl -n kube-system get secret sealed-secrets-keysnghr
}

function applyArgoCdAppOfApps {
  kubectl apply -f "${1:?arg1 is cluster-apps.yaml}"
}

function installCilium {
  kustomize build --enable-helm cluster-critical/cilium/ | kubectl  apply -f -
}

function installMultus {
  kustomize build --enable-helm cluster-critical/multus/ | kubectl  apply -f -
}

function configureArgoCD {
  # wait for Traefik to come up before installing IngressRoute so `argocd login` works
  kubectl -n kube-system wait pod \
    --selector=app.kubernetes.io/name=traefik \
    --for=condition=Ready
  kubectl apply -f cluster-critical/argocd
  # TODO retrieve password automagically
  cluster-critical/argocd/update-initial-admin-passwd.sh
}

function installCriticalHelmCharts {
  find cluster-critical -type f -name '*-helmchart.yaml' | xargs -n1 kubectl apply -f 
}

function installOLM {
  cluster-critical/olm/manager.sh install
}

# main
retrieveKubeConfig
restoreSealedSecretsMasterKey "${1:-sealed-secrets-master-key-secret.yaml}"
# install Multus then Cilium
installMultus
installCilium
# TODO switch to Kustomise HelmGen so install progress is visible in ArgoCD
installCriticalHelmCharts
#installOLM  # TODO replace apps with operators where available
configureArgoCD
applyArgoCdAppOfApps "${2:-cluster-apps.yaml}"

# TODO confirm kube-vip is up and update .kube/config
updateKubeConfigServer "192.168.40.10" "$kubeCfg"
