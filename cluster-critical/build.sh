#!/usr/bin/env bash
#
#
set -eEuo pipefail

depsOrder=(
sealed-secrets
cert-manager
longhorn-system
nfs
traefik
argocd
argocd-apps
)

# TODO maybe replace this with an "app of apps"
# https://github.com/argoproj/argocd-example-apps/tree/master/apps
function genArgoCdApps {
  pushd `pwd`/argocd-apps

  # generate kustomization.yaml header, for ordering
  cat <<EOF > kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd

resources:
EOF

  # generate argocd application manifests
  for app in "${depsOrder[@]}" ; do
    if [[ "$app" == "argocd-apps" ]] ; then
      continue  # avoid recursion
    fi
    export app 
    envsubst \
      < argocd-app.yaml.tmpl \
      > "${app}.yaml" 

    # add to Kustomize resource list
    echo "  - $app" >> kustomization.yaml
  done
  popd
}

function applyManifestsInOrder {
  for svc in "${depsOrder[@]}" ; do
    if [[ -r "$svc/kustomization.yaml" ]] ; then
      kustomise build "$svc" | kubectl apply -f -
    else
      kubectl apply -f "$svc"
    fi
  done
}

function restoreSealedSecretsMasterKey {
  kubectl apply -f "${1:?arg1 is Sealed Secrets master key}"
  # get the key to test for successful apply
  kubectl -n kube-system get secret sealed-secrets-keysnghr
}

# main
#restoreSealedSecretsMasterKey
genArgoCdApps
#applyManifestsInOrder
