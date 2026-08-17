#!/usr/bin/env bash
set -euo pipefail

node_id="${1:?identifiant de nœud Kafka requis}"
node_ip="${2:?adresse IP du nœud Kafka requise}"
kafka_image="docker.io/apache/kafka:3.9.2"
kafka_name="poc-kafka"
kafka_cluster_id="q1Sh-9_ISia_zwGINzRvyQ"
controller_voters="1@192.168.33.10:9093,2@192.168.33.11:9093,3@192.168.33.12:9093"
jolokia_version="2.2.0"
jolokia_agent="/opt/poc-observability/jolokia-agent.jar"
jolokia_url="https://repo1.maven.org/maven2/org/jolokia/jolokia-agent-jvm/${jolokia_version}/jolokia-agent-jvm-${jolokia_version}-javaagent.jar"

command -v podman >/dev/null 2>&1 || dnf install -y podman
command -v curl >/dev/null 2>&1 || dnf install -y curl

if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-port=9092/tcp
  firewall-cmd --permanent --add-port=9093/tcp
  firewall-cmd --reload
fi

podman pull "$kafka_image"
podman rm -f "$kafka_name" 2>/dev/null || true
podman volume create kafka-data >/dev/null || true
install -d -m 0755 /opt/poc-observability
install -d -m 0777 /var/log/kafka
curl -fsSL --retry 3 -o "$jolokia_agent" "$jolokia_url"

podman run -d \
  --name "$kafka_name" \
  --restart unless-stopped \
  -p 9092:9092 -p 9093:9093 -p 127.0.0.1:8778:8778 \
  -v kafka-data:/tmp/kraft-combined-logs:Z \
  -v /var/log/kafka:/opt/kafka/logs:Z \
  -v "$jolokia_agent":/opt/jolokia/jolokia-agent.jar:ro,Z \
  -e CLUSTER_ID="$kafka_cluster_id" \
  -e KAFKA_NODE_ID="$node_id" \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093 \
  -e KAFKA_ADVERTISED_LISTENERS="PLAINTEXT://${node_ip}:9092" \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS="$controller_voters" \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=3 \
  -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=3 \
  -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=2 \
  -e KAFKA_DEFAULT_REPLICATION_FACTOR=3 \
  -e KAFKA_MIN_INSYNC_REPLICAS=2 \
  -e KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0 \
  -e KAFKA_AUTO_CREATE_TOPICS_ENABLE=true \
  -e KAFKA_OPTS='-javaagent:/opt/jolokia/jolokia-agent.jar=port=8778,host=0.0.0.0' \
  "$kafka_image"

# Podman redémarre les conteneurs marqués d'une politique restart au boot.
systemctl enable --now podman-restart.service 2>/dev/null || true
