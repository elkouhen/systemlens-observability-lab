---
theme: default
title: "Topologie et flux d'observabilité"
info: Architecture EDOT/OTel du POC SystemLens
class: text-center
drawings:
  persist: false
mdc: true
---

<style>
.d2 { display: block; width: 100%; height: 500px; margin: 0.4rem auto 0; object-fit: contain; }
</style>

# Topologie et flux d’observabilité

## Du signal produit à sa consultation dans Elastic

Applications · Kubernetes · VM · Kafka · MongoDB · PostgreSQL

<div class="absolute bottom-8 left-10 text-sm opacity-70">POC SystemLens · 2026</div>

---

# Architecture cible

<img class="d2" src="./diagrams/topology.png" />

Le chemin commun est explicite : source, collecte, buffer Kafka, export et
consultation. Chaque étape regroupe les composants qui portent cette responsabilité.

---

# Flux des logs

<img class="d2" src="./diagrams/logs.png" />

Les logs applicatifs et Kubernetes sont enrichis au plus près de la collecte.
Les logs des VM et des services de données suivent le même buffer avant
indexation dans Elasticsearch.

---

# Flux des métriques

<img class="d2" src="./diagrams/metrics.png" />

Les métriques applicatives, Kubernetes, système et bases de données convergent
vers les data streams OTel vérifiés par les dashboards.

---

# Flux des traces et de l’APM

<img class="d2" src="./diagrams/traces.png" />

Les identifiants `trace.id`, `span.id`, `service.name` et `host.name` permettent
de relier une transaction à ses logs et à son contexte d’infrastructure.

---

# Lecture opérationnelle des flux

| Étape | Composant | Responsabilité |
| --- | --- | --- |
| 1 | Collectors EDOT/OTel | collecte et enrichissement |
| 2 | Gateway Edge | entrée OTLP et publication par signal |
| 3 | Kafka | tampon et découplage |
| 4 | Gateway Backend | consommation et export |
| 5 | Elasticsearch / APM Server | stockage des données |
| 6 | Kibana | dashboards, APM et diagnostic |

---

# Contrôles de l’architecture

```bash
make kubernetes-validate
make ansible-validate
make otel-validation
make dashboards-verify
```

Une évolution durable suit le même parcours que les signaux : elle est
déclarée dans Kustomize ou Ansible, déployée, puis vérifiée sur les data
streams et les dashboards.
