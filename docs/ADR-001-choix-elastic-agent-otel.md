# ADR-001 : adopter EDOT et OpenTelemetry pour une architecture avec gateway

Cette décision définit le plan de données de l’architecture d’observabilité.
Le choix principal est d’utiliser EDOT et les composants OpenTelemetry afin de
conserver une chaîne OTLP commune et de faire transiter les signaux par une
gateway avant Kafka et le backend Elastic. Fleet reste un plan de contrôle
disponible, mais ses integrations classiques ne constituent pas le chemin
actif de collecte décrit ici.

|                |                                            |
| -------------- | ------------------------------------------ |
| **Statut**     | Acceptée                                   |
| **Date**       | 2026-09-21                                 |
| **Périmètre**  | VM, Kubernetes, applications Java et transport |
| **Audience**   | Développeurs, exploitants et responsables de la plateforme |
| **Références** | [`Documentation système`](README.md), [`architecture.md`](architecture.md) |

---

## 1. Décision

L’architecture utilise EDOT et OpenTelemetry pour le plan de données. EDOT
apporte les distributions et l’intégration Elastic ; OpenTelemetry fournit le
modèle de collecte, le protocole OTLP et les composants de pipeline. Les
producteurs n’exportent pas directement vers Elasticsearch. Ils envoient leurs
signaux à la gateway OTLP, qui centralise le traitement d’entrée, publie dans
Kafka, puis laisse le backend EDOT exporter vers Elastic.

| Composant | Collecte retenue | Gestion | Transport et destination |
| --- | --- | --- | --- |
| VM actives | Elastic Agent EDOT standalone avec `filelog`, `hostmetrics` et les receivers de données | Configuration Ansible locale | OTLP vers la gateway Edge, Kafka, backend EDOT, puis Elastic |
| Kubernetes | EDOT Collector avec `hostmetrics`, `kubeletstats`, `k8scluster` et `filelog` | Configuration Kustomize locale | OTLP vers la gateway Edge, Kafka, puis backend EDOT |
| Applications Java | Agent EDOT Java, OTLP et Micrometer OTLP | Configuration Kubernetes | OTLP vers la gateway Edge, Kafka, puis backend EDOT |
| Gateway et collectors | EDOT Collector | Configuration Ansible et Kustomize versionnée | Réception OTLP, routage vers Kafka, puis export vers Elasticsearch ou APM Server |
| Fleet Server | Elastic Agent Fleet Server | Fleet classique | Plan de contrôle optionnel, sans collecte de ces signaux |

Ce choix répond à trois contraintes :

1. conserver une compatibilité avec l’écosystème OpenTelemetry et le protocole
   OTLP pour les applications, Kubernetes et les VM ;
2. disposer d’un point de passage unique avec la gateway pour appliquer le
   traitement commun et contrôler le routage ;
3. conserver l’intégration Elastic et ses distributions EDOT sans imposer un
   collector OTel générique séparé pour chaque environnement.

La gateway est donc une conséquence directe de la décision. Elle reçoit les
signaux OTLP des producteurs, les transmet à Kafka par signal, et évite de
coupler chaque producteur à Elasticsearch, APM Server ou à la topologie Kafka.

Les data streams ECS historiques et les data streams OTel coexistent selon les
composants et les dashboards qui les consomment. Cette coexistence ne change
pas le choix du plan de données : les nouveaux flux décrits par cette ADR
suivent EDOT, OTLP, gateway, Kafka et backend.

### 1.1 Application du choix aux VM

Chaque VM active utilise Elastic Agent en mode EDOT standalone. L’agent
exécute les composants de collecte EDOT et exporte en OTLP vers le Collecteur
Edge. Il ne s’agit pas d’une package policy Fleet classique appliquée à la
VM.

Le chemin de données devient :

```text
Elastic Agent EDOT sur la VM
    -> OTLP
Collecteur Edge
    -> Kafka par signal
Collecteur Backend
    -> Elasticsearch ou APM Server
```

Cette décision s’applique à `poc-01`, `otel-backend-01`, `otel-edge-01` et
`elk-01`. Fleet Server est conservé pour les interfaces Elastic et les usages
de contrôle, mais il n’est pas utilisé pour collecter les mêmes logs ou
métriques. Les anciennes package policies Fleet qui collecteraient ces signaux
doivent rester non assignées afin d’éviter les doublons.

