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
    stopped|poweroff|aborted|saved)
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
