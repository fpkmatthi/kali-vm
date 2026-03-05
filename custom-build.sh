#!/usr/bin/env bash
set -euo pipefail

# --- Config you asked for ---
DISK_GB=150
DESKTOP="xfce"
TOOLSET="default"
TIMEZONE="Europe/Brussels"
HOSTNAME="fpkali"
DEBOS_MEMORY="4G"   # RAM for the *build VM* (not the final VM's runtime)
# ----------------------------

# Ensure deps
command -v git >/dev/null || { echo "[!] git not found"; exit 1; }
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
sudo ./build-in-container.sh \
  -v vmware \
  -s "${DISK_GB}" \
  -D "${DESKTOP}" \
  -T "${TOOLSET}" \
  -Z "${TIMEZONE}" \
  -H "${HOSTNAME}" \
  -- --memory="${DEBOS_MEMORY}"

# Resulting files will be under ./images/
echo
echo "[✓] Build completed. Check the ./images/ directory for the VMware VMDK/VMX output."