Les sections 3.1 à 3.4 documentent les alternatives Fleet classiques évaluées.
Elles ne décrivent pas le chemin actif.

### 1.2 Rôle d’OpAMP

Dans cette architecture, OpAMP sert à superviser les agents et les
collecteurs EDOT. Il remonte leur état, leur télémétrie interne et les
indicateurs utiles au suivi dans Fleet. Il ne sert pas à gérer leur
configuration.

La configuration effective reste déclarée dans le dépôt, principalement dans
les templates Ansible pour les VM et dans les manifests Kustomize pour
Kubernetes. Une évolution de configuration doit donc être modifiée dans ces
fichiers, validée, puis appliquée par le mécanisme de déploiement prévu. La
présence d’un endpoint OpAMP ou l’activation du monitoring OpAMP ne transforme
pas les agents EDOT standalone en agents gérés par une policy Fleet.

## 2. Contexte vérifié

Le dépôt décrit une architecture hybride dans laquelle les VM, Kubernetes et
les applications utilisent EDOT et OpenTelemetry. Les producteurs envoient
leurs signaux en OTLP à la gateway Edge, puis les flux passent par Kafka et le
backend EDOT avant leur export vers Elastic. Cette topologie est décrite dans
[`architecture.md`](architecture.md:1) et dans
[`briques-remontee-telemetrie.md`](briques-remontee-telemetrie.md:1).

Le script [`bootstrap-fleet-policies.sh`](../architecture/platform/elk/scripts/bootstrap-fleet-policies.sh:107)
déclare les packages Fleet classiques pour les VM. Les policies concernent
System sur les VM et Kafka, MongoDB et PostgreSQL sur `poc-01`.

Le manifeste [`otel-kafka.yaml`](../architecture/platform/kubernetes/base/observability/otel-kafka.yaml:101)
déclare les collectors EDOT Kubernetes, leurs receivers et leurs extensions
Les collectors Kubernetes utilisent une configuration versionnée et ne
s’enrôlent pas dans Fleet.

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

Les quatre premières sections décrivent des alternatives Fleet classiques
écartées pour le plan de données actif. Les choix normatifs sont la décision
globale de la section 1, l’application aux VM en section 1.1 et les choix EDOT
Kubernetes et Java des sections 3.5 et 3.6.

### 3.1 Alternative écartée pour les VM et les métriques système

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

### 3.2 Alternative écartée pour Kafka

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

### 3.3 Alternative écartée pour MongoDB

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

### 3.4 Alternative écartée pour PostgreSQL

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
> **Choix :** Kubernetes utilise EDOT Collector configuré par Kustomize pour les métriques,
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

Elle conserve Fleet Server comme point d’observation OpAMP disponible, sans en
faire le collecteur ni le gestionnaire de configuration du chemin actif. Les
données des VM suivent le plan OTel et le chemin Edge, Kafka et backend.

Elle conserve le Gateway local comme point de passage des logs, traces et
métriques Kubernetes. Ce point de passage permet de conserver le traitement
commun, le buffer Kafka et l’export backend définis par l’architecture.

Elle impose la validation des receivers EDOT retenus pour System, Kafka,
MongoDB et PostgreSQL, ainsi que la comparaison des volumes indexés. Les
dashboards ECS historiques ne sont conservés que pour les données déjà
produites ou pour les composants qui ne sont pas encore basculés.

## 5. Invariants et contrôles

Les évolutions de cette architecture doivent conserver les invariants suivants :

1. une seule collecte active par signal et par source ;
2. les VM utilisent Elastic Agent en mode EDOT et exportent leurs signaux en
   OTLP vers le Collecteur Edge ;
3. Kubernetes utilise les collectors EDOT déclarés dans
   `platform/kubernetes/base/observability/otel-kafka.yaml` ;
4. les topics Kafka OTLP restent séparés par signal et le Collecteur Backend
   les consomme ;
5. les anciennes policies Fleet qui doublonneraient la collecte EDOT sont
   désactivées ;
6. aucun secret n’est versionné dans les policies ou les manifests ;
7. les dashboards ciblent explicitement le schéma ECS ou OTel correspondant.

Les contrôles reproductibles sont :

```bash
make architecture-status
make kubernetes-validate
make ansible-validate
make dashboards-verify
```

Le contrôle live doit confirmer les agents EDOT actifs, les collectors
Kubernetes prêts et l’absence de doublons actifs.

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
