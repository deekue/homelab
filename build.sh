#!/usr/bin/env bash
#
# TODO make this idempotent
set -eEuo pipefail

promCrdVersion="v0.57.0"
waitTimeout=360s

function installSealedSecrets {
  local -r masterKey="${1:?arg1 is Sealed Secrets master key}"
  local -r sealedSecret="$(yq -r .items[].metadata.name "$masterKey")"

  if ! kubectl -n kube-system get secret "$sealedSecret" > /dev/null 2>&1 ; then
    kubectl apply -f "$masterKey"
    # get the key to test for successful apply
    kubectl -n kube-system get secret sealed-secrets-keysnghr
  fi
  kustomize build --enable-helm cluster-critical/sealed-secrets/ | kubectl  apply -f -
}

function installCRDs {
  manifest="$(mktemp)"
  kustomize build --enable-helm "cluster-critical/crds/" \
    > "$manifest" 
  kubectl apply -f "$manifest"
  kubectl wait -f "$manifest" \
    --for=condition=Established \
    --timeout="$waitTimeout"
  rm "$manifest"

  run prometheusCrdWorkaround  # run this before ArgoCD tries to install it
}

function installKustomizeBuild {
  local -r cfgDir="${1:?arg1 is Kustomize file/dir}"

  kustomize build --enable-helm "$cfgDir" \
    | kubectl apply -f -
}

function installCilium {
  kustomize build --enable-helm cluster-critical/cilium/ \
    | kubectl  apply -f -
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
    numberAvailable="$(kubectl -n kube-system get daemonsets.apps multus -o json \
      | jq '.status.numberAvailable')"
    if [[ "${numberAvailable:-0}" -gt 0 ]] ; then
      break
    fi
  done
}

function applyArgoCdAppOfApps {
  kubectl apply -f "${1:?arg1 is cluster-apps.yaml}"
  # TODO wait for cluster-apps to go Healthy/Synced
}

function configureCertManager {
  kustomize build --enable-helm cluster-critical/cert-manager/ \
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
  kustomize build --enable-helm cluster-critical/traefik/ \
    | kubectl  apply -f -
  kubectl wait \
    -f cluster-critical/traefik/wildcard.s.chaosengine.net.yaml \
    --for=condition=ready \
    --timeout="$waitTimeout"
}

function configureArgoCD {
  kustomize build --enable-helm cluster-critical/argocd/ \
    | kubectl  apply -f -
  kubectl -n kube-system wait deployment \
    --selector=app.kubernetes.io/name=traefik \
    --for=condition=Available=True \
    --timeout="$waitTimeout"
  kubectl -n argocd wait deployment \
    --selector=app.kubernetes.io/name=argocd-server \
    --for=condition=Available=True \
    --timeout="$waitTimeout"
  echo "Updating initial ArgoCD password"
  cluster-critical/argocd/update-initial-admin-passwd.sh
}

function installOLM {
  pushd cluster-critical/olm
  ./manage.sh install || true
  popd
}

function prometheusCrdWorkaround {
  cluster-workloads/monitoring/kube-prom-stack/force-update-crds.sh "$promCrdVersion"
}

function run {
  echo "############### $1 #########################"
  "$@"
}

# main
run installCilium
run installCRDs
run installSealedSecrets "${1:-sealed-secrets-master-key-secret.yaml}"
run installMultus  # required before rook-ceph
run installOLM  # TODO replace apps with operators where available
run configureCertManager  # required for Traefik
run configureTraefik  # required for `argocd login`
run configureArgoCD
run applyArgoCdAppOfApps "${2:-cluster-apps.yaml}"
run : DONE
