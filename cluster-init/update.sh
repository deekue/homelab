#!/usr/bin/env bash
#
#
set -eEuo pipefail

manifestUrl="$(cat sealed-secrets-manifest.url)"
manifestFile="controller.yaml"
kubesealUrl="$(cat sealed-secrets-kubeseal.url)"
kubesealPath="/usr/local/bin"

case "${1:-}" in
  m|manifest)
    curl -fsSLo "$manifestFile" "$manifestUrl"
    # TODO auto-commit to git if different?
    ;;
  k|kubeseal)
    tempdir="$(mktemp -d)"
    curl -fsSL "$kubesealUrl" \
      | tar xzf - -C "${tempdir}" kubeseal
    install -v -o root -g root -m 0755 -C --backup=numbered \
      "${tempdir}/kubeseal" "${kubesealPath}/kubeseal"
    ;;
  *)
    echo "Usage: $(basename -- "$0") <m|manifest|k|kubeseal>" >&2
    exit 1
    ;;
esac
