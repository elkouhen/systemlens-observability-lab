#!/usr/bin/env bash
# Redémarre les cinq VM de l'architecture sans reprovisionnement Ansible.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
vagrant_bin="${VAGRANT:-vagrant}"
k3s_vm_name="${K3S_VM_NAME:-k3s-01}"
nodes=(supermarket-middleware-01 otel-backend-01 otel-edge-01 elk-01 "${k3s_vm_name}")

command -v "${vagrant_bin}" >/dev/null || {
  printf 'Vagrant est requis pour redémarrer les VM.\n' >&2
  exit 2
}

cd "${architecture_root}"

for node in "${nodes[@]}"; do
  state="$(${vagrant_bin} status "${node}" --machine-readable | awk -F, '$3 == "state" {print $4; exit}')"
  case "${state}" in
    running)
      printf 'Redémarrage de %s\n' "${node}"
      "${vagrant_bin}" reload "${node}" --no-provision
      ;;
    saved)
      # Vagrant refuse de reprendre une VM sauvegardée dont la redirection
      # SSH a été corrigée automatiquement à sa création (« forwarded port
      # ... already in use ») : l'état sauvegardé est restauré directement
      # par VirtualBox, avec ses redirections existantes.
      machine_id_file="${architecture_root}/.vagrant/machines/${node}/virtualbox/id"
      printf 'Reprise de %s (état : saved)\n' "${node}"
      VBoxManage startvm "$(cat "${machine_id_file}")" --type headless
      ;;
    stopped|poweroff|aborted)
      printf 'Démarrage de %s (état : %s)\n' "${node}" "${state}"
      "${vagrant_bin}" up "${node}" --no-provision
      ;;
    *)
      printf 'État Vagrant inattendu pour %s : %s\n' "${node}" "${state:-inconnu}" >&2
      exit 1
      ;;
  esac
done

printf '\nÉtat final des VM :\n'
"${vagrant_bin}" status "${nodes[@]}"
