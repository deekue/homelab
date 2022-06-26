#!/usr/bin/env bash
#
#
set -eEuo pipefail

depsOrder=(
kube-system/sealed-secrets
cert-manager/cert-manager
longhorn-system/longhorn-system
kube-system/traefik
argocd/argocd
argocd/argocd-apps
)

# TODO maybe replace this with an "app of apps"
# https://github.com/argoproj/argocd-example-apps/tree/master/apps
function genArgoCdApps {
  pushd `pwd`/argocd-apps > /dev/null

  # generate kustomization.yaml header, for ordering
  cat <<EOF > kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd

resources:
EOF

  # generate argocd application manifests
  for svc in "${depsOrder[@]}" ; do
    namespace="${svc%%/*}"
    app="${svc##*/}"
    appFile="${app}.yaml"
    if [[ "$app" == "argocd-apps" ]] ; then
      continue  # avoid recursion
    fi
    echo "Generating ArgoCD Application for $app in $namespace"
    export app namespace  # export for envsubst
    envsubst \
      < argocd-app.yaml.tmpl \
      > "${appFile}"

    # add to Kustomize resource list
    echo "  - $appFile" >> kustomization.yaml
  done
  popd > /dev/null
}

function applyManifestsInOrder {
  for svc in "${depsOrder[@]}" ; do
    app="${svc##*/}"
    if [[ -r "$app/kustomization.yaml" ]] ; then
      kustomise build "$app" --reorder=none \
	| kubectl apply -f -
    else
      kubectl apply -f "$app"
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
