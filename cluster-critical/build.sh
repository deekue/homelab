#!/usr/bin/env bash
#
#
set -eEuo pipefail

function restoreSealedSecretsMasterKey {
  kubectl apply -f "${1:?arg1 is Sealed Secrets master key}"
  # get the key to test for successful apply
  kubectl -n kube-system get secret sealed-secrets-keysnghr
}

function applyArgoCdAppOfApps {
  kubectl apply -f "${1:?arg1 is cluster-apps.yaml}"
}

# main
#restoreSealedSecretsMasterKey "${1:?arg1 is Sealed Secrets master key}"
applyArgoCdAppOfApps "${2:-../cluster-apps.yaml}"
