#!/usr/bin/env bash
#
# https://forums.rancher.com/t/traefik-dashboard-404/36180

set -eEuo pipefail

case "${1:-}" in
  e|enable)
    kubectl -n kube-system \
      patch ingressroute traefik-dashboard \
      --type=merge \
      -p '{"spec":{"entryPoints":["websecure"]}}'
    ;;
  d|disable)
    kubectl -n kube-system \
      patch ingressroute traefik-dashboard \
      --type=merge \
      -p '{"spec":{"entryPoints":["traefik"]}}'
    ;;
  s|status)
    kubectl -n kube-system \
      get ingressroute traefik-dashboard \
      -o jsonpath='{.spec.entryPoints}'
    echo
    ;;
  *)
    echo "Usage: $(basename -- "$0") <e|enable|d|disable|s|status>" >&2
    exit 1
    ;;
esac
