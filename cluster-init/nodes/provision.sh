#!/bin/bash
#
# this runs on every boot, so needs to be idempotent
set -euo pipefail

longhornUseWholeDisk=false
longhornDisk=/dev/sda
longhornDir=/var/lib/longhorn

if [[ ! -r /etc/rancher/k3s/registries.yaml ]] ; then
  echo "get SSL CA cert for private registry cache"
  cat <<-EOF > /etc/rancher/k3s/registries.yaml
	mirrors:
	  docker.io:
	endpoint:
	  -  "https://192.168.40.238:3128"
	EOF
  wget -O - -q "http://192.168.40.238:3128/ca.crt" \
    | tee -a /etc/ssl/certs/ca-certificates.crt
fi

echo "setup AMT serial console"
grep -q ttyS4 /etc/inittab || echo 'ttyS4::respawn:/sbin/getty -L 115200 ttyS4 vt100' >> /etc/inittab
grep -q ttyS4 /etc/securetty || echo 'ttyS4' >> /etc/securetty

echo "setup disk for Longhorn"
if [[ -b "${longhornDisk}" ]] ; then
  if [[ "${longhornUseWholeDisk}" == "true" ]] ; then
    if [[ ! -b "${longhornDisk}1" ]] ; then
      echo "  using whole disk ${longhornDisk} for Longhorn data"
      cat <<-EOF | parted "${longhornDisk}"
	print
	mklabel gpt
	mkpart primary ext4 0% 100%
	EOF
      partprobe
    fi
  else
    partStart="$(parted -m "${longhornDisk}" unit GB print free \
      | grep ':free;' \
      | grep -v '0.00GB:free;$' \
      | cut -f2 -d: \
      || true)"
    if [[ -n "${partStart}" ]] ; then
      echo -n "not using whole disk, finding free space..."
      parted "${longhornDisk}" \
	mkpart primary ext4 "$partStart" 100%
      partprobe
      echo "done."
    fi
  fi

  # do we have an empty partition?
  longhornPartNum="$(parted -m "${longhornDisk}" unit GB print free \
    | grep -E '::[^:]*:;$' \
    | cut -f1 -d: \
    || true)"
  if [[ -n "${longhornPartNum}" ]] ; then
    longhornPart="${longhornDisk}${longhornPartNum}"  # TODO support other parttion naming. eg nvme0n1p1
    echo "formating ${longhornPart} with ext4"
    # TODO optimal ext4 options?
    mke2fs -vF -t ext4 -L longhorn-data -m0 "${longhornDisk}${longhornPartNum}"
  else
    # do we have an ext4 partition already
    longhornPartNum="$(parted -m "${longhornDisk}" unit GB print free \
      | grep -E ':ext4:[^:]*:;$' \
      | cut -f1 -d: \
      || true)"
    if [[ -n "${longhornPartNum}" ]] ; then
      longhornPart="${longhornDisk}${longhornPartNum}"  # TODO support other parttion naming. eg nvme0n1p1
    else
      echo "ERROR: partition not found/created on ${longhornDisk} for Longhorn data" >&2
      exit 1
    fi
  fi
  if [[ ! -d "${longhornDir}" ]] ; then
    echo "making dir ${longhornDir}"
    mkdir -p "${longhornDir}"
  fi
  if [[ -b "${longhornPart}" ]] ; then
    if ! grep -q "${longhornPart}" /etc/fstab ; then
      echo "updating /etc/fstab"
      grep -v "${longhornDir}" /etc/fstab \
	> /etc/fstab.tmp
      echo "${longhornPart}	${longhornDir}	ext4	nodiratime,relatime 0 0" \
	>> /etc/fstab.tmp
      mv /etc/fstab.tmp /etc/fstab
    fi
    echo "mounting ${longhornPart} on ${longhornDir}"
    mount -a
    mount | grep "${longhornPart}"
  fi
fi

