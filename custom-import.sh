#!/usr/bin/env bash
set -euo pipefail

### --- Config ---
VM_NAME="fpkali"
IMAGE_DIR="${PWD}/images/kali-linux-rolling-vmware-amd64.vmwarevm"   # change if your images are elsewhere
VM_ROOT="${HOME}/vmware"               # where to store the new VM

# VM runtime (you can change later in VMware UI)
MEMORY_MB=4096
CPUS=2
NET_TYPE="nat"                      # nat | bridged | hostonly

# Shared folder config
ENABLE_SHARED_FOLDER=true
SHARE_NAME="hostshare"              # how it appears inside the guest
HOST_SHARE_PATH="${HOME}/Documents/shared-folders/${VM_NAME}"
READONLY=false                      # true -> read-only in guest
### -------------

# Prep
VM_DIR="${VM_ROOT}/${VM_NAME}"
mkdir -p "${VM_DIR}"

# Ensure shared folder host path exists (if enabled)
if [[ "${ENABLE_SHARED_FOLDER}" == "true" ]]; then
  mkdir -p "${HOST_SHARE_PATH}"
fi

# Find newest VMware artifact
shopt -s nullglob
vmx_candidates=("${IMAGE_DIR}"/*.vmx)
vmdk_candidates=("${IMAGE_DIR}"/*.vmdk)
shopt -u nullglob

pick_newest_file() {
  local newest=""
  local newest_mtime=0
  for f in "$@"; do
    [[ -e "$f" ]] || continue
    mtime=$(stat -c %Y "$f")
    if (( mtime > newest_mtime )); then
      newest_mtime=$mtime
      newest="$f"
    fi
  done
  [[ -n "$newest" ]] && echo "$newest" || return 1
}

VMX_SRC=""
VMDK_SRC=""

if ((${#vmx_candidates[@]})); then
  VMX_SRC=$(pick_newest_file "${vmx_candidates[@]}")
  base="${VMX_SRC%.*}"
  if [[ -f "${base}.vmdk" ]]; then
    VMDK_SRC="${base}.vmdk"
  elif ((${#vmdk_candidates[@]})); then
    VMDK_SRC=$(pick_newest_file "${vmdk_candidates[@]}")
  fi
elif ((${#vmdk_candidates[@]})); then
  VMDK_SRC=$(pick_newest_file "${vmdk_candidates[@]}")
else
  echo "[!] No .vmx or .vmdk found in ${IMAGE_DIR}"
  exit 1
fi

echo "[*] Using:"
[[ -n "${VMX_SRC}" ]] && echo "    VMX:  ${VMX_SRC}"
[[ -n "${VMDK_SRC}" ]] && echo "    VMDK: ${VMDK_SRC}"

# Copy artifacts into the VM folder
echo "[*] Creating VM at ${VM_DIR}"
rsync -a --delete --include="*/" --include="*.vmx" --include="*.nvram" --include="*.vmdk" --include="*.vmsd" --include="*.vmxf" --exclude="*" "${IMAGE_DIR}/" "${VM_DIR}/" || true

# Ensure chosen files are present
if [[ -n "${VMDK_SRC:-}" && ! -f "${VM_DIR}/$(basename "${VMDK_SRC}")" ]]; then
  cp -f "${VMDK_SRC}" "${VM_DIR}/"
fi
if [[ -n "${VMX_SRC:-}" && ! -f "${VM_DIR}/$(basename "${VMX_SRC}")" ]]; then
  cp -f "${VMX_SRC}" "${VM_DIR}/"
fi

# Determine final vmx path; create one if missing
VMX_PATH=""
shopt -s nullglob
vmx_in_dir=("${VM_DIR}"/*.vmx)
shopt -u nullglob

if ((${#vmx_in_dir[@]})); then
  VMX_PATH="${vmx_in_dir[0]}"
else
  if [[ -z "${VMDK_SRC:-}" ]]; then
    echo "[!] No .vmx in image and no .vmdk to attach. Cannot continue."
    exit 1
  fi
  VMDK_BASENAME="$(basename "${VMDK_SRC}")"
  VMX_PATH="${VM_DIR}/${VM_NAME}.vmx"
  cat > "${VMX_PATH}" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
displayName = "${VM_NAME}"
guestOS = "debian12-64"
memsize = "${MEMORY_MB}"
numvcpus = "${CPUS}"

# Disk
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "${VMDK_BASENAME}"

# NIC
ethernet0.present = "TRUE"
ethernet0.connectionType = "${NET_TYPE}"
ethernet0.virtualDev = "vmxnet3"
ethernet0.addressType = "generated"

# Misc
firmware = "efi"
usb.present = "TRUE"
sound.present = "FALSE"
tools.syncTime = "TRUE"
EOF
fi

# Helper: set/replace a key=value in the .vmx (append if missing)
set_vmx_kv () {
  local key="$1" val="$2"
  # remove existing
  sed -i -e "/^${key} = \".*\"/d" "${VMX_PATH}" || true
  # append new
  printf '%s = "%s"\n' "$key" "$val" >> "${VMX_PATH}"
}

# Base runtime tuning
sed -i \
  -e "s/^displayName = \".*\"/displayName = \"${VM_NAME//\//\\/}\"/g" \
  -e "s/^memsize = \".*\"/memsize = \"${MEMORY_MB}\"/g" \
  -e "s/^numvcpus = \".*\"/numvcpus = \"${CPUS}\"/g" \
  -e "/^ethernet0.connectionType = \"/c\\ethernet0.connectionType = \"${NET_TYPE}\"" \
  "${VMX_PATH}" || true

# --- Shared folder pre-configuration in .vmx ---
if [[ "${ENABLE_SHARED_FOLDER}" == "true" ]]; then
  # Clean any existing sharedFolderN.* lines to avoid conflicts
  sed -i -E '/^sharedFolder[0-9]+\..*/d' "${VMX_PATH}" || true

  # Enable HGFS/Shared Folders in the VMX
  set_vmx_kv "isolation.tools.hgfs.disable" "FALSE"
  set_vmx_kv "hgfs.linkRootShare" "TRUE"
  set_vmx_kv "sharedFolder.maxNum" "1"

  # Define sharedFolder0
  set_vmx_kv "sharedFolder0.present" "TRUE"
  set_vmx_kv "sharedFolder0.enabled" "TRUE"
  set_vmx_kv "sharedFolder0.readAccess" "$([[ "${READONLY}" == "true" ]] && echo TRUE || echo TRUE)"
  set_vmx_kv "sharedFolder0.writeAccess" "$([[ "${READONLY}" == "true" ]] && echo FALSE || echo TRUE)"
  set_vmx_kv "sharedFolder0.hostPath" "${HOST_SHARE_PATH}"
  set_vmx_kv "sharedFolder0.guestName" "${SHARE_NAME}"
  set_vmx_kv "sharedFolder0.expiration" "never"
fi

echo "[✓] VM created:"
echo "    ${VMX_PATH}"

# # If vmrun is available, also enable and register the share at the VMX level
# if [[ "${ENABLE_SHARED_FOLDER}" == "true" ]] && command -v vmrun >/dev/null; then

#   echo "[*] Enabling shared folders via vmrun..."
#   # Some VMware products need the type; try Workstation first, fallback if needed
#   if vmrun -T ws list >/dev/null 2>&1; then
#     vmrun -T ws enableSharedFolders "${VMX_PATH}"
#     vmrun -T ws addSharedFolder "${VMX_PATH}" "${SHARE_NAME}" "${HOST_SHARE_PATH}"
#   elif vmrun -T player list >/dev/null 2>&1; then
#     vmrun -T player enableSharedFolders "${VMX_PATH}"
#     vmrun -T player addSharedFolder "${VMX_PATH}" "${SHARE_NAME}" "${HOST_SHARE_PATH}"
#   else
#     # fallback without -T (older installs)
#     vmrun enableSharedFolders "${VMX_PATH}" || true
#     vmrun addSharedFolder "${VMX_PATH}" "${SHARE_NAME}" "${HOST_SHARE_PATH}" || true
#   fi
#   echo "[✓] Shared folder registered: ${SHARE_NAME} -> ${HOST_SHARE_PATH}"
# else
#   if [[ "${ENABLE_SHARED_FOLDER}" == "true" ]]; then
#     echo "[i] 'vmrun' not found; shared folder is pre-set in the .vmx."
#   fi
# fi

echo
echo "Open the VM in VMware, or start via:"
echo "  vmrun start \"${VMX_PATH}\" nogui    # (or 'gui')"

if [[ "${ENABLE_SHARED_FOLDER}" == "true" ]]; then
  cat <<'TIP'

Inside the Kali guest (after open-vm-tools is running), you can mount the share:
  sudo mkdir -p /mnt/hgfs/hostshare
  sudo vmhgfs-fuse .host:/hostshare /mnt/hgfs/hostshare -o allow_other

To auto-mount on login, you can add a systemd user service or fstab entry later.
TIP
fi

# Optional: auto-start if user passed --start
if [[ "${1:-}" == "--start" ]]; then
  if command -v vmrun >/dev/null; then
    echo "[*] Starting VM..."
    vmrun start "${VMX_PATH}" nogui
    echo "[✓] Started."
  else
    echo "[!] 'vmrun' not found. Install VMware Workstation/Player CLI tools."
  fi
fi

