#!/usr/bin/env bash
#
# manage OLM install

set -eEuo pipefail

baseURL="https://github.com/operator-framework/operator-lifecycle-manager/releases/download"
files=(
  olm.yaml
  crds.yaml
  )

function downloadAndSplit {
  local -r version="${1:?arg1 is version}"
  local -r url="$baseURL/$version"

  for file in "${files[@]}" ; do
    curl -fsSLo "$file" "$url/$file"
  done

  if command -v yq > /dev/null ; then
    echo "yq required. for example:" >&2
    echo "pip3 install --user yq" >&2
    exit 1
  fi
  # required to (un)install PackageServer separately
  # https://github.com/operator-framework/operator-lifecycle-manager/issues/1304
  # https://gist.github.com/offlinehacker/856b64ec5ad5ab3829bf01f1fb29958d
  yq -y 'select(.metadata.name != "packageserver")' olm.yaml > deployment.yaml
  yq -y 'select(.metadata.name == "packageserver")' olm.yaml > packageserver.yaml
}

function forceRemoveNamespace {
  local -r ns="${1:?arg1 is namespace}"

  # this is dangerous and only to be used as a last resort
  # https://github.com/operator-framework/operator-lifecycle-manager/issues/1304
  # https://stackoverflow.com/questions/52369247/namespace-stuck-as-terminating-how-i-removed-it/59667608#59667608
  kubectl get namespace "$ns" -o json \
    | jq '.spec = {"finalizers":[]}' \
    | kubectl replace --raw /api/v1/namespaces/"$ns"/finalize -f -
}

function generateSubscriptionManifest {
  local -r operatorName="${1:?arg1 is operator name}"
  local -r targetNamespace="${2:?arg2 is target namespace for operator}"
  local    channel="${3:-}"
  local    installPlanApproval="${4:-}"

  local -r package="$(kubectl get packagemanifest "$operatorName" -o json)"
  if [[ -z "$package" ]] ; then
    echo "failed to get packagemanifest $operatorName" >&2
    exit 1
  fi

  catalogSource="$(jq -r '.status.catalogSource | @sh' <<< "$package")"
  sourceNamespace="$(jq -r '.metadata.namespace | @sh' <<< "$package")"
  if [[ -z "$channel" ]] ; then
    channel="$(jq -r '.status.defaultChannel | @sh' <<< "$package")"
  fi
  if [[ -z "$installPlanApproval" ]] ; then
    installPlanApproval="Manual"  # safe default
  else
    installPlanApproval="${installPlanApproval,,}"  # lowercase
    case "${installPlanApproval}" in
      m|manual)
        installPlanApproval=Manual
	;;
      a|auto|automatic)
        installPlanApproval=Automatic
	;;
      *)
	echo "installPlanApproval is [m]anual|[a]utomatic" >&2
	echo
	usage
	;;
    esac
  fi

  cat <<EOF
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $operatorName
  namespace: $targetNamespace
spec:
  channel: $channel
  name: $operatorName
  source: $catalogSource
  sourceNamespace: $sourceNamespace
  installPlanApproval: $installPlanApproval
EOF
}

function usage {
  cat <<EOF >&2
Usage: $(basename -- "$0") <command> [options]

commands:
  d|download <version>	downlod manifests, and split olm.yaml
  i|install		install OLM on a new cluster
  u|update		update OLM
  r|remove		remove OLM
  s|subscription <args> generate Subscription manifest
                        Args: <name> <targetNS> [channel] [installPlanApproval]

EOF
  exit 1
}

case "${1:-}" in
  d|download)
    downloadAndSplit "${2:?arg2 for download is version. e.g. v0.21.2}"
    ;;
  i|install)
    if kubectl get ns olm 2>/dev/null ; then
      echo "olm namespace detected, refusing to install" >&2
      exit 2
    fi
    kubectl create -f crds.yaml
    kubectl wait --for=condition=Established -f crds.yaml
    kubectl create -f deployment.yaml
    kubectl create -f packageserver.yaml
    ;;
  u|update)
    # https://github.com/operator-framework/operator-lifecycle-manager/issues/2767
    # https://github.com/operator-framework/operator-lifecycle-manager/issues/2778
    kubectl apply -f crds.yaml --server-side=true
    kubectl wait --for=condition=Established -f crds.yaml
    kubectl apply -f deployment.yaml
    kubectl apply -f packageserver.yaml
    ;;
  r|remove)
    kubectl delete -f packageserver.yaml || true
    kubectl delete -f deployment.yaml || true
    kubectl delete -f crds.yaml || true
    ;;
  ns)
    forceRemoveNamespace olm || true
    forceRemoveNamespace operators || true
    ;;
  s|subscription)
    shift
    generateSubscriptionManifest "$@"
    ;;
  *)
    usage
    ;;
esac

