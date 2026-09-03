# APM des applications Java sur Kubernetes

Ce guide décrit le chemin APM historique de la v1. Pour la chaîne v2 basée sur
OpenTelemetry, utiliser le [comparatif v1/v2/v3](architecture-v1-v2-v3.md)
et le [guide de déploiement](deploiement-et-exploitation.md).

Les commandes de ce document sont à exécuter depuis la racine du dépôt, après
avoir sélectionné `v1` avec `make architecture-switch VERSION=v1`.

Ce document décrit les impacts de la mise en place d’Elastic APM pour les
applications Java du POC et fournit une recette de vérification reproductible.
Il couvre les trois services `order-service`, `inventory-service` et
`restock-service`.

## Chaîne de collecte

```text
application Spring Boot
    → agent Java Elastic APM (-javaagent)
    → APM Server Kubernetes (HTTPS)
    → Logstash (Lumberjack)
    → Elasticsearch (data streams traces-* et metrics-*)
    → Kibana / APM
```

Les logs JSON ECS suivent un chemin distinct :

```text
stdout du conteneur → Elastic Agent Kubernetes → Logstash → Elasticsearch
```

L’agent Java produit les traces, erreurs et métriques APM. L’Elastic Agent ne
collecte pas les traces applicatives ; il collecte les logs des conteneurs et
les métriques Kubernetes. Les métriques applicatives Prometheus, notamment les
métriques Kafka client exposées par Actuator, sont également collectées par
l’Elastic Agent Kubernetes.

## Composants Kubernetes à installer

Oui, l’APM nécessite plusieurs composants côté Kubernetes. Ils sont toutefois
déployés par la plateforme Elastic du dépôt ; il n’est pas nécessaire
d’installer un agent APM Java sous forme de DaemonSet.

### Prérequis du cluster

Ces éléments doivent déjà être disponibles sur le cluster :

- un cluster Kubernetes fonctionnel ;
- `kubectl`, Helm et Kustomize côté opérateur ;
- Traefik, utilisé par les IngressRoutes TLS du POC.

### Composants installés par le dépôt

`make eck-deploy` installe ou met à jour l’opérateur ECK dans
`elastic-system`. ECK gère ensuite les ressources Elastic Kubernetes.

`make elk-deploy` installe ou applique les composants suivants dans
`elastic-stack` :

| Composant | Fonction APM ou observabilité |
| --- | --- |
| Elasticsearch | Stockage des traces, erreurs et métriques |
| Kibana | Consultation APM et installation des assets Elastic |
| APM Server (`ApmServer`) | Réception HTTPS des agents Java |
| Logstash | Routage APM vers les data streams Elasticsearch |
| Fleet Server (`Agent`) | Gestion des Elastic Agents Fleet |
| Elastic Agent Kubernetes (`Agent`) | Logs des pods et métriques Kubernetes/Prometheus |
| `kube-state-metrics` | État des Deployments, pods et ressources Kubernetes |
| Package Registry | Fourniture locale des packages Elastic |
| IngressRoutes TLS | Accès externe aux endpoints Elastic |

Le manifest Kustomize de la plateforme est le point d’entrée de ces ressources :
[`v1/platform/kubernetes/base/observability/kustomization.yaml`](../v1/platform/kubernetes/base/observability/kustomization.yaml).
Elasticsearch et Kibana sont initialement créés par la release Helm ECK ; les
autres composants sont appliqués par Kustomize.

### Ce qui n’est pas installé

Le dépôt n’installe pas de collecteur de traces supplémentaire :

- pas de DaemonSet APM Java ;
- pas d’EDOT Collector ;
- pas de Filebeat ou Metricbeat pour les applications Kubernetes ;
- pas de sortie Elasticsearch directe depuis APM Server.

Le chemin APM reste donc : agent Java dans le conteneur → APM Server →
Logstash → Elasticsearch. L’Elastic Agent Kubernetes est réservé aux logs,
aux métriques Kubernetes et au scraping Prometheus des applications.

### Vérifier l’installation des composants

Après `make elk-deploy`, contrôler :

```bash
kubectl -n elastic-system get statefulset elastic-operator
kubectl -n elastic-stack get elasticsearch,kibana,apmserver,agent
kubectl -n elastic-stack get deployment
kubectl -n elastic-stack get ingressroute
```

Résultat attendu : l’opérateur ECK est disponible, Elasticsearch/Kibana/APM
Server sont prêts, les Agents Fleet sont actifs et les Deployments
`apm-logstash` et `kube-state-metrics` sont disponibles. Fleet utilise l'EPR
public Elastic pour télécharger les packages.

