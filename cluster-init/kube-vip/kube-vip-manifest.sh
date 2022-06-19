#!/usr/bin/env bash
#
#
# TODO make the env vars options
#
# ref: https://kube-vip.chipzoller.dev/docs/installation/

KVIMAGE=ghcr.io/kube-vip/kube-vip
CONTAINER_RUNTIME="docker"
VIP="192.168.136.10"
INTERFACE="eth0"
KVVERSION=
BGP_AS=
BGP_ROUTER_ID=
BGP_PEERS=
KVRBAC_FILE="$HOME/.cache/kube-vip/rbac.yaml"
KVRBAC_URL="https://kube-vip.io/manifests/rbac.yaml"

if [[ -z "${KVVERSION}" ]] ; then
  export KVVERSION=$(curl -sSL https://api.github.com/repos/kube-vip/kube-vip/releases \
    | jq -r ".[0].name")
fi

function kube-vip {
  if [[ -z "$CONTAINER_RUNTIME" ]] ; then
    if command -v docker > /dev/null ; then
      CONTAINER_RUNTIME="docker"
    elif command -v ctr > /dev/null ; then
      CONTAINER_RUNTIME="containerd"
    else
      echo "ERROR: docker and ctr not found" >&2
      exit 2
    fi
  fi

  case "$CONTAINER_RUNTIME" in
    docker) 
      docker run --network host --rm "$KVIMAGE:$KVVERSION" "$@"
      ;;
    containerd)
      ctr run --rm --net-host "$KVIMAGE:$KVVERSION" vip /kube-vip "$@"
      ;;
    *)
      echo "ERROR: CONTAINER_RUNTIME must be docker or containerd" >&2
      exit 3
      ;;
  esac
}

function usage {
  cat <<EOF >&2
Usage: $(basename -- "$0") <static|daemonset> <arp|bgp> [options]
EOF
  exit 1
}

function ds_arp {
  kube-vip manifest daemonset \
      --interface "$INTERFACE" \
      --address "$VIP" \
      --inCluster \
      --taint \
      --controlplane \
      --services \
      --arp \
      --leaderElection \
      "$@"
}

function ds_bgp {
  kube-vip manifest daemonset \
      --interface "$INTERFACE" \
      --address "$VIP" \
      --inCluster \
      --taint \
      --controlplane \
      --services \
      --bgp \
      --localAS "$BGP_AS" \
      --bgpRouterID "$BGP_ROUTER_ID" \
      --bgppeers "$BGP_PEERS" \
      "$@"
}

function static_arp {
  kube-vip manifest pod \
      --interface "$INTERFACE" \
      --address "$VIP" \
      --controlplane \
      --services \
      --arp \
      --leaderElection \
      "$@"
}

function static_bgp {
  kube-vip manifest pod \
      --interface "$INTERFACE" \
      --address "$VIP" \
      --controlplane \
      --services \
      --bgp \
      --localAS "$BGP_AS" \
      --bgpRouterID "$BGP_ROUTER_ID" \
      --bgppeers "$BGP_PEERS" \
      "$@"
}

function emit_rbac {
  if [[ -r "$KVRBAC_FILE" ]] ; then
    echo "Using cached rbac.yaml from $KVRBAC_FILE" >&2
    cat "$KVRBAC_FILE"
  else
    mkdir -p "$(dirname "$KVRBAC_FILE")"
    curl -fsSL "$KVRBAC_URL" | tee "$KVRBAC_FILE"
  fi
  echo "---"
}

case "$1" in
  static)
    case "$2" in
      arp)
	shift 2
	static_arp "$@" ;;
      bgp)
	shift 2
	static_bgp "$@" ;;
      *)
	usage;;
    esac
    ;;
  ds|daemon|daemonset)
    emit_rbac
    case "$2" in
      arp)
	shift 2
	ds_arp "$@" ;;
      bgp)
	shift 2
	ds_bgp "$@" ;;
      *)
	usage;;
    esac
    ;;
  *)
    usage
    ;;
esac
