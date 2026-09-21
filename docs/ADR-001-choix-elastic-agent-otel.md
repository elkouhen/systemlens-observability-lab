# ADR-001 : choisir Elastic Agent ou OTel selon le composant

Cette décision décrit le modèle de collecte de l’architecture et les
frontières entre Fleet classique, EDOT et OpAMP.

|                |                                            |
| -------------- | ------------------------------------------ |
| **Statut**     | Acceptée                                   |
| **Date**       | 2026-09-21                                 |
| **Périmètre**  | VM, Kubernetes, applications Java, transport et contrôle Fleet |
| **Audience**   | Développeurs, exploitants et responsables de la plateforme |
| **Références** | [`Documentation système`](README.md), [`architecture.md`](architecture.md) |

---

## 1. Décision

L’architecture conserve Elastic Agent Fleet classique pour les VM et leurs
intégrations System, Kafka, MongoDB et PostgreSQL. Elle utilise EDOT et
OpenTelemetry pour Kubernetes, les applications Java et les collectors qui
transportent les signaux vers Elastic. Ce choix est conservé pour faire passer
les logs, les traces et les métriques Kubernetes par le Gateway local avant
leur mise en tampon et leur export.

| Composant | Collecte retenue | Gestion | Transport et destination |
| --- | --- | --- | --- |
| VM `poc-01` | Elastic Agent Fleet avec `system`, `kafka`, `mongodb`, `postgresql` | Fleet classique | HTTPS direct vers Elasticsearch |
| VM `otel-backend-01` et `otel-edge-01` | Elastic Agent Fleet avec `system` | Fleet classique | HTTPS direct vers Elasticsearch |
| Kubernetes | EDOT Collector avec `hostmetrics`, `kubeletstats`, `k8scluster`, `filelog` | OpAMP via Fleet | OTLP vers Gateway, Kafka, puis Elasticsearch |
| Applications Java | EDOT Java, OTLP et Micrometer OTLP | Configuration Kubernetes | Gateway OTLP, Kafka, puis backend EDOT |
| Gateway et collectors Kubernetes | EDOT Collector | OpAMP via Fleet | Kafka par signal, puis export Elasticsearch ou APM Server |
| Fleet Server | Elastic Agent Fleet Server | Fleet classique | Plan de contrôle Fleet |

Cette décision maintient les data streams ECS des VM et les data streams OTel
de Kubernetes dans leurs périmètres respectifs. Elle évite de remplacer les
dashboards VM existants par des dashboards OTel en Technical Preview.

## 2. Contexte vérifié

Le dépôt décrit une architecture hybride dans laquelle les VM publient
directement vers Elasticsearch, tandis que Kubernetes et les applications
utilisent OTLP et Kafka. Cette topologie est décrite dans
[`architecture.md`](architecture.md:1) et dans
[`briques-remontee-telemetrie.md`](briques-remontee-telemetrie.md:1).

Le script [`bootstrap-fleet-policies.sh`](../architecture/platform/elk/scripts/bootstrap-fleet-policies.sh:107)
déclare les packages Fleet classiques pour les VM. Les policies concernent
System sur les VM et Kafka, MongoDB et PostgreSQL sur `poc-01`.

Le manifeste [`otel-kafka.yaml`](../architecture/platform/kubernetes/base/observability/otel-kafka.yaml:101)
déclare les collectors EDOT Kubernetes, leurs receivers et leurs extensions
OpAMP. Les trois collectors Kubernetes utilisent l’UID de leur pod comme
identité technique.

