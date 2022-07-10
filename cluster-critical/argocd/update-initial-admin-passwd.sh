#!/usr/bin/env bash
#
#
set -eEuo pipefail

argoServer="${1:-argocd.s.chaosengine.net}"
initialPassword="$(kubectl --namespace argocd -o json \
    get secret argocd-initial-admin-secret \
    | jq -r '.data.password' \
    | base64 -d \
    || true)"
if [[ -z "$initialPassword" ]] ; then
  exit 0  # not an error if we've run before
fi

argocd login "$argoServer" \
  --username admin \
  --password "$initialPassword"
argocd account update-password \
  --account admin \
  --current-password "$initialPassword"
kubectl -n argocd delete secret argocd-initial-admin-secret
