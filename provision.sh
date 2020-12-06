#!/bin/bash
#
#
set -euo pipefail

longhornDisk=/dev/sda
longhornPart=${longhornDisk}1
longhornDir=/var/lib/longhorn

# get SSL CA cert for private registry cache
if [[ ! -r /etc/rancher/k3s/registries.yaml ]] ; then
  cat <<-EOF > /etc/rancher/k3s/registries.yaml
	mirrors:
	  docker.io:
	endpoint:
	  -  "https://192.168.136.238:3128"
	EOF
  wget -O - -q "http://192.168.136.238:3128/ca.crt" \
    | tee -a /etc/ssl/certs/ca-certificates.crt
fi

# setup serial console
grep -q ttyS4 /etc/inittab || echo 'ttyS4::respawn:/sbin/getty -L 115200 ttyS4 vt100' >> /etc/inittab
grep -q ttyS4 /etc/securetty || echo 'ttyS4' >> /etc/securetty

# setup disk for Longhorn
if [[ -b "${longhornDisk}" ]] ; then
  if [[ ! -b "${longhornPart}" ]] ; then
    cat <<-EOF | parted "${longhornDisk}"
	print
	mklabel gpt
	mkpart primary ext4 0% 100%
	EOF
    partprobe
    # TODO optimal ext4 options?
    mke2fs -vF -t ext4 -L longhorn-data -m0 "${longhornPart}"
  fi
  if [[ ! -d "${longhornDir}" ]] ; then
    mkdir -p "${longhornDir}"
  fi
  grep -q "${longhornDir}" /etc/fstab \
    || echo "${longhornPart}	${longhornDir}	ext4	nodiratime,relatime	0 0" >> /etc/fstab
  mount -a
fi

