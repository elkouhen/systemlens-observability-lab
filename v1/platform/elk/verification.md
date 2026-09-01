# Vérifier la remontée des logs et métriques v1

Ce guide vérifie la chaîne v1 de bout en bout, depuis `data-01` et les pods
Kubernetes jusqu'aux data streams Elasticsearch.

```text
data-01 : Filebeat / Metricbeat ──┐
                                  ├─ Logstash 5045 → Elasticsearch
pods Kubernetes : Elastic Agent ──┘

agent Java APM → APM Server 5044 → Logstash → Elasticsearch
```

La v1 utilise uniquement la VM `data-01`. Les métriques et logs de cette VM
ne passent pas par Fleet : Filebeat et Metricbeat publient en TLS sur
`logstash.poc.test:443`. Traefik route ce flux TCP vers l'entrée Beats
Logstash `5045`.

## Prérequis

Depuis la racine du dépôt, sélectionner la v1 et charger les identifiants :

```bash
make architecture-switch VERSION=v1
source ./v1/platform/elk/scripts/load-credentials.sh
export ELASTICSEARCH_URL="${ELASTICSEARCH_URL:-https://elasticsearch.poc.test:443}"
export ELASTICSEARCH_CURL_RESOLVE="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.poc.test:443:127.0.0.1}"
```

La plateforme, `data-01` et les applications doivent être déployés. La
variable `LOGSTASH_URL` peut remplacer l'adresse par défaut utilisée lors du
provisionnement de la VM : `logstash.poc.test:443`.

## Vérifier dans Kibana Discover

Ouvrir `https://kibana.poc.test`, puis **Discover**. Sélectionner un data view
couvrant la famille de signaux à contrôler ; créer au besoin ces data views
avec `@timestamp` comme champ temporel :

| Data view | Signaux couverts |
| --- | --- |
| `logs-*` | logs de `data-01` et logs applicatifs Kubernetes |
| `metrics-*` | métriques Metricbeat, Kubernetes, Prometheus et APM |
| `traces-*` | transactions et spans APM |

Régler la période sur **Last 15 minutes**, puis appliquer ces filtres KQL :

| Contrôle | Filtre KQL |
| --- | --- |
| Logs système | `host.name: "data-01" and data_stream.dataset: "system.syslog"` |
| Logs MongoDB | `host.name: "data-01" and data_stream.dataset: "mongodb.log"` |
| Logs Kafka | `host.name: "data-01" and data_stream.dataset: "kafka.log"` |
| Logs PostgreSQL | `host.name: "data-01" and data_stream.dataset: "postgresql.log"` |
| Métriques système | `host.name: "data-01" and data_stream.dataset: system.*` |
| Métriques MongoDB | `host.name: "data-01" and data_stream.dataset: mongodb.*` |
| Métriques Kafka | `host.name: "data-01" and data_stream.dataset: kafka.*` |
| Métriques Kubernetes | `data_stream.dataset: kubernetes.*` |
| Logs applicatifs | `data_stream.dataset: "kube-0tl" and data_stream.namespace: "homologation"` |
| Métriques Actuator | `data_stream.dataset: "app.prometheus.0tl"` |
| Métriques APM Java | `agent.name: "java" and data_stream.type: metrics` |

Pour chaque filtre, vérifier que `@timestamp` est récent et que `host.name`,
`service.name`, `event.dataset` et `data_stream.*` correspondent à la source
attendue. Un tableau vide indique le point de diagnostic à examiner dans les
sections suivantes.

## 1. Vérifier les composants de collecte

```bash
make -C v1 kubernetes-status
make -C v1 vm-status
kubectl -n elastic-stack get deployment apm-logstash apm-server-apm-server
kubectl -n elastic-stack get endpoints apm-logstash
kubectl -n elastic-stack get ingressroutetcp logstash-beats
```

Résultat attendu : les Deployments sont disponibles, l'endpoint Logstash
possède au moins une adresse et `vm-status` confirme les conteneurs de
`data-01`.

Vérifier ensuite les services Beats sur la VM :