Pour vérifier la chaîne complète avant de déployer une application :

```bash
make apm-logstash-deploy
kubectl -n elastic-stack rollout status deployment/apm-logstash --timeout=300s
kubectl -n elastic-stack rollout status deployment/apm-server-apm-server --timeout=300s
```

Le namespace applicatif et les Secrets APM sont ensuite créés ou synchronisés
par `make apps-deploy` via la cible `apm-token-sync`.

## Impacts côté applications

### Dépendances et code Java

L’instrumentation APM ne nécessite pas de SDK Elastic dans le code métier. Le
code reste instrumenté au démarrage par l’agent Java. Les dépendances
Micrometer/Prometheus sont nécessaires uniquement pour exposer les métriques
applicatives sur `/actuator/prometheus`.

Les trois modules Spring Boot doivent conserver :

- Java 21 et la version de l’agent définie par le `Dockerfile` ;
- les logs structurés ECS sur stdout ;
- l’exposition Actuator de `health`, `info` et `prometheus` ;
- les noms de service APM stables : `order-service`, `inventory-service` et
  `restock-service`.

### Image Docker

Le `Dockerfile` multi-stage télécharge l’agent Java puis démarre chaque image
avec :

```text
-javaagent:/opt/elastic-apm-agent.jar
```

Une image reconstruite doit donc être disponible dans le runtime Kubernetes
avant le rollout :

```bash
make apps-test
make apps-build
make images-import
make apps-deploy
```

Le tag Docker est contrôlé par `APP_IMAGE_TAG`. Il doit être identique entre
`make apps-build`, `make images-import` et les manifests déployés.

### Configuration runtime

Les variables suivantes sont injectées par le Deployment Kubernetes :

| Variable | Rôle |
| --- | --- |
| `ELASTIC_APM_SERVICE_NAME` | Identité stable du service dans APM |
| `ELASTIC_APM_SERVICE_VERSION` | Version déclarée de l’application |
| `ELASTIC_APM_ENVIRONMENT` | Environnement APM, ici `homologation` |
| `ELASTIC_APM_APPLICATION_PACKAGES` | Packages applicatifs à reconnaître dans les traces |
| `ELASTIC_APM_SERVER_URL` | Endpoint interne HTTPS d’APM Server |
| `ELASTIC_APM_SECRET_TOKEN` | Authentification d’ingestion, fournie par Secret Kubernetes |
| `ELASTIC_APM_ENABLE_LOG_CORRELATION` | Ajout de `trace.id` et `transaction.id` aux logs ECS |
| `KUBERNETES_NAMESPACE` | Namespace transmis à Logstash pour le routage |

Le token et le certificat ne sont jamais codés dans Git. `make apps-deploy`
copie le token et le certificat produits par ECK dans le namespace
`h0tl-supermarche-app`, puis prépare un truststore Java dans un init container.

## Impacts côté Kubernetes

### Ressources de la plateforme

Le namespace `elastic-stack` héberge :

- `ApmServer`, géré par ECK ;
- `apm-logstash`, qui reçoit APM sur le port interne `5044` ;
- la configuration des pipelines et la clé API Elasticsearch de Logstash ;
- Kibana et les packages APM nécessaires à la consultation.

`ApmServer` n’a pas de sortie Elasticsearch directe dans ce POC. Sa sortie
unique est Logstash :

```text
apm-server-apm-http.elastic-stack.svc:8200
    → apm-logstash.elastic-stack.svc:5044
```

La configuration est déclarée dans
[`apm-server.yaml`](../v1/platform/kubernetes/base/observability/apm-server.yaml)
et [`apm-logstash.yaml`](../v1/platform/kubernetes/base/observability/apm-logstash.yaml).

### Ressources applicatives

Le namespace `h0tl-supermarche-app` contient les Deployments, les Services et
les Secrets nécessaires aux applications. Chaque Deployment APM doit
conserver :

- `ELASTIC_APM_SERVER_URL` vers le service interne APM Server ;
- la référence au Secret de token APM ;
- la référence au Secret de certificat APM Server ;
- le volume `emptyDir` du truststore et l’init container `apm-truststore` ;
- `imagePullPolicy: IfNotPresent` pour les images importées localement.

Le certificat permet à la JVM de vérifier le TLS interne ECK. Sans ce
truststore, l’agent peut échouer avec une erreur SSL avant toute ingestion.
Chaque application scrutée par l’Elastic Agent doit également disposer d’un
Service Kubernetes. Le Service `restock-service` expose le port `3002` pour
permettre le scrape Prometheus interne.

