#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./ansible_on_kali_vm.sh \
#     --vmx ~/vms/fpkali/fpkali.vmx \
#     --playbook site.yml \
#     --user kali \
#     [--ssh-key ~/.ssh/id_rsa | --pass 'mypassword'] \
#     [--guest-pass 'mypassword'] \
#     [--become-pass 'sudoPw'] \
#     [--start] [--gui]

# Requirements (on host):
#   - VMware Workstation/Player CLI: vmrun
#   - ansible
#   - sshpass (only if you use --pass for SSH auth)
#   - ssh & ssh-keyscan

VMX="$HOME/vmware/fpkali/kali-linux-rolling-vmware-amd64.vmx"
PLAYBOOK="./ansible/site.yml"
SSH_USER="kali"
SSH_KEY=""
SSH_PASS="kali"
GUEST_PASS="kali"      # Password to run commands via vmrun inside guest (optional but needed for bootstrap)
BECOME_PASS="kali"
START_IF_NEEDED=false
START_GUI=false

err() { echo "[!] $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# # --- Parse args ---
# while [[ $# -gt 0 ]]; do
#   case "$1" in
#     --vmx) VMX="$2"; shift 2 ;;
#     --playbook) PLAYBOOK="$2"; shift 2 ;;
#     --user) SSH_USER="$2"; shift 2 ;;
#     --ssh-key) SSH_KEY="$2"; shift 2 ;;
#     --pass) SSH_PASS="$2"; shift 2 ;;
#     --guest-pass) GUEST_PASS="$2"; shift 2 ;;
#     --become-pass) BECOME_PASS="$2"; shift 2 ;;
#     --start) START_IF_NEEDED=true; shift ;;
#     --gui) START_GUI=true; shift ;;
#     -h|--help)
#       sed -n '1,120p' "$0"; exit 0 ;;
#     *) err "Unknown arg: $1" ;;
#   esac
# done

[[ -n "$VMX" && -f "$VMX" ]] || err "--vmx path is required"
# [[ -n "$PLAYBOOK" && -f "$PLAYBOOK" ]] || err "--playbook file is required"
[[ -n "$SSH_USER" ]] || err "--user is required"
if [[ -z "$SSH_KEY" && -z "$SSH_PASS" ]]; then
  echo "[i] No --ssh-key or --pass provided; will try key from ssh-agent or default identity."
fi

have vmrun || err "vmrun not found. Install VMware Workstation/Player."
# have ansible-playbook || err "ansible-playbook not found."
have ssh || err "ssh not found."
have ssh-keyscan || err "ssh-keyscan not found."

# --- Ensure the VM is running (optional) ---
is_running=false
if vmrun list | tail -n +2 | grep -Fxq "$VMX"; then
  is_running=true
fi

if ! $is_running && $START_IF_NEEDED; then
  echo "[*] Starting VM…"
  if $START_GUI; then
    vmrun start "$VMX" gui
  else
    vmrun start "$VMX" nogui
  fi
  # give the guest a moment to boot further before tools/IP detection
  sleep 5
fi

# --- Get guest IP (requires VMware Tools in guest) ---
echo "[*] Waiting for guest IP (VMware Tools)…"
GUEST_IP="$(vmrun getGuestIPAddress "$VMX" -wait 2>/dev/null || true)"
[[ -n "$GUEST_IP" ]] || err "Could not get guest IP. Ensure VMware Tools is installed and the VM is booted."

echo "[✓] Guest IP: ${GUEST_IP}"

# --- (Optional) bootstrap SSH inside guest via vmrun ---
# This needs a valid *guest* username + password (GUEST_PASS) with sudo.
if [[ -n "$GUEST_PASS" ]]; then
  echo "[*] Bootstrapping SSH on guest using vmrun…"
  # Update & install openssh-server + python3 (Ansible often needs Python)
  # Note: runProgramInGuest runs non-interactively; use /bin/bash -lc to run a full shell.
  for CMD in \
    "echo '${GUEST_PASS}' | sudo -S /usr/bin/apt-get update -y" \
    "echo '${GUEST_PASS}' | sudo -S /usr/bin/apt-get install -y openssh-server python3" \
    "echo '${GUEST_PASS}' | sudo -S /usr/bin/systemctl enable ssh" \
    "echo '${GUEST_PASS}' | sudo -S /usr/bin/systemctl restart ssh"
  do
    vmrun -gu "$SSH_USER" -gp "$GUEST_PASS" runProgramInGuest "$VMX" /bin/bash -c "$CMD" || {
      echo "[!] Warning: bootstrap command failed: $CMD"
    }
  done
fi

# --- Wait for SSH to be reachable ---
echo "[*] Waiting for SSH on ${GUEST_IP}:22…"
for i in {1..60}; do
  if timeout 3 bash -c ">/dev/tcp/${GUEST_IP}/22" 2>/dev/null; then
    break
  fi
  sleep 2
  [[ $i -eq 60 ]] && err "SSH did not become reachable on ${GUEST_IP}:22"
done
echo "[✓] SSH reachable."

# --- Trust host key (avoid interactive prompt) ---
mkdir -p ~/.ssh
ssh-keyscan -T 5 -H "${GUEST_IP}" >> ~/.ssh/known_hosts 2>/dev/null || true

# # --- Build Ansible invocation ---
# INVENTORY="${GUEST_IP},"
# ANSIBLE_ENV=()
# ANSIBLE_ARGS=( -i "${INVENTORY}" -u "${SSH_USER}" )

# # Auth selection
# if [[ -n "$SSH_KEY" ]]; then
#   [[ -f "$SSH_KEY" ]] || err "SSH key not found: $SSH_KEY"
#   ANSIBLE_ARGS+=( --private-key "$SSH_KEY" )
# elif [[ -n "$SSH_PASS" ]]; then
#   have sshpass || err "sshpass is required for password auth (install it)."
#   ANSIBLE_ARGS+=( -e "ansible_password=${SSH_PASS}" )
#   # Disable strict host key checking for this run to be extra safe with fresh VMs
#   ANSIBLE_ARGS+=( -e "ansible_ssh_common_args=-o StrictHostKeyChecking=no" )
# fi

# # Become / sudo
# if [[ -n "$BECOME_PASS" ]]; then
#   ANSIBLE_ARGS+=( --become -e "ansible_become_password=${BECOME_PASS}" )
# fi

# # Run the playbook
# echo "[*] Running Ansible playbook on ${GUEST_IP}…"
# echo "${ANSIBLE_ARGS[@]}"
# echo "${PLAYBOOK}"
# sleep 2
# ansible-playbook "${ANSIBLE_ARGS[@]}" "${PLAYBOOK}"

# echo "[✓] Playbook completed successfully."

