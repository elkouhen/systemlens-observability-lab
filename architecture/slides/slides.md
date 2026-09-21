---
theme: default
title: Architecture — Hybride Fleet
info: Présentation de l’architecture d’observabilité Elastic
class: text-center
highlighter: shiki
drawings:
  persist: false
mdc: true
---

# Architecture

## Hybride Fleet

Observabilité des applications Java, de Kubernetes et des VM avec Elastic
Stack **9.4.3**

<div class="absolute bottom-8 left-10 text-sm opacity-70">POC SystemLens · 2026</div>

---

# Une architecture hybride, deux chemins maîtrisés

<div class="grid grid-cols-2 gap-8 mt-8">

<div class="border-2 border-blue-400 rounded-xl p-6">

### Applications & Kubernetes

**OpenTelemetry / EDOT + Kafka**

- traces Java via OTLP ;
- logs stdout et métriques Kubernetes ;
- buffer Kafka séparé par signal ;
- export final vers Elasticsearch.

</div>

<div class="border-2 border-orange-400 rounded-xl p-6">

### VM de données

**Elastic Agent enrôlé dans Fleet**

- logs et métriques système ;
- intégrations Kafka, MongoDB et PostgreSQL ;
- publication directe vers Elasticsearch ;
- pilotage centralisé par Fleet Server.

</div>

</div>

<div class="mt-8 text-center text-xl">Kafka reste le tampon de télémétrie du cluster — pas celui des VM.</div>

---

# Topologie de déploiement

```mermaid
flowchart LR
  subgraph K8s[Cluster Kubernetes]
    APP[Applications Java\norder · inventory · restock]
    KCOL[Collectors EDOT\nDaemonSet + scraper Prometheus]
  end
  EDGE[otel-edge-01\nHAProxy / point d'entrée]
  BACK[otel-backend-01\nGateway OTLP + exporteur Kafka]
  DATA[poc-01\nKafka · MongoDB · PostgreSQL]
  ELK[elk-01\nElasticsearch · Kibana · Fleet Server]
  FLEET[Elastic Agent\nVM data plane]

  APP -->|OTLP| EDGE
  KCOL -->|OTLP| EDGE
  EDGE --> BACK
  BACK -->|otel-traces\notel-metrics\notel-logs| DATA
  DATA --> BACK
  BACK -->|OTLP/HTTP| ELK
  FLEET -->|TLS direct| ELK
  ELK -->|enrôlement| FLEET

  classDef k8s fill:#dbeafe,stroke:#2563eb,color:#111827
  classDef vm fill:#ffedd5,stroke:#ea580c,color:#111827
  class APP,KCOL k8s
  class EDGE,BACK,DATA,ELK,FLEET vm
```

<div class="text-sm opacity-70 mt-4">otel-edge-01 est le seul point d’entrée exposé ; elk-01 porte le stockage et la consultation.</div>

---

# Flux applicatif : traces et métriques

```mermaid
sequenceDiagram
  participant J as Service Java
  participant E as otel-edge-01
  participant G as Gateway EDOT
  participant K as Kafka
  participant X as Exporteur EDOT
  participant ES as Elasticsearch

  J->>E: traces OTLP/HTTP :4318
  E->>G: OTLP
  G->>K: otel-traces
  K->>X: consommation group otel-backend
  X->>ES: traces + métriques APM agrégées
```

- L’agent Java est injecté par init container.
- Le contexte `trace.id` / `span.id` permet la corrélation avec les logs.
- Les métriques applicatives sont scrappées sur `/actuator/prometheus` toutes les 15 s.
- L’export métrique de l’agent Java est désactivé pour éviter les doublons.

---

# Flux logs et métriques Kubernetes

