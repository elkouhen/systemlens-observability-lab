# Schémas de remontée de l'observabilité v1/v2

Ces schémas décrivent les flux déclarés dans le dépôt pour le profil léger,
avec la VM `data-01`. Les flèches indiquent le transport et les data streams
indiquent la destination logique dans Elasticsearch.

## v1 — métriques et traces APM Java

```mermaid
flowchart LR
    J[Applications Java\nagent Elastic APM] -->|HTTPS APM| A[APM Server]
    A -->|Lumberjack :5044| L[Logstash\npipeline apm]
    L -->|data streams ECS\ntraces-* / metrics-apm*| E[(Elasticsearch)]
    E --> K[Kibana\nObservability / APM]
```

## v1 — métriques et logs de la VM

```mermaid
flowchart LR
    S[VM data-01\nCPU · mémoire · disque · réseau\nKafka · MongoDB · PostgreSQL] --> MB[Metricbeat]
    S --> FB[Filebeat]
    MB -->|metrics-*\nHTTPS direct| E[(Elasticsearch)]
    FB -->|logs système et services\nHTTPS direct| E
    E --> K[Kibana\nSystem / Kafka / MongoDB / PostgreSQL]
```

`Metricbeat` et `Filebeat` des VM écrivent directement dans Elasticsearch en
v1 ; Kafka est une source observée, pas un buffer de télémétrie.

## v1 — logs applicatifs

```mermaid
flowchart LR
    P[Pods Java\nstdout ECS JSON\ntrace.id / span.id] --> A[Elastic Agent Kubernetes]
    A -->|Beats :5045| L[Logstash\npipeline kubernetes-logs]
    L -->|logs-* ECS\nnamespace + dataset| E[(Elasticsearch)]
    E --> K[Kibana\nDiscover / Logs]
    E -. corrélation .-> AP[APM\nView surrounding logs]
```

## v2 — métriques et traces APM Java

```mermaid
flowchart LR
    J[Applications Java\nOpenTelemetry Java Agent] -->|OTLP HTTP :4318| G[EDOT Collector Gateway]
    G -->|elasticapm processor + connector| T[Kafka\notel-traces]
    G -->|métriques APM agrégées\notel-metrics| M[Kafka\notel-metrics]
    T --> X[EDOT Kafka exporter]
    M --> X
    X -->|data streams OTel\ntraces-* / metrics-*| E[(Elasticsearch)]
    E --> K[Kibana\nAPM Services / traces]
```

Le `elasticapm` processor/connector produit les métriques APM agrégées à
partir des traces ; elles suivent le même buffer Kafka avant indexation.

## v2 — métriques et logs de la VM

```mermaid
flowchart LR
    V[VM data-01\nhostmetrics\nKafka · MongoDB · PostgreSQL\nlogs système et services] --> A[EDOT Agent VM]
    A -->|OTLP Kafka\nedot-vm-metrics| KM[Kafka]
    A -->|OTLP Kafka\nedot-vm-logs| KL[Kafka]
    KM --> X[EDOT Kafka exporter]
    KL --> X
    X -->|data streams OTel\nmetrics / logs| E[(Elasticsearch)]
    E --> K[Kibana\nSystem / Kafka / MongoDB / PostgreSQL]
```

Le chemin VM v2 est volontairement distinct du Gateway : `EDOT Agent VM →
Kafka → EDOT Kafka exporter → Elasticsearch`.

## v2 — logs applicatifs

```mermaid
flowchart LR
    P[Pods Java\nstdout ECS JSON\ntrace_id / span_id] --> D[EDOT Collector DaemonSet\nfilelog + parser container]
    D -->|OTLP Kafka\notel-logs| L[Kafka]
    L --> X[EDOT Kafka exporter]
    X -->|logs-generic.otel-*| E[(Elasticsearch)]
    E --> K[Kibana\nDiscover / Logs]
    E -. trace.id .-> AP[APM\ntrace associée]
```

Les applications Java n'exportent pas les logs via l'agent OpenTelemetry
(`OTEL_LOGS_EXPORTER=none`) : le DaemonSet lit stdout et conserve le contexte
de trace dans les événements indexés.

## Ce qui manquait dans la liste initiale

Les trois familles citées couvrent les flux principaux. Pour une chaîne
complète, il faut également expliciter :

- les métriques et logs de la plateforme Kubernetes elle-même (DaemonSet
  EDOT en v2, Elastic Agent et `kube-state-metrics` en v1) ;
- la corrélation logs-traces (`trace.id`, `span.id`) et la génération des
  métriques APM agrégées depuis les traces ;
- le rôle de Kafka en v2 comme buffer de télémétrie, avec ses topics, ses
  consumer groups et l'EDOT exporter ;
- la consultation finale : data streams Elasticsearch, règles de routage et
  dashboards Kibana.

Les métriques Prometheus de l'application (`/actuator/prometheus`) constituent
un cas à part : elles sont exportées comme métriques OTel par l'agent Java en
v2 ; en v1, elles passent par la collecte Elastic Agent/Metricbeat dédiée.
Elles ne doivent pas être confondues avec les métriques APM agrégées.

## Sources IaC

- v1 : `v1/platform/kubernetes/base/observability/` et
  `v1/ansible/templates/filebeat.yml.j2`, `metricbeat.yml.j2` ;
- v2 : `v2/platform/kubernetes/base/observability/otel-kafka.yaml` et
  `v2/ansible/templates/otel-agent.yml.j2` ;
- vue de référence lisible directement sur GitHub : ce document Markdown et ses
  six schémas Mermaid.
