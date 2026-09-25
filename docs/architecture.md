# Architecture : Hybride Fleet

L’architecture active du POC utilise Elastic
Stack `9.4.3`, OpenTelemetry et EDOT pour les applications, Kubernetes et les
VM. Les agents des VM sont installés en mode EDOT standalone. Leur supervision
Fleet OpAMP est optionnelle et limitée au monitoring ; leur configuration reste
gérée par les fichiers Ansible versionnés.

## Périmètre

Cette spécification décrit la topologie, les flux de télémétrie, les
responsabilités des composants et les contrôles de l’architecture. Les
commandes détaillées et les prérequis sont dans le [guide de déploiement et
d’exploitation](deploiement-et-exploitation.md).

Le code Java et les images applicatives restent partagés entre les composants
du dépôt. Les manifests Kubernetes et le provisionnement des VM sont propres
à l'architecture.

## Topologie

```text
Applications Java et pods Kubernetes
                 |
                 v
       Collecteur Edge sur otel-edge-01
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
        Elastic Agent EDOT
                 |
                 v
       Collecteur Edge, Kafka et backend
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
et métriques en OTLP au Collecteur Edge avec Elastic Agent EDOT standalone.

| Signal | Collecte | Transport | Destination |
| --- | --- | --- | --- |
| Traces applicatives | Agent Java OpenTelemetry | OTLP, Edge, Kafka `otel-traces` | EDOT backend, APM Server |
| Logs applicatifs et Kubernetes | EDOT DaemonSet `filelog` | OTLP, Edge, Kafka `otel-logs` | EDOT backend, Elasticsearch |
| Métriques applicatives | Micrometer OTLP | OTLP, Edge, Kafka `otel-metrics` | EDOT backend, Elasticsearch |
| Métriques Kubernetes | EDOT DaemonSet | OTLP, Edge, Kafka `otel-metrics` | EDOT backend, Elasticsearch |
| Logs et métriques des VM | Elastic Agent EDOT standalone | OTLP, Edge, Kafka par signal | EDOT backend, Elasticsearch |

Les topics OTLP sont séparés par signal : `otel-traces`, `otel-logs` et
`otel-metrics`. Le Collector backend applique le traitement nécessaire avant
l’export vers Elastic.

## Responsabilités des composants

| Composant | Responsabilité | Source de configuration |
| --- | --- | --- |
| `otel-edge-01` | Recevoir l’OTLP Kubernetes et VM puis publier dans Kafka | `architecture/ansible/roles/otel_edge/` |
| EDOT DaemonSet | Collecter les logs et métriques Kubernetes | `architecture/platform/kubernetes/base/observability/` |
| `poc-01` | Fournir Kafka, MongoDB et PostgreSQL | `architecture/ansible/` |
| `otel-backend-01` | Consommer Kafka et exporter les signaux vers Elastic | `architecture/ansible/` |
| `otel-edge-01` | Exposer les points d’entrée et héberger le Collecteur Edge | `architecture/ansible/` et `architecture/platform/kubernetes/` |
| `elk-01` | Fournir Elasticsearch, Kibana et Fleet Server | `architecture/ansible/` |
| Elastic Agent EDOT | Collecter les logs et métriques des VM et les exporter en OTLP | `architecture/ansible/roles/elastic_agent/` |

Les collecteurs Kubernetes et les applications envoient leurs signaux au
Collecteur Edge via le Service `otel-edge-vm`. Les agents EDOT standalone des
VM utilisent directement l’adresse OTLP de ce même collecteur. Tous les flux
suivent ensuite Kafka et le backend.

## Invariants d’architecture

Les contrôles et évolutions de l'architecture doivent conserver les invariants suivants :

1. Les applications et les collecteurs Kubernetes utilisent le namespace
   `elastic-stack` pour les composants de la plateforme.
2. Les signaux OTLP applicatifs et Kubernetes passent par Kafka avant le
   traitement backend.
3. Les topics Kafka distinguent les traces, les logs et les métriques.
4. Les VM utilisent Elastic Agent EDOT et exportent en OTLP vers le Collecteur
   Edge avant Kafka et le traitement backend.
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
make vms-up
make vm-status
make deploy
```

Les contrôles fonctionnels de la chaîne sont :

```bash
make otel-validation
make dashboards-verify
```

Le [README de l'architecture](../architecture/README.md) renvoie vers les README de la plateforme,
du provisionnement Ansible et des dashboards. Le [document sur les briques de
télémétrie](briques-remontee-telemetrie.md) fournit le détail des sources
IaC de chaque flux.
