#!/bin/bash
#
#
set -eEuo pipefail

namespace="${1:?arg1 is namespace}"
cert="${2:?arg2 is certificate}"

secretName="$(kubectl -n "$namespace" get certificate "$cert" -o yaml \
  | yq -r '.spec.secretName')"

kubectl -n "$namespace" get secret "$secretName" -o yaml \
  | yq 'del(.metadata.uid, .metadata.resourceVersion)' \
  | kubeseal -n "$namespace" -o yaml \
  > "${secretName}-sealedsecret.yaml"
