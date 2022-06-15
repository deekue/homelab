#!/bin/bash
#
#
set -euo pipefail

longhornUseWholeDisk=false
longhornDisk=/dev/sda
longhornPart=${longhornDisk}2
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
    if [[ "${longhornUseWholeDisk}" == "true" ]] ; then
      cat <<-EOF | parted "${longhornDisk}"
	  print
	  mklabel gpt
	  mkpart primary ext4 0% 100%
	  EOF
    else
      # create 2nd partition from free space
      partStart="$(parted -m "${longhornDisk}" unit GB print free \
	| grep ':free;' \
	| grep -v '0.00GB:free;$' \
	| cut -f2 -d:)"
      if [[ -n "${partStart}" ]] ; then
        parted "${longhornDisk}" \
	  mkpart primary ext4 "$partStart" 100%
      fi
    fi
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

