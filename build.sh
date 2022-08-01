#!/usr/bin/env bash
#
# TODO make this idempotent
set -eEuo pipefail

k8sHost="rancher@192.168.40.1"
k8sVip="192.168.40.10"
kubeDir="$HOME/.kube"
kubeCfg="$kubeDir/config"
sealedSecret="sealed-secrets-keysnghr"
promCrdVersion="v0.57.0"
waitTimeout=360s

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
  sed -i '/^\( *server: https:..\).*:6443$/ s//\1'"$addr"':6443/' "$kubeConfig"
}

function restoreSealedSecretsMasterKey {
  if ! kubectl -n kube-system get secret "$sealedSecret" > /dev/null 2>&1 ; then
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
    --for=condition=Ready \
    --timeout="$waitTimeout"
}

function installMultus {
  local numberAvailable=0

  kustomize build --enable-helm cluster-critical/multus/ \
    | kubectl  apply -f -
  # TODO update kubectl wait when availabe in k8s 1.25
  while sleep 10s ; do 
    numberAvailable="$(kubectl -n kube-system get daemonsets.apps kube-multus-ds -o json \
      | jq '.status.numberAvailable')"
    if [[ "${numberAvailable:-0}" -gt 0 ]] ; then
      break
    fi
  done
  kustomize build cluster-critical/multus/nads/ \
    | kubectl  apply -f -

}

function configureCertManager {
  kustomize build cluster-critical/cert-manager/ \
    | kubectl  apply -f -
  kubectl -n cert-manager wait clusterissuers.cert-manager.io \
    --all --for=condition=ready \
    --timeout="$waitTimeout"
}

function configureTraefik {
  # restore wildcard cert secret first, avoid hammering LE
  # TODO schedule backup
  kubectl -n kube-system wait deployment sealed-secrets-controller \
    --for=condition=Available \
    --timeout="$waitTimeout"
  kubectl apply -f \
    cluster-critical/traefik/wildcard-s-chaosengine-net-tls-sealedsecret.yaml
  kustomize build cluster-critical/traefik/ \
    | kubectl  apply -f -
  kubectl wait \
    -f cluster-critical/traefik/wildcard.s.chaosengine.net.yaml \
    --for=condition=ready \
    --timeout="$waitTimeout"
}

function configureArgoCD {
  # wait for Traefik to come up before installing IngressRoute so `argocd login` works
  kubectl -n kube-system wait deployment \
    --selector=app.kubernetes.io/name=traefik \
    --for=condition=Available=True \
    --timeout="$waitTimeout"
  kustomize build cluster-critical/argocd/ | kubectl  apply -f -
  kubectl -n argocd wait deployment \
    --selector=app.kubernetes.io/name=argocd-server \
    --for=condition=Available=True \
    --timeout="$waitTimeout"
  echo "Updating initial ArgoCD password"
  cluster-critical/argocd/update-initial-admin-passwd.sh
}

function installCriticalHelmCharts {
  find cluster-critical -type f -name '*-helmchart.yaml' -print0 \
    | xargs -r0 -n1 kubectl apply -f 
  # wait for HelmChart install jobs to complete
  kubectl -n kube-system get helmcharts -o json \
    | jq -r '.items[].status.jobName' \
    | xargs -P0 -n1 \
        kubectl -n kube-system wait job \
	  --for=condition=complete \
          --timeout="$waitTimeout"
}

function installOLM {
  pushd cluster-critical/olm
  ./manage.sh install || true
  popd
}

function prometheusCrdWorkaround {
  cluster-workloads/monitoring/kube-prom-stack/force-update-crds.sh "$promCrdVersion"
}

function wipeOldSshKnownHosts {
  # TODO central source for node defs
  for node in m900-{1,2,3} 192.168.40.{1,2,3} ; do
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R $node
  done
}

function run {
  echo "############### $1 #########################"
  "$@"
}

# main
run wipeOldSshKnownHosts
run retrieveKubeConfig
run restoreSealedSecretsMasterKey "${1:-sealed-secrets-master-key-secret.yaml}"
# install Multus then Cilium
run installMultus
run installCilium
run installCriticalHelmCharts
run installOLM  # TODO replace apps with operators where available
run configureCertManager  # required for `argocd login`
run configureTraefik  # required for `argocd login`
run configureArgoCD
run prometheusCrdWorkaround  # run this before ArgoCD tries to install it
run applyArgoCdAppOfApps "${2:-cluster-apps.yaml}"

echo "wait for kube-vip to be up..."
kubectl -n kube-system wait pod \
  --selector=app.kubernetes.io/name=kube-vip-ds \
  --for=condition=Ready \
  --timeout="$waitTimeout"
run updateKubeConfigServer "$k8sVip" "$kubeCfg"
run : DONE
