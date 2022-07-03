# homelab

WIP, YMMV, IANAL etc etc

this is my homelab, there are many like it but this one is mine.

## Hardware
* 3x Lenovo m900 Tiny
  * i5-6500
  * 16GB RAM
  * 500GB nVME boot drive
  * 500GB HDD
  * 1x 1GE NIC
* 1x franken-server
  * i5-6500
  * 32GB RAM 
  * 2x 500GB nVME boot drive
  * 2x 2TB HDD
  * 2x 1GE NIC
* Synology DS415+
  * 8GB RAM
  * 4x 6TB HDD
  * 2x 1GE NIC
* PiKVM v3
  * Ezcoo 4-port HDMI switch
* 2x Cyberpower PFC1500 UPS
* Network
  * Unifi USG-3P
  * 2x Unifi US-8-60W
  * 2x Unifi UAP-AC-Lite
  * USW-Flex-Mini
  * Netgear GS108T
  * 3x TP-Link TL-PA8010P
  * TP-Link TL-WPA8???
  * 2x Actiontec ECB6200

## Software

plan is to migrate all the services, Docker containers and scripts onto k8s
from the old server + Synology.

* k3s
* k3os (now deprecated, replacement TBD)
* Network
  * Cillium
  * Multus (to give some pods L2 access, like HomeAssistant to the IoT VLAN)
* Storage
  * Longhorn (replicated PVs)
  * NFS to Synology (backups, bulk media)
* Infra
  * cert-manager
  * ArgoCD
  * OLM
  * Sealed Secrets
* [various other workloads](cluster-workloads/) 


