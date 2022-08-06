#!/usr/bin/env bash
#
# capture an existing secret
set -eEuo pipefail

namespace="${1:?arg1 is namespace}"
secretName="${2:?arg2 is secret name}"

kubectl -n "$namespace" get secret "$secretName" -o yaml \
  | yq 'del(.metadata.uid, .metadata.resourceVersion)' \
  | kubeseal -n "$namespace" -o yaml \
      -w "${secretName}-sealedsecret.yaml"