```mermaid
flowchart LR
  PODS[stdout des pods Java\nJSON ECS] --> D[EDOT DaemonSet]
  HOST[hostmetrics\nlogs pods · k8sattributes] --> D
  ACT[Actuator /prometheus\norder · inventory · restock] --> S[EDOT scraper]
  D -->|OTLP| EDGE[otel-edge-01]
  S -->|OTLP| EDGE
  EDGE --> G[Gateway EDOT]
  G --> L[Kafka otel-logs]
  G --> M[Kafka otel-metrics]
  L --> X[Exporteur EDOT]
  M --> X
  X --> ES[(Elasticsearch)]
```

Le parsing du JSON ECS et l’enrichissement Kubernetes sont réalisés avant le
buffer. L’exporteur remappe les identifiants de trace vers les champs ECS.

---

# Flux VM : Fleet en direct

```mermaid
flowchart LR
  subgraph VM[VM observées]
    D[data-01\nKafka · MongoDB · PostgreSQL]
    B[otel-backend-01]
    E[otel-edge-01]
  end
  F[Fleet Server\nelk-01]
  A[Elastic Agent\npolicy data-fleet]
  ES[(Elasticsearch\nelk-01)]
  K[Kibana]

  F -->|enrôle / policy| A
  D --> A
  B --> A
  E --> A
  A -->|TLS direct| ES
  ES --> K
```

<div class="grid grid-cols-3 gap-4 mt-6 text-center">
<div class="rounded-lg bg-orange-100 p-3">System</div>
<div class="rounded-lg bg-orange-100 p-3">Kafka</div>
<div class="rounded-lg bg-orange-100 p-3">MongoDB · PostgreSQL</div>
</div>

<div class="mt-5 text-center">Les VM n’écrivent ni dans <code>otel-logs</code> ni dans <code>otel-metrics</code>.</div>

---

# Pourquoi séparer les topics Kafka ?

```mermaid
flowchart TB
  G[Gateway EDOT]
  T[otel-traces]
  M[otel-metrics]
  L[otel-logs]
  X[Exporteur EDOT\nrécepteur Kafka typé]
  ES[(Elasticsearch)]
  G --> T --> X
  G --> M --> X
  G --> L --> X
  X --> ES
```

| Signal | Topic | Traitement notable |
| --- | --- | --- |
| Traces | `otel-traces` | enrichissement APM |
| Métriques | `otel-metrics` | export infrastructure et APM |
| Logs | `otel-logs` | corrélation ECS `trace.id` / `span.id` |

La séparation évite les erreurs de décodage du receiver Kafka OTLP et rend la
backpressure observable par signal.

---

# Exploitation : une chaîne vérifiable

<div class="grid grid-cols-2 gap-8 mt-6">

<div>

### Déclarer

- Kustomize : `architecture/platform/kubernetes/` ;
- Ansible / Quadlet : `architecture/ansible/` ;
- policy Fleet et dashboards : `architecture/platform/elk/`.

</div>

<div>

### Contrôler

```bash
make kubernetes-validate
make -C architecture ansible-validate
make -C architecture otel-validation
make -C architecture dashboards-verify
```

</div>

</div>

<div class="mt-8 p-5 rounded-xl bg-slate-100">

**Résultat attendu :** manifests rendus, playbook syntaxiquement valide,
endpoints OTLP joignables et données visibles dans Kibana.

</div>

---

# À retenir

<div class="text-2xl leading-relaxed mt-8">

1. **Un point d’entrée** : `otel-edge-01` simplifie l’exposition OTLP et TLS.
2. **Un buffer ciblé** : Kafka découple les signaux du cluster.
3. **Une gestion VM native Elastic** : Fleet centralise les agents et les intégrations.
4. **Une destination commune** : Elasticsearch et Kibana corrèlent traces, logs et métriques.
5. **Une architecture IaC** : chaque raccordement est décrit et validable dans le dépôt.

</div>

<div class="absolute bottom-8 right-10 text-sm opacity-70">Sources : architecture/README.md · architecture/platform/elk · architecture/platform/kubernetes · architecture/ansible</div>
