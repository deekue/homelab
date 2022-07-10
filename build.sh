#!/usr/bin/env bash
#
# TODO make this idempotent
set -eEuo pipefail

k8sHost="rancher@192.168.40.1"
k8sVip="192.168.40.10"
kubeDir="$HOME/.kube"
kubeCfg="$kubeDir/config"
sealedSecret="sealed-secrets-keysnghr"

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
  if ! kubectl -n kube-system get secret "$sealedSecret" > /dev/null ; then
    kubectl apply -f "${1:?arg1 is Sealed Secrets master key}"
    # get the key to test for successful apply
    kubectl -n kube-system get secret sealed-secrets-keysnghr
  fi
}

function applyArgoCdAppOfApps {
  kubectl apply -f "${1:?arg1 is cluster-apps.yaml}"
  # TODO wait for cluster-apps to go Healthy/Synced
}

function installCilium {
  kustomize build --enable-helm cluster-critical/cilium/ | kubectl  apply -f -
  kubectl -n kube-system wait pod \
    --selector=k8s-app=cilium \
    --for=condition=Ready
}

function installMultus {
  kustomize build --enable-helm cluster-critical/multus/ | kubectl  apply -f -
  kubectl -n kube-system wait pod \
    --selector=app=multus \
    --for=condition=Ready
}

function configureCertManager {
  kustomize build cluster-critical/cert-manager/ | kubectl  apply -f -
  kubectl -n cert-manager wait clusterissuers.cert-manager.io \
    --all --for=condition=ready
}

function configureTraefik {
  kustomize build cluster-critical/traefik/ | kubectl  apply -f -
  kubectl wait -f cluster-critical/traefik/wildcard.s.chaosengine.net.yaml \
    --for=condition=ready
}

function configureArgoCD {
  # wait for Traefik to come up before installing IngressRoute so `argocd login` works
  kubectl -n kube-system wait pod \
    --selector=app.kubernetes.io/name=traefik \
    --for=condition=Ready
  kustomize build cluster-critical/argocd/ | kubectl  apply -f -
  sleep 10  # TODO can't wait on a resource that doesn't exist yet
  kubectl -n argocd wait pod \
    --selector=app.kubernetes.io/name=argocd-server \
    --for=condition=Ready
  echo "Updating initial ArgoCD password"
  cluster-critical/argocd/update-initial-admin-passwd.sh
}

function installCriticalHelmCharts {
  find cluster-critical -type f -name '*-helmchart.yaml' \
    | xargs -n1 kubectl apply -f 
  # wait for HelmChart install jobs to complete
  kubectl -n kube-system get helmcharts -o json \
    | jq -r '.items[].status.jobName' \
    | xargs -P0 -n1 \
        kubectl -n kube-system wait job --for=condition=complete
}

function installOLM {
  pushd cluster-critical/olm
  ./manage.sh install || true
  popd
}

# main
retrieveKubeConfig
restoreSealedSecretsMasterKey "${1:-sealed-secrets-master-key-secret.yaml}"
# install Multus then Cilium
installMultus
installCilium
installCriticalHelmCharts
installOLM  # TODO replace apps with operators where available
configureCertManager  # required for `argocd login`
configureTraefik  # required for `argocd login`
configureArgoCD
applyArgoCdAppOfApps "${2:-cluster-apps.yaml}"

# wait for kube-vip to be up
kubectl -n kube-system wait pod \
  --selector=app.kubernetes.io/name=kube-vip-ds \
  --for=condition=Ready
updateKubeConfigServer "$k8sVip" "$kubeCfg"
