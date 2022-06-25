#!/usr/bin/env bash
#
#
set -eEuo pipefail

kubectl apply -f "${1:?arg1 is Sealed Secrets master key}"
kubectl -n kube-system get secret sealed-secrets-keysnghr
kubectl apply -f .
