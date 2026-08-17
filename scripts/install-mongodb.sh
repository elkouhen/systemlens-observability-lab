#!/usr/bin/env bash
set -euo pipefail

node_id="${1:?identifiant de nœud MongoDB requis}"
node_ip="${2:?adresse IP du nœud MongoDB requise}"
mongo_image="docker.io/library/mongo:8.0"
mongo_name="poc-mongodb"
replica_set="poc-rs"
seed_ip="192.168.33.10"
cluster_nodes=("192.168.33.10" "192.168.33.11" "192.168.33.12")

find_primary() {
  local candidate
  for candidate in "${cluster_nodes[@]}"; do
    if podman exec "$mongo_name" mongosh --quiet --host "${candidate}:27017" \
      --eval 'db.hello().isWritablePrimary' 2>/dev/null | grep -qx 'true'; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

command -v podman >/dev/null 2>&1 || dnf install -y podman

if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-port=27017/tcp
  firewall-cmd --reload
fi

podman pull "$mongo_image"
podman rm -f "$mongo_name" 2>/dev/null || true
podman volume create mongodb-data >/dev/null || true
install -d -m 0755 /var/log/mongodb
touch /var/log/mongodb/mongod.log
# Le processus MongoDB du conteneur n'est pas root ; le fichier monte doit
# donc etre inscriptible par son UID, tout en conservant le label SELinux :Z.
chmod 0666 /var/log/mongodb/mongod.log
podman run -d \
  --name "$mongo_name" \
  --restart unless-stopped \
  -p 27017:27017 \
  -v mongodb-data:/data/db:Z \
  -v /var/log/mongodb:/var/log/mongodb:Z \
  "$mongo_image" mongod --replSet "$replica_set" --bind_ip_all \
    --logpath /var/log/mongodb/mongod.log --logappend

until podman exec "$mongo_name" mongosh --quiet --eval 'db.adminCommand({ping: 1}).ok' \
  | grep -qx '1'; do
  sleep 2
done

if [ "$node_id" = "1" ]; then
  podman exec "$mongo_name" mongosh --quiet --eval "
    try { rs.status() } catch (_) {
      rs.initiate({_id: '$replica_set', members: [{_id: 0, host: '$seed_ip:27017'}]})
    }
  "
else
  # Les nœuds 2 et 3 se joignent au primaire actuellement élu.
  until primary_ip="$(find_primary)"; do
    sleep 2
  done

  podman exec "$mongo_name" mongosh --quiet --host "$primary_ip:27017" --eval "
    const cfg = rs.conf();
    if (!cfg.members.some(member => member.host === '$node_ip:27017')) {
      rs.add({host: '$node_ip:27017'});
    }
  "
fi

systemctl enable --now podman-restart.service 2>/dev/null || true
