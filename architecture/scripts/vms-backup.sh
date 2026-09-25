#!/usr/bin/env bash
# Crée un snapshot Vagrant commun aux quatre VM et conserve son manifeste local.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
backup_dir="${VAGRANT_BACKUP_DIR:-${architecture_root}/.vagrant-backups}"
vagrant_bin="${VAGRANT:-vagrant}"
nodes=(poc-01 otel-backend-01 otel-edge-01 elk-01)

command -v "${vagrant_bin}" >/dev/null || {
  printf 'Vagrant est requis pour sauvegarder les VM.\n' >&2
  exit 2
}

cd "${architecture_root}"
mkdir -p "${backup_dir}"

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
snapshot_name="systemlens-${timestamp}"
manifest="${backup_dir}/backup-${timestamp}.env"

for node in "${nodes[@]}"; do
  printf 'Snapshot Vagrant %s : %s\n' "${node}" "${snapshot_name}"
  "${vagrant_bin}" snapshot save "${node}" "${snapshot_name}"
done

{
  printf 'created_at=%s\n' "${timestamp}"
  printf 'snapshot_name=%s\n' "${snapshot_name}"
  printf 'nodes=%s\n' "${nodes[*]}"
} >"${manifest}"
cp "${manifest}" "${backup_dir}/latest.env"

printf 'Backup créé : %s\n' "${manifest}"
printf 'Les snapshots restent gérés par Vagrant/VirtualBox ; le manifeste local indique le dernier backup.\n'