### Routage des signaux

Logstash normalise l’identité issue du namespace Kubernetes. Pour
`h0tl-supermarche-app` :

| Élément | Valeur |
| --- | --- |
| type d’environnement | `h` → `homologation` |
| code plateforme | `0tl` |
| namespace applicatif | `supermarche-app` |
| dataset APM traces | `apm-0tl` |
| dataset APM traces et métriques applicatives | `apm-0tl` |
| namespace data stream | `homologation` |

Le dataset est mutualisé au niveau plateforme et le namespace du data stream
porte l’environnement. Les traces et les métriques APM applicatives détaillées
suivent cette règle. Les métriques APM agrégées qui ne portent pas le namespace
Kubernetes restent dans leur data stream d’origine.

## Déploiement dans le bon ordre

Pour une installation ou une modification de la plateforme complète :

```bash
source ./platform/elk/scripts/load-credentials.sh
make elk-deploy
make apps-test
make apps-build
make images-import
make apps-deploy
```

Pour une modification limitée au code applicatif, la plateforme déjà
disponible permet de commencer à `make apps-test`.

Valider le rendu Kubernetes avant toute application de manifest :

```bash
make kubernetes-validate
```

## Points de vérification

### 1. Manifests et ressources Kubernetes

```bash
make kubernetes-status
kubectl -n elastic-stack get deployment apm-server-apm-server apm-logstash
kubectl -n h0tl-supermarche-app get deployment,pods,service
kubectl -n h0tl-supermarche-app get secret order-service-apm-token order-service-apm-server-ca
```

Résultat attendu : les Deployments Elastic et applicatifs sont disponibles,
les trois pods applicatifs sont `1/1 Running`, et les deux Secrets APM existent
dans le namespace applicatif. Ne jamais afficher leur contenu.

### 2. Probes et Actuator

Vérifier les probes depuis Kubernetes :

```bash
kubectl -n h0tl-supermarche-app describe pod -l app.kubernetes.io/name=inventory-service
```

Résultat attendu : les probes `/api/health` sont en succès. Pour contrôler
Actuator sans exposer le service hors du cluster :

```bash
kubectl -n h0tl-supermarche-app run actuator-check --rm --attach --stdin \
  --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl --fail --silent http://inventory-service:3001/actuator/health
```

Le résultat attendu contient `"status":"UP"`.

### 3. Agent Java et TLS

```bash
kubectl -n h0tl-supermarche-app logs deployment/inventory-service --tail=100
kubectl -n h0tl-supermarche-app get pod -l app.kubernetes.io/name=inventory-service \
  -o jsonpath='{.items[0].spec.containers[0].env[*].name}'
```

Vérifier l’absence d’erreur `SSLHandshakeException`, `secret token` ou
`APM Server`. La liste des variables doit inclure les variables `ELASTIC_APM_*`
et `KUBERNETES_NAMESPACE`.

### 4. APM Server et Logstash

```bash
kubectl -n elastic-stack logs deployment/apm-server-apm-server --tail=100
kubectl -n elastic-stack logs deployment/apm-logstash --tail=100
kubectl -n elastic-stack get endpoints apm-logstash
```

Résultat attendu : pas d’erreur d’authentification, de connexion TLS ou
d’indexation Elasticsearch ; l’endpoint Logstash possède une adresse pour les
ports APM `5044` et logs/métriques Kubernetes `5045`.

### 5. Générer et retrouver une trace

Générer une transaction HTTP métier :

```bash
make order-service-command ORDER_PRODUCT_ID=PASTA-500G ORDER_QUANTITY=1
```

Dans Kibana > Observability > APM > Services, rechercher le service
`order-service`, puis la transaction HTTP et l’appel vers `inventory-service`.
Dans APM, contrôler :

- `service.name` et `service.environment` ;
- la présence d’un `trace.id` ;
- les spans Kafka, MongoDB et PostgreSQL lorsque le chemin les traverse ;
- l’absence d’erreur d’export côté application.

### 6. Vérifier les data streams et la corrélation des logs

Dans Discover, utiliser les filtres suivants :

```kql
data_stream.dataset:"apm-0tl"
and data_stream.namespace:"homologation"
and service.name:("order-service" or "inventory-service" or "restock-service")
```

Pour les logs applicatifs :

