#!/usr/bin/env bash
#
#
set -eEuo pipefail

manifestUrl="$(cat kube-vip-cloud-controller.url)"
manifestFile="kube-vip-cloud-controller.yaml"

curl -fsSLo "$manifestFile" "$manifestUrl"
git diff "$manifestFile"
