#!/usr/bin/env bash
#
# https://github.com/bitnami-labs/sealed-secrets#usage
# TODO support kubeseal --scope cluster-wide 
set -eEuo pipefail

namespace="${1:?arg1 is namespace}"
secretName="${2:?arg2 is secret name}"
secretFile="${3:-/dev/stdin}"

kubectl create secret generic "${secretName}" \
  -n "${namespace}" \
  --dry-run=client \
  --from-file="${secretFile}" \
  -o json \
  | tee "${secretName}-secret.json" \
  | kubeseal \
    -n "${namespace}" \
  > "${secretName}-sealedsecret.json"
