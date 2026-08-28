#!/usr/bin/env bash
set -euo pipefail

profile="${POC_PROFILE:-minimal}"
case "$profile" in
  minimal) nodes=(data-01) ;;
  distributed) nodes=(data-01 data-02 data-03) ;;
  *) printf 'POC_PROFILE doit valoir minimal ou distributed\n' >&2; exit 2 ;;
esac

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

printf '\n== MongoDB (%s) ==\n' "$profile"
mongo_status='JSON.stringify(rs.status().members.map(m => ({name:m.name,state:m.stateStr,health:m.health})))'
if [[ "$profile" == distributed ]]; then
  for node in "${nodes[@]}"; do
    if run_on_vm "$node" "timeout 15 sudo podman exec poc-mongodb mongosh --quiet --eval \"${mongo_status}\""; then break; fi
  done
else
  run_on_vm data-01 "timeout 15 sudo podman exec poc-mongodb mongosh --quiet --eval 'db.adminCommand({ping: 1}).ok'" \
    || printf 'MongoDB indisponible\n'
fi

printf '\n== Kafka KRaft quorum ==\n'
for node in "${nodes[@]}"; do
  printf '\n[%s]\n' "$node"
  run_on_vm "$node" \
    'timeout 15 sudo podman exec -e KAFKA_OPTS= poc-kafka /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status' \
    || printf 'Kafka indisponible ou quorum non forme\n'
done

printf '\n== PostgreSQL data-01 ==\n'
run_on_vm data-01 \
  'timeout 15 sudo podman exec poc-postgresql psql -U observability -d observability_test -tAc "SELECT count(*) AS kafka_orders FROM stock_movements WHERE channel = '\''kafka'\''"' \
  || printf 'PostgreSQL indisponible ou table stock_movements non créée\n'
