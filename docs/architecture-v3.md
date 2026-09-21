# Architecture v3 : Hybride Fleet

L’architecture v3 est l’architecture active du POC. Elle utilise Elastic
Stack `9.4.3`, OpenTelemetry et EDOT pour les applications et Kubernetes, puis
Elastic Agent Fleet pour les VM.

## Périmètre

Cette spécification décrit la topologie, les flux de télémétrie, les
responsabilités des composants et les contrôles de l’architecture v3. Les
commandes détaillées et les prérequis sont dans le [guide de déploiement et
d’exploitation](deploiement-et-exploitation.md).

Le code Java et les images applicatives restent partagés entre les composants
du dépôt. Les manifests Kubernetes et le provisionnement des VM sont propres
à la v3.

## Topologie

```text
Applications Java et pods Kubernetes
                 |
                 v
       otel-gateway dans Kubernetes
                 |
                 v
       Kafka sur poc-01
                 |
                 v
   EDOT backend sur otel-backend-01
                 |
                 v
       Elasticsearch sur elk-01
                 |
                 v
                Kibana

VM de données et VM de plateforme
                 |
                 v
        Elastic Agent Fleet
                 |
                 v
       Elasticsearch sur elk-01
```

`otel-edge-01` fournit le point d’entrée exposé pour OTLP, Elasticsearch,
Kibana et Fleet. `elk-01` héberge Elasticsearch, Kibana et Fleet Server.
`otel-backend-01` traite les signaux Kafka. `poc-01` héberge Kafka, MongoDB et
PostgreSQL.

Les namespaces Kubernetes conservés sont `elastic-stack` pour la plateforme
et `h0tl-supermarche-app` pour l’application.

## Flux de télémétrie

Les applications Java et les composants Kubernetes utilisent Kafka comme
tampon entre la collecte et le traitement backend. Les VM envoient leurs logs
et métriques directement vers Elasticsearch avec Elastic Agent Fleet.

| Signal | Collecte | Transport | Destination |
| --- | --- | --- | --- |
| Traces applicatives | Agent Java OpenTelemetry | OTLP, Gateway, Kafka `otel-traces` | EDOT backend, Elasticsearch |
| Logs applicatifs et Kubernetes | EDOT DaemonSet `filelog` | Kafka `otel-logs` | EDOT backend, Elasticsearch |
| Métriques applicatives | Receiver Prometheus sur `/actuator/prometheus` | Kafka `otel-metrics` | EDOT backend, Elasticsearch |
| Métriques Kubernetes | EDOT DaemonSet | Kafka `otel-metrics` | EDOT backend, Elasticsearch |
| Logs et métriques des VM | Elastic Agent enrôlé dans Fleet | HTTPS direct | Elasticsearch |

Les topics OTLP sont séparés par signal : `otel-traces`, `otel-logs` et
`otel-metrics`. Le Collector backend applique le traitement nécessaire avant
l’export vers Elastic.

## Responsabilités des composants

| Composant | Responsabilité | Source de configuration |
| --- | --- | --- |
| `otel-gateway` | Recevoir les signaux OTLP et les publier dans Kafka | `v3/platform/kubernetes/` |
| EDOT DaemonSet | Collecter les logs et métriques Kubernetes | `v3/platform/kubernetes/base/observability/` |
| `poc-01` | Fournir Kafka, MongoDB et PostgreSQL | `v3/ansible/` |
| `otel-backend-01` | Consommer Kafka et exporter les signaux vers Elastic | `v3/ansible/` |
| `otel-edge-01` | Exposer les points d’entrée et assurer le routage TLS | `v3/ansible/` et `v3/platform/kubernetes/` |
| `elk-01` | Fournir Elasticsearch, Kibana et Fleet Server | `v3/ansible/` |
| Elastic Agent Fleet | Collecter les données des VM | Policy Fleet et rôles Ansible |

La collecte VM ne passe ni par le Gateway OTLP Kubernetes ni par Kafka. Kafka
reste observé comme source de données et comme tampon des flux applicatifs et
Kubernetes.

## Invariants d’architecture

Les contrôles et évolutions de la v3 doivent conserver les invariants suivants :

1. Les applications et les collecteurs Kubernetes utilisent le namespace
   `elastic-stack` pour les composants de la plateforme.
2. Les signaux OTLP applicatifs et Kubernetes passent par Kafka avant le
   traitement backend.
3. Les topics Kafka distinguent les traces, les logs et les métriques.
4. Les VM utilisent Elastic Agent Fleet et exportent directement vers
   Elasticsearch.
5. Les secrets et jetons restent hors Git et sont fournis par les mécanismes
   prévus par le dépôt.
6. Les changements durables de Kubernetes, Fleet, Elastic et Ansible restent
   déclarés dans les fichiers versionnés correspondants.

## Déploiement et vérification

Depuis la racine du dépôt, vérifier l’architecture active puis valider les
manifests sans appliquer de ressource :

```bash
make architecture-status
make kubernetes-validate
make ansible-validate
```

Pour déployer l’architecture complète, fournir les secrets hors Git puis
exécuter :

```bash
export POSTGRESQL_PASSWORD='...'
make deploy
```

Les contrôles fonctionnels de la chaîne sont :

```bash
make otel-validation
make dashboards-verify
```

Le [README de la v3](../v3/README.md) renvoie vers les README de la plateforme,
du provisionnement Ansible et des dashboards. Le [document sur les briques de
télémétrie](briques-remontee-telemetrie-v3.md) fournit le détail des sources
IaC de chaque flux.
