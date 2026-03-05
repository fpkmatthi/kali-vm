#!/usr/bin/env bash
set -euo pipefail

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

echo "[*] Waiting for guest IP (VMware Tools)…"
GUEST_IP="$(vmrun getGuestIPAddress "$VMX" -wait 2>/dev/null || true)"
[[ -n "$GUEST_IP" ]] || err "Could not get guest IP. Ensure VMware Tools is installed and the VM is booted."

echo "[✓] Guest IP: ${GUEST_IP}"



# --- Build Ansible invocation ---
INVENTORY="${GUEST_IP},"
ANSIBLE_ENV=()
ANSIBLE_ARGS=( -i "${INVENTORY}" -u "${SSH_USER}" )

# Auth selection
if [[ -n "$SSH_KEY" ]]; then
  [[ -f "$SSH_KEY" ]] || err "SSH key not found: $SSH_KEY"
  ANSIBLE_ARGS+=( --private-key "$SSH_KEY" )
elif [[ -n "$SSH_PASS" ]]; then
  have sshpass || err "sshpass is required for password auth (install it)."
  ANSIBLE_ARGS+=( -e "ansible_password=${SSH_PASS}" )
  # Disable strict host key checking for this run to be extra safe with fresh VMs
  # ANSIBLE_ARGS+=( -e "ansible_ssh_common_args=-o StrictHostKeyChecking=no" )
fi

# Become / sudo
if [[ -n "$BECOME_PASS" ]]; then
  ANSIBLE_ARGS+=( --become -e "ansible_become_password=${BECOME_PASS}" )
fi

# Run the playbook
echo "[*] Running Ansible playbook on ${GUEST_IP}…"
sleep 2
ansible-playbook "${ANSIBLE_ARGS[@]}" "${PLAYBOOK}"
# ansible-playbook -i "192.168.196.129," -u kali --become ./ansible/site.yml -e "ansible_become_password=kali" -e "ansible_password=kali"

echo "[✓] Playbook completed successfully."

