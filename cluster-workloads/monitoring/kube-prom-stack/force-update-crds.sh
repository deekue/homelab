#!/usr/bin/env bash
# https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/README.md#from-35x-to-36x
set -eEuo pipefail

crdVersion="${1:?arg1 is CRD version. last was v0.57.0}"
baseUrl="https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${crdVersion}/example/prometheus-operator-crd"

crds=(
monitoring.coreos.com_alertmanagerconfigs.yaml
monitoring.coreos.com_alertmanagers.yaml
monitoring.coreos.com_podmonitors.yaml
monitoring.coreos.com_probes.yaml
monitoring.coreos.com_prometheuses.yaml
monitoring.coreos.com_prometheusrules.yaml
monitoring.coreos.com_servicemonitors.yaml
monitoring.coreos.com_thanosrulers.yaml
)

for crd in "${crds[@]}" ; do
  echo $crd
  kubectl apply \
    --server-side \
    -f "$baseUrl/$crd"
done

