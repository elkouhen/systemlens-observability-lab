#!/usr/bin/env bash
# Agrandit idempotemment le disque système d'une VM VirtualBox puis sa partition XFS.
set -euo pipefail

vm_short_name="${1:?Usage : $0 <nom-vm> <taille-en-MiB>}"
target_mib="${2:?Usage : $0 <nom-vm> <taille-en-MiB>}"
vagrant_bin="${VAGRANT:-vagrant}"

command -v VBoxManage >/dev/null || { echo 'VBoxManage est requis.' >&2; exit 1; }
[[ "${target_mib}" =~ ^[0-9]+$ ]] || { echo 'La taille cible doit être un entier en MiB.' >&2; exit 1; }

vm_name="$(VBoxManage list vms | sed -n "s/^\"\(.*_${vm_short_name}_.*\)\" {.*/\1/p" | head -n 1)"
[[ -n "${vm_name}" ]] || { echo "VM VirtualBox introuvable : ${vm_short_name}" >&2; exit 1; }

disk_uuid="$(VBoxManage showvminfo "${vm_name}" --machinereadable \
  | awk -F= '/ImageUUID-0-0/ {gsub(/\"/, "", $2); print $2; exit}')"
[[ -n "${disk_uuid}" ]] || { echo "Disque système introuvable pour ${vm_name}" >&2; exit 1; }

current_mib="$(VBoxManage showmediuminfo "${disk_uuid}" \
  | awk '/Capacity:/ {print $2; exit}')"
[[ -n "${current_mib}" ]] || { echo "Taille du disque introuvable : ${disk_uuid}" >&2; exit 1; }

if (( current_mib < target_mib )); then
  echo "Agrandissement ${vm_short_name}: ${current_mib} MiB -> ${target_mib} MiB"
  "${vagrant_bin}" halt "${vm_short_name}"
  VBoxManage modifymedium "${disk_uuid}" --resize "${target_mib}"
  "${vagrant_bin}" up "${vm_short_name}" --no-provision
else
  echo "Disque ${vm_short_name} déjà dimensionné à ${current_mib} MiB"
fi

"${vagrant_bin}" ssh "${vm_short_name}" -c \
  'printf "Yes\\n" | sudo parted ---pretend-input-tty /dev/sda resizepart 3 100% && sudo xfs_growfs /'
