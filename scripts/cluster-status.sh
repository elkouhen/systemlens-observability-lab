#!/usr/bin/env bash
set -euo pipefail

nodes=(data-01 data-02 data-03)

run_on_vm() {
  local node="$1"
  shift
  vagrant ssh "$node" -c "$*"
}

printf '== Conteneurs Podman ==\n'
for node in "${nodes[@]}"; do
  printf '\n[%s]\n' "$node"
  if ! run_on_vm "$node" "sudo podman ps -a --format '{{.Names}} {{.Status}}'"; then
    printf 'VM indisponible ou Podman non installe\n'
  fi
done

printf '\n== MongoDB replica set ==\n'
mongo_status='JSON.stringify(rs.status().members.map(m => ({name:m.name,state:m.stateStr,health:m.health})))'
for node in "${nodes[@]}"; do
  if run_on_vm "$node" "timeout 15 sudo podman exec poc-mongodb mongosh --quiet --eval \"${mongo_status}\""; then
    break
  fi
done

printf '\n== Kafka KRaft quorum ==\n'
for node in "${nodes[@]}"; do
  printf '\n[%s]\n' "$node"
  run_on_vm "$node" \
    'timeout 15 sudo podman exec -e KAFKA_OPTS= poc-kafka /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status' \
    || printf 'Kafka indisponible ou quorum non forme\n'
done