```bash
cd v1 && vagrant ssh data-01 -c \
  'sudo systemctl is-active filebeat metricbeat'
cd v1 && vagrant ssh data-01 -c \
  'getent hosts logstash.poc.test && echo | openssl s_client -connect logstash.poc.test:443 -servername logstash.poc.test 2>/dev/null | grep "Verify return code"'
```

La commande doit retourner deux lignes `active`.

## 2. Vérifier les logs de la VM

Filebeat lit les fichiers suivants et les transmet à Logstash `5045` :

| Source | Data stream attendu |
| --- | --- |
| `/var/log/messages*`, `/var/log/secure*` | `logs-system.syslog-default` |
| `/var/log/mongodb/mongod.log` | `logs-mongodb.log-default` |
| `/var/log/kafka/*.log` | `logs-kafka.log-default` |
| `/var/log/postgresql/*.log` | `logs-postgresql.log-default` |

Contrôler le service et les erreurs de publication :

```bash
cd v1 && vagrant ssh data-01 -c \
  'sudo journalctl -u filebeat --since "15 minutes ago" --no-pager'
kubectl -n elastic-stack logs deployment/apm-logstash \
  --since=15m | rg -i 'error|exception|failed' || true
```

Puis vérifier chaque data stream dans Elasticsearch. La requête suivante
retourne le nombre de documents reçus dans les quinze dernières minutes :

```bash
for dataset in system.syslog mongodb.log kafka.log postgresql.log; do
  count="$(curl --fail --silent --show-error --insecure \
    --resolve "${ELASTICSEARCH_CURL_RESOLVE}" \
    -u "${ELASTICSEARCH_USERNAME:-elastic}:${ELASTICSEARCH_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X POST "${ELASTICSEARCH_URL}/logs-*/_count" \
    --data "{\"query\":{\"bool\":{\"filter\":[{\"term\":{\"data_stream.dataset\":\"${dataset}\"}},{\"range\":{\"@timestamp\":{\"gte\":\"now-15m\"}}}]}}}" \
    | jq -r '.count')"
  printf '%-24s %s document(s)\n' "${dataset}" "${count}"
done
```

Chaque source active doit retourner un nombre supérieur à zéro. Si une source
reste à zéro, vérifier le chemin du fichier sur la VM puis `journalctl -u
filebeat` avant d'examiner Logstash.

## 3. Vérifier les métriques Metricbeat de `data-01`

Metricbeat collecte les familles suivantes :

| Famille | Data streams attendus |
| --- | --- |
| Système | `system.cpu`, `system.memory`, `system.filesystem`, `system.network` |
| MongoDB | `mongodb.status`, `mongodb.replstatus`, `mongodb.metrics`, `mongodb.collstats` |
| Kafka | `kafka.broker`, `kafka.partition`, `kafka.consumergroup` |

Contrôler le service et les erreurs de publication :

```bash
cd v1 && vagrant ssh data-01 -c \
  'sudo journalctl -u metricbeat --since "15 minutes ago" --no-pager'
```

La cible automatisée vérifie les familles utilisées par les dashboards :

```bash
DASHBOARDS_VERIFY_WINDOW=15m make -C v1 dashboards-verify
```

Pour isoler une famille, reprendre la requête Elasticsearch de la section
précédente en remplaçant `logs-*` par `metrics-*` et le dataset par exemple
par `kafka.broker`.

## 4. Vérifier les métriques Kubernetes

Les Agents Kubernetes dédiés envoient leurs métriques au même listener
Logstash `5045` :

- l'Agent DaemonSet collecte les métriques kubelet (`kubernetes.container`,
  `kubernetes.node`, `kubernetes.pod`, `kubernetes.system`,
  `kubernetes.volume`) ;
- l'Agent Deployment collecte l'état des workloads via kube-state-metrics
  (`kubernetes.state_*`).

```bash
kubectl -n elastic-stack get pods -l agent.k8s.elastic.co/name=kubernetes-logs
kubectl -n elastic-stack get pods \
  -l agent.k8s.elastic.co/name=kubernetes-cluster-metrics
kubectl -n elastic-stack logs \
  -l agent.k8s.elastic.co/name=kubernetes-logs --since=15m --tail=100
```

