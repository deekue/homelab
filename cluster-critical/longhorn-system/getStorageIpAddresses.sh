
kubectl -n longhorn-system get pods \
    -l longhorn.io/component=instance-manager \
    -o json \
  | jq -r  '.items[].metadata.annotations."k8s.v1.cni.cncf.io/network-status"' \
  | jq -rs '.[] | .[] | select(.name == "kube-system/storage-macvlan-whereabouts") | .ips[0]'