Elastic documente deux modèles compatibles dans un même Elastic Agent : les
receivers hérités qui produisent ECS et les receivers OTel natifs qui suivent
les conventions sémantiques OpenTelemetry. Les packages OTel d’entrée sont
gérés par Fleet en mode agent standard, tandis qu’un collector en mode OTel
utilise une configuration Collector et OpAMP. Voir la
[documentation Elastic Agent et OTel](https://www.elastic.co/docs/reference/fleet/elastic-agent-as-otel-collector)
et la [documentation des packages OTel](https://www.elastic.co/docs/reference/fleet/otel-integrations),
consultées le 2026-09-21.

Les receivers `hostmetrics`, `kafkametrics`, `mongodbreceiver` et
`postgresqlreceiver` figurent dans les composants de l’Elastic Agent 9.x. Le
catalogue fournit cependant des niveaux de support différents pour les
packages et les dashboards associés. Voir la
[liste des composants EDOT](https://www.elastic.co/docs/reference/edot-collector/components),
consultée le 2026-09-21.

## 3. Choix par composant

### 3.1 VM et métriques système

> **Pourquoi et quoi - conserver System Fleet**
>
> **Choix :** les VM utilisent le package System classique dans Fleet.
>
> **Pourquoi :** la policy existante produit les data streams ECS attendus par
> les dashboards VM et exporte directement vers Elasticsearch. Le package
> System OTel fournit des dashboards dédiés, mais il reste en Technical Preview.
>
> **Alternatives considérées :** le package Host Metrics OTel fournirait un
> schéma uniforme avec Kubernetes. Il ajouterait toutefois une migration de
> data streams et de dashboards pour les VM.
>
> **Retour arrière :** réactiver la package policy `system` dans
> `data-fleet` ou `otel-fleet` et arrêter la collecte OTel correspondante.

### 3.2 Kafka

> **Pourquoi et quoi - conserver Kafka Fleet**
>
> **Choix :** les brokers et les logs Kafka restent collectés par
> l’intégration Kafka classique sur `poc-01`.
>
> **Pourquoi :** cette intégration couvre les data streams actuels
> `kafka.broker`, `kafka.partition`, `kafka.consumergroup` et `kafka.log`.
> Le package Kafka OTel propose des dashboards séparés et reste en Technical
> Preview.
>
> **Alternatives considérées :** `kafkametricsreceiver` fournirait des
> métriques OTel pour les brokers, les topics et les consumers. Il ne conserve
> pas automatiquement les requêtes et les data streams des dashboards Kafka
> existants.
>
> **Retour arrière :** conserver la policy `kafka-poc-01` et supprimer une
> éventuelle policy OTel Kafka uniquement après validation de l’absence de
> doublons.

### 3.3 MongoDB

> **Pourquoi et quoi - conserver MongoDB Fleet**
>
> **Choix :** MongoDB reste collecté par l’intégration MongoDB classique et
> son input de logs.
>
> **Pourquoi :** la collecte actuelle alimente les data streams
> `mongodb.status`, `mongodb.metrics`, `mongodb.dbstats`, `mongodb.replstatus`
> et `mongodb.log`, que les dashboards du POC utilisent.
>
> **Alternatives considérées :** `mongodbreceiver` et le content pack MongoDB
> OTel couvrent les opérations, la latence, le cache et la capacité. Le pack
> reste en Technical Preview et ses dashboards utilisent un schéma OTel séparé.
>
> **Retour arrière :** conserver la policy MongoDB actuelle et retirer le
> receiver OTel avant toute suppression de data stream historique.

### 3.4 PostgreSQL

> **Pourquoi et quoi - conserver PostgreSQL Fleet**
>
> **Choix :** PostgreSQL reste collecté par l’intégration PostgreSQL classique
> et son input de logs.
>
> **Pourquoi :** cette collecte alimente les dashboards et les data streams
> `postgresql.database`, `postgresql.statement` et `postgresql.log`. Elle
> utilise déjà le secret de supervision déclaré par le dépôt.
>
> **Alternatives considérées :** `postgresqlreceiver` offre des événements de
> requêtes et des dashboards OTel dédiés. Le content pack PostgreSQL OTel reste
> en Technical Preview et demande des droits supplémentaires, ainsi que
> l’extension `pg_stat_statements` pour les requêtes détaillées.
>
> **Retour arrière :** conserver la policy PostgreSQL classique jusqu’à la
> validation séparée des droits, des data streams et des dashboards OTel.

### 3.5 Kubernetes

> **Pourquoi et quoi - choisir EDOT Kubernetes**
>
> **Choix :** Kubernetes utilise EDOT Collector avec OpAMP pour les métriques,
> les logs et les signaux applicatifs.
>
> **Pourquoi :** `kubeletstats` collecte les ressources des nœuds, pods et
> conteneurs, `k8scluster` collecte l’état agrégé du cluster et `filelog` lit
> les logs stdout. Les processors Kubernetes ajoutent l’identité du workload
> avant le passage dans le Gateway local. Le Gateway centralise ensuite les
> trois signaux avant leur mise en tampon dans Kafka et leur export.
>
> **Alternatives considérées :** l’intégration Kubernetes Fleet classique
> simplifierait la gestion avec une policy ECS. Elle enverrait les événements
> directement vers Elasticsearch et ne conserverait pas le passage des logs,
> traces et métriques par le Gateway local.
>
> **Retour arrière :** réinstaller l’intégration Kubernetes classique sur une
> policy dédiée après avoir arrêté les collectors EDOT et contrôlé les
> doublons.

### 3.6 Applications Java

> **Pourquoi et quoi - utiliser EDOT Java**
>
> **Choix :** les applications Java exportent leurs traces et métriques en
> OTLP vers le Gateway Kubernetes.
>
> **Pourquoi :** l’instrumentation suit le même protocole que les collectors
> Kubernetes et conserve la corrélation service, pod, conteneur et trace. Les
> logs stdout restent collectés par le DaemonSet `filelog`, ce qui évite de
> modifier le format Logback ECS existant.
>
> **Alternatives considérées :** l’agent APM Java classique conserverait le
> chemin APM historique. Il créerait un modèle de collecte différent de celui
> des métriques et traces OTLP déjà utilisés par les applications.
>
> **Retour arrière :** désactiver l’export OTLP de l’application et restaurer
> les paramètres APM prévus par l’image concernée, sans modifier les logs
> stdout.

## 4. Conséquences

Cette décision conserve les dashboards et data streams ECS des VM. Elle garde
également les dashboards OTel Kubernetes alignés avec les receivers qui les
alimentent.

Elle impose deux modèles de données dans Elasticsearch. Les opérateurs doivent
donc choisir les dashboards selon le composant observé et éviter de mélanger
les data views ECS et OTel dans une même vérification.

Elle conserve deux plans de gestion. Fleet classique pilote les agents VM et
Fleet Server ; OpAMP pilote les collectors EDOT Kubernetes. Cette séparation
permet de gérer les policies Fleet des VM sans convertir ces agents en
collectors standalone.

Elle conserve le Gateway local comme point de passage des logs, traces et
métriques Kubernetes. Ce point de passage permet de conserver le traitement
commun, le buffer Kafka et l’export backend définis par l’architecture.

Elle reporte la migration OTel de System, Kafka, MongoDB et PostgreSQL. Cette
migration reste possible après la disponibilité de packages d’entrée adaptés,
la validation des dashboards OTel et la comparaison des volumes indexés.

## 5. Invariants et contrôles

Les évolutions de cette architecture doivent conserver les invariants suivants :

1. une seule collecte active par signal et par source ;
2. les VM utilisent `data-fleet` ou `otel-fleet` avec export direct vers
   Elasticsearch ;
3. Kubernetes utilise les collectors EDOT déclarés dans
   `platform/kubernetes/base/observability/otel-kafka.yaml` ;
4. les topics Kafka OTLP restent séparés par signal ;
5. aucun secret n’est versionné dans les policies ou les manifests ;
6. les dashboards ciblent explicitement le schéma ECS ou OTel correspondant.

Les contrôles reproductibles sont :

```bash
make architecture-status
make kubernetes-validate
make ansible-validate
make dashboards-verify
```

Le contrôle live Fleet doit confirmer les agents VM actifs, les collectors
OpAMP Kubernetes et l’absence de doublons actifs avant toute modification de
policy.

## 6. Références

- [Architecture](architecture.md)
- [Briques de remontée de la télémétrie](briques-remontee-telemetrie.md)
- [Policies Fleet](../architecture/platform/elk/fleet/README.md)
- [Bootstrap des policies Fleet](../architecture/platform/elk/scripts/bootstrap-fleet-policies.sh)
- [Configuration EDOT Kubernetes](../architecture/platform/kubernetes/base/observability/otel-kafka.yaml)
- [Elastic Agent comme collector OTel](https://www.elastic.co/docs/reference/fleet/elastic-agent-as-otel-collector)
- [Packages d’intégration OTel](https://www.elastic.co/docs/reference/fleet/otel-integrations)
- [Composants inclus dans Elastic Agent](https://www.elastic.co/docs/reference/edot-collector/components)
- [System OpenTelemetry Assets](https://www.elastic.co/docs/reference/integrations/system_otel)
- [Kafka OpenTelemetry Assets](https://www.elastic.co/docs/reference/integrations/kafka_otel)
- [MongoDB OpenTelemetry Assets](https://www.elastic.co/docs/reference/integrations/mongodb_otel)
- [PostgreSQL OpenTelemetry Assets](https://www.elastic.co/docs/reference/integrations/postgresql_otel)

La décision s’appuie sur les fichiers IaC du dépôt et sur les documentations
Elastic consultées le 2026-09-21. Les choix d’architecture sont normatifs ;
les statuts de packages et de receivers restent dépendants de la version
Elastic Stack déclarée par le dépôt.