Vérifier ensuite les datasets `kubernetes.container`, `kubernetes.pod` et
`kubernetes.state_deployment` avec une requête sur `metrics-*`.

Les logs stdout des applications suivent également l'Agent Kubernetes puis
Logstash `5045`. Pour les pods du namespace applicatif, le dataset final est
`logs-kube-0tl-homologation`.

```bash
kubectl -n h0tl-supermarche-app logs deployment/order-service --since=15m
kubectl -n elastic-stack logs deployment/apm-logstash --since=15m --tail=100
```

Vérifier la présence des logs routés :

```bash
curl --fail --silent --show-error --insecure \
  --resolve "${ELASTICSEARCH_CURL_RESOLVE}" \
  -u "${ELASTICSEARCH_USERNAME:-elastic}:${ELASTICSEARCH_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${ELASTICSEARCH_URL}/logs-*/_count" \
  --data '{"query":{"bool":{"filter":[{"term":{"data_stream.dataset":"kube-0tl"}},{"term":{"data_stream.namespace":"homologation"}},{"range":{"@timestamp":{"gte":"now-15m"}}}]}}}' \
  | jq
```

## 5. Vérifier les métriques Prometheus applicatives

L'Agent Kubernetes scrute `/actuator/prometheus` sur les trois Services :

```bash
kubectl -n h0tl-supermarche-app get pods,svc
kubectl -n elastic-stack logs \
  -l agent.k8s.elastic.co/name=kubernetes-logs --since=15m --tail=100
```

Le data stream attendu est
`metrics-app.prometheus.0tl-homologation`. Vérifier sa présence :

```bash
curl --fail --silent --show-error --insecure \
  --resolve "${ELASTICSEARCH_CURL_RESOLVE}" \
  -u "${ELASTICSEARCH_USERNAME:-elastic}:${ELASTICSEARCH_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${ELASTICSEARCH_URL}/metrics-*/_count" \
  --data '{"query":{"bool":{"filter":[{"term":{"data_stream.dataset":"app.prometheus.0tl"}},{"range":{"@timestamp":{"gte":"now-15m"}}}]}}}' \
  | jq
```

Un résultat avec `count` supérieur à zéro confirme la collecte des métriques
Kafka client et des métriques exposées par Actuator.

## 6. Vérifier les métriques APM

Les métriques APM suivent le chemin `agent Java → APM Server:5044 → Logstash
→ Elasticsearch`. Vérifier d'abord les composants :

```bash
kubectl -n elastic-stack get secret apm-server-apm-token
kubectl -n elastic-stack get deployment apm-server-apm-server apm-logstash
kubectl -n elastic-stack logs deployment/apm-server-apm-server --since=15m
kubectl -n elastic-stack logs deployment/apm-logstash --since=15m | tail -100
```

Après avoir généré une requête applicative, vérifier les data streams
`apm.app.*`, `apm.service_transaction.1m` et `apm.transaction.1m` dans
`metrics-*` ou `traces-*` selon le type d'événement.

```bash
make -C v1 order-service-command ORDER_PRODUCT_ID=1 ORDER_QUANTITY=1
```

## Diagnostic par point de rupture

| Point contrôlé | Symptôme si le point est en panne | Contrôle suivant |
| --- | --- | --- |
| Beat actif sur `data-01` | aucun événement local | `systemctl status`, `journalctl` |
| Connexion VM → Traefik → Logstash `5045` | erreurs de connexion dans les logs Beat | vérifier `logstash.poc.test`, le certificat et `LOGSTASH_URL` |
| Pipeline `kubernetes-logs` | événements reçus mais absents d'Elasticsearch | logs du Deployment Logstash |
| Sortie Elasticsearch Logstash | erreurs `401`, `403` ou mapping | Secret `apm-logstash-elasticsearch`, logs Logstash |
| Data stream | documents présents dans un dataset inattendu | champs `data_stream.*` et configuration du Beat |

La vérification globale des datasets utilisés par les dashboards reste
disponible avec :

```bash
DASHBOARDS_VERIFY_WINDOW=15m make -C v1 dashboards-verify
```
