#!/usr/bin/env bash
#
#

podName="$(kubectl -n rook-ceph get pod -l app=rook-ceph-tools -o json \
  | jq -r '.items[].metadata.name')"

kubectl -n rook-ceph exec -it "${podName:?failed to find rook-ceph tools pod}" -- bash