```kql
data_stream.dataset:"kube-0tl"
and service.environment:"homologation"
and labels.ptf:"0tl"
and labels.namespace:"supermarche-app"
```

Sur un log produit pendant une transaction, vérifier la présence de `trace.id`
et l’utilisation de « View trace » ou « View surrounding logs » depuis APM.

### 7. Métriques Kafka côté client

Contrôler d’abord l’exposition locale :

```bash
kubectl -n h0tl-supermarche-app run metrics-check --rm --attach --stdin \
  --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl --fail --silent http://inventory-service:3001/actuator/prometheus \
  | grep -E 'kafka_(producer|consumer)_' | head
```

Puis rechercher dans Discover :

```kql
data_stream.dataset:"app.prometheus.0tl"
and data_stream.namespace:"homologation"
and service.name:"order-service"
and prometheus.metrics.kafka_producer_linger_milliseconds:*
```

Les champs à rechercher sont notamment :

- `prometheus.metrics.kafka_producer_linger_milliseconds` : valeur configurée
  de `linger.ms` ;
- `prometheus.metrics.kafka_producer_batch_size_configured_bytes` : valeur
  configurée de `batch.size` ;
- `prometheus.metrics.kafka_producer_batch_size_avg` et
  `prometheus.metrics.kafka_producer_batch_size_max` : taille runtime des
  batches effectivement envoyés.

Le champ `metricset.name` vaut `collector` pour ce flux. Il ne faut pas le
filtrer sur `kafka` : les métriques Kafka client sont scrutées sur l’endpoint
Prometheus de l’application. Elles sont stockées dans le data stream dédié
`metrics-app.prometheus.0tl-homologation`, séparé des métriques APM natives
afin d’éviter un conflit de mapping ECS. Les métriques des brokers Kafka sont
issues de Metricbeat sur `data-01` et passent par Logstash `5045`.

Si l’endpoint expose les métriques mais qu’aucun document n’apparaît, vérifier
les logs de l’Elastic Agent Kubernetes, le ciblage du Service DNS et les logs
Logstash. Les métriques Kafka client ne sont pas les métriques des brokers,
qui sont collectées séparément par Metricbeat sur `data-01`.

## Diagnostic rapide

| Symptôme | Contrôles prioritaires |
| --- | --- |
| Service absent dans APM | image avec `-javaagent`, variables `ELASTIC_APM_*`, logs du pod |
| Erreur SSL côté agent | Secret CA, init container, `JAVA_TOOL_OPTIONS`, URL interne APM |
| Erreur 401/403 | présence et synchronisation du Secret de token APM |
| Traces reçues mais mauvais data stream | `KUBERNETES_NAMESPACE`, convention `h0tl-supermarche-app`, pipeline Logstash |
| Logs sans `trace.id` | `ELASTIC_APM_ENABLE_LOG_CORRELATION=true`, logs ECS sur stdout |
| Métriques Kafka absentes | `/actuator/prometheus`, stream Elastic Agent, pipeline et data stream |
| Rollout bloqué | `kubectl describe pod`, probes `/api/health`, image importée dans k3d |

## Checklist de recette

- [ ] `make kubernetes-validate` réussit.
- [ ] `make apps-test` réussit.
- [ ] APM Server et Logstash sont `1/1`.
- [ ] Les trois applications sont `1/1 Running` sans redémarrage.
- [ ] Les probes `/api/health` et Actuator sont disponibles.
- [ ] Une transaction HTTP apparaît dans APM.
- [ ] Une trace Kafka apparaît après le flux de commande en ligne.
- [ ] Les spans MongoDB et PostgreSQL sont visibles pour une réservation.
- [ ] Les logs ECS contiennent un identifiant de trace corrélable.
- [ ] Les métriques Kafka client apparaissent dans
      `metrics-app.prometheus.0tl-homologation`.
- [ ] Le dataset traces reste lié à la plateforme (`apm-0tl`) et le namespace sépare
      l’environnement (`homologation`).

## Références du dépôt

- [`apps/ADDING_APPLICATION.md`](../apps/ADDING_APPLICATION.md) : intégrer une
  nouvelle application Java observée ;
- [`kubernetes/apps/supermarket-demo/`](../kubernetes/apps/supermarket-demo/) :
  base commune et patches des Deployments applicatifs ;
- [`v1/platform/kubernetes/base/observability/README.md`](../v1/platform/kubernetes/base/observability/README.md) :
  chaîne APM, Logstash et règles de routage ;
- [`Makefile`](../Makefile) : cibles de test, validation et déploiement.
