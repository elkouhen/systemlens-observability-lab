#!/usr/bin/env bash
# Restaure le dernier snapshot Vagrant des quatre VM.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
backup_dir="${VAGRANT_BACKUP_DIR:-${architecture_root}/.vagrant-backups}"
vagrant_bin="${VAGRANT:-vagrant}"
nodes=(poc-01 otel-backend-01 otel-edge-01 elk-01)
manifest="${backup_dir}/latest.env"
start_after_restore="${START_AFTER_RESTORE:-YES}"

command -v "${vagrant_bin}" >/dev/null || {
  printf 'Vagrant est requis pour restaurer les VM.\n' >&2
  exit 2
}
[[ -r "${manifest}" ]] || {
  printf 'Aucun manifeste de backup trouvé : %s\n' "${manifest}" >&2
  exit 1
}
[[ "${CONFIRM_RESTORE:-}" == 'YES' ]] || {
  printf 'Restauration destructive bloquée. Relancer avec CONFIRM_RESTORE=YES.\n' >&2
  exit 2
}

snapshot_name="$(awk -F= '$1 == "snapshot_name" {print $2; exit}' "${manifest}")"
[[ "${snapshot_name}" =~ ^systemlens-[0-9]{8}T[0-9]{6}Z$ ]] || {
  printf 'Nom de snapshot invalide dans %s.\n' "${manifest}" >&2
  exit 1
}

cd "${architecture_root}"
for node in "${nodes[@]}"; do
  if ! "${vagrant_bin}" snapshot list "${node}" | grep -Fqx "${snapshot_name}"; then
    printf 'Snapshot %s absent pour %s.\n' "${snapshot_name}" "${node}" >&2
    exit 1
  fi
done

printf 'Restauration du snapshot %s pour : %s\n' "${snapshot_name}" "${nodes[*]}"
for node in "${nodes[@]}"; do
  "${vagrant_bin}" halt --force "${node}"
done
for node in "${nodes[@]}"; do
  printf 'Restauration Vagrant %s\n' "${node}"
  "${vagrant_bin}" snapshot restore "${node}" "${snapshot_name}"
  # Un snapshot peut avoir été pris alors que la VM était démarrée. Garantir
  # ici un état arrêté évite que Vagrant conserve ses anciennes règles NAT
  # lorsque la VM suivante est restaurée.
  "${vagrant_bin}" halt --force "${node}"
done

if [[ "${start_after_restore}" == 'YES' ]]; then
  # Démarrer séquentiellement laisse Vagrant recalculer les ports SSH après
  # chaque restauration et évite les collisions avec une ancienne instance.
  for node in "${nodes[@]}"; do
    printf 'Démarrage Vagrant %s\n' "${node}"
    "${vagrant_bin}" up --no-provision "${node}"
  done
else
  printf 'VM restaurées et laissées arrêtées ; utiliser START_AFTER_RESTORE=YES pour les redémarrer.\n'
fi
