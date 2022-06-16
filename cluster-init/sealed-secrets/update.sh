#!/usr/bin/env bash
#
#
set -eEuo pipefail

manifestUrl="$(cat sealed-secrets-manifest.url)"
manifestFile="controller.yaml"

curl -fsSLo "$manifestFile" "$manifestUrl"
