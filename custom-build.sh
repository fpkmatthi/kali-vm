#!/usr/bin/env bash
set -euo pipefail

SUPPORTED_ARCHITECTURES="amd64"
SUPPORTED_BRANCHES="kali-dev kali-last-snapshot kali-rolling"
SUPPORTED_DESKTOPS="e17 gnome i3 kde lxde mate xfce none"
SUPPORTED_TOOLSETS="default everything headless large none"
SUPPORTED_FORMATS="hyperv ova ovf qemu raw vagrant virtualbox vmware"
SUPPORTED_VARIANTS="generic hyperv qemu rootfs virtualbox vmware"

# Config
TARGET="vmware"
DISK_GB=150
DESKTOP="xfce"
TOOLSET="default"
TIMEZONE="Europe/Brussels"
HOSTNAME="fpkali"
DEBOS_MEMORY="4G" # RAM for the *build VM* (not the final VM's runtime)

# Ensure deps
command -v git >/dev/null || {
    echo "[!] git not found"
    exit 1
}
# You can use Docker or Podman; the wrapper script auto-detects.
if ! command -v docker >/dev/null && ! command -v podman >/dev/null; then
    echo "[!] Neither docker nor podman found. Install one of them first."
    exit 1
fi

# Build inside container (aka "build-docker")
# Notes:
#  - -v vmware        -> VMware-targeted image
#  - -s 150           -> 150 GB virtual disk
#  - -D xfce          -> Xfce desktop
#  - -T default       -> default toolset
#  - -Z Europe/Brussels -> timezone
#  - -H fpkali        -> hostname
#  - debos options go after "--" (here we set the build VM to 4G RAM)
sudo CONTAINER=docker ./build-in-container.sh \
    -v "${TARGET}" \
    -s "${DISK_GB}" \
    -D "${DESKTOP}" \
    -T "${TOOLSET}" \
    -Z "${TIMEZONE}" \
    -H "${HOSTNAME}" \
    -- --memory="${DEBOS_MEMORY}"

# Resulting files will be under ./images/
echo
echo "[✓] Build completed. Check the ./images/ directory for the VMware VMDK/VMX output."
