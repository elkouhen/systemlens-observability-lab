# Ajouter une application Java observée

Ce guide décrit le raccordement à la chaîne d'observabilité architecture. Conserver le
socle applicatif commun et ajouter le patch d'instrumentation OTel décrit dans
`kubernetes/apps/supermarket-demo/default/otel-instrumentation.yaml`.

Ce guide décrit l'ajout d'une application Java Spring Boot à la chaîne
d'observabilité du lab. Le chemin des signaux est le suivant :

```text
application Java → agent Java OTel injecté → collecteur daemon otel-kube-stack
  → Collecteur Edge → Kafka → Collector backend → Elasticsearch (OTel natif)
```

L'agent Java OTel, injecté par l'opérateur du chart
`opentelemetry-kube-stack` (ADR-019), produit les traces et les logs,
Micrometer les métriques applicatives. Le collecteur daemon du nœud pose les
attributs Kubernetes et transmet à l'Edge. Les logs sont OTel natifs, sans format ECS (ADR-012).
Le Collecteur Edge reçoit l'OTLP, choisit le topic Kafka de la plateforme
du namespace et pose le dataset ; le Collector backend lit la plateforme et
l'environnement dans le nom du topic (ADR-015).

L'application `apps/demo-api` est l'exemple minimal de ce guide : un seul
service, sa plateforme `demo`, ses manifests sous `kubernetes/apps/demo-api/`.
Sans Micrometer, elle laisse l'agent exporter les métriques JVM
(`OTEL_METRICS_EXPORTER=otlp`, posé par l'Instrumentation), au format
sémantique OTel. Toutes les
métriques, celles de l'agent comme celles de Micrometer, sont indexées en
mapping OTel natif dans `metrics-<dataset>.otel-<environnement>` (ADR-018).

## Préparer l'application

L'image ne contient pas d'agent : l'`ENTRYPOINT` lance seulement
`java -jar`. L'opérateur OpenTelemetry injecte l'agent Java OpenTelemetry au
démarrage du pod (init container `opentelemetry-auto-instrumentation-java`
et `JAVA_TOOL_OPTIONS`). C'est le seul agent d'instrumentation : ne pas
ajouter l'agent Java Elastic APM ni de `-javaagent`, qui attacherait l'agent
deux fois. Le `Dockerfile` de `supermarket-demo` est la référence du dépôt ;
chaque cible d'image fixe `OTEL_SERVICE_NAME` pour une exécution hors
Kubernetes.

Les logs passent par l'agent : son instrumentation Logback exporte chaque
log en OTLP, avec le `trace_id` et le `span_id` du span courant. Ne pas
configurer de format structuré (`logging.structured.format.console`) ni
d'appender d'export : stdout garde le texte par défaut de Spring Boot, lu par
`kubectl logs` mais pas collecté.

## Annoter le Deployment

Le patch `otel-instrumentation.yaml` de l'overlay ajoute deux annotations au
gabarit de pod :

```yaml
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-java: elastic-stack/otel-kube-stack
        resource.opentelemetry.io/service.version: "1.0.0"
```

La première demande l'injection de l'agent décrit par le CR
`Instrumentation` `elastic-stack/otel-kube-stack`
(`architecture/platform/helm/opentelemetry-kube-stack-values.yaml`). Ce CR
porte la configuration commune : version de l'agent, endpoint du collecteur
daemon, exporteurs OTLP des traces, métriques et logs, et options Logback.
La seconde garde `service.version` sur la version applicative, au lieu du tag
de l'image. `service.name` vient du nom du Deployment.

Une application qui exporte ses métriques par Micrometer OTLP pointe vers le
même collecteur :

```yaml
env:
  - name: MANAGEMENT_OTLP_METRICS_EXPORT_URL
    value: http://otel-kube-stack-daemon-collector.elastic-stack.svc.cluster.local:4318/v1/metrics
```

L'application ne déclare ni attribut Kubernetes, ni clé Edge, ni plateforme,
ni environnement. Le collecteur daemon pose `k8s.namespace.name`,
`k8s.pod.name`, `k8s.pod.uid`, `k8s.node.name`, `k8s.deployment.name`,
`host.name` (le nœud) et `service.node.name` (le pod) par `k8sattributes`,
puis transmet à l'Edge avec sa propre clé. `k8s.namespace.name` choisit la
plateforme : le collecteur Edge pose `k8s.cluster.name` et
`deployment.environment.name` depuis l'entrée du namespace dans
`otel_edge_namespace_routes`
(`architecture/ansible/inventory/group_vars/otel_edge_nodes.yml`) et écrase
toute valeur envoyée. Un namespace inconnu de l'Edge est rejeté : un nouveau
namespace applicatif demande donc une nouvelle entrée.

Les options Logback de l'Instrumentation
(`OTEL_INSTRUMENTATION_LOGBACK_APPENDER_EXPERIMENTAL_CAPTURE_KEY_VALUE_PAIR_ATTRIBUTES`,
`..._EXPERIMENTAL_LOG_ATTRIBUTES`) transforment les paires SLF4J
`addKeyValue` en attributs du log (`event.action`, `business.units_sold`) et
ajoutent `thread.name` et `thread.id`.

Après le déploiement, `make otel-instrumentation-verify` vérifie que l'agent
est injecté et exporte vers le daemon. Un pod démarré avant l'opérateur, ou
pendant une indisponibilité du webhook, démarre sans agent : le redémarrer.

Une exception traitée par un `@ExceptionHandler` n'atteint pas
l'instrumentation servlet de l'agent et ne produit pas d'erreur APM, même si
la réponse est un 500. Pour qu'elle apparaisse dans l'UI APM, l'enregistrer
sur le span courant avec l'API OpenTelemetry, reliée à l'agent
(`io.opentelemetry:opentelemetry-api`, version gérée par le BOM de Spring
Boot) : `Span.current().recordException(e)` puis
`setStatus(StatusCode.ERROR, ...)`.

## Convention d'environnement

Le namespace Kubernetes suit le format
`<type><ptf_sur_3_caracteres>-<namespace>`, par exemple
`h0tl-supermarche-app` : `h` pour homologation, `0tl` pour la plateforme,
`supermarche-app` pour le périmètre applicatif.

Aucun traitement ne découpe cette valeur. L'environnement affiché par l'UI APM
vient de l'attribut de ressource `deployment.environment.name` du patch OTel
(nom courant d'OpenTelemetry, à la place de `deployment.environment`), indexé
en `service.environment` sur les traces et les métriques APM. Il ne choisit
pas le data stream : seule la route Edge le fait. Le namespace est transmis
par `k8s.namespace.name` et indexé en `kubernetes.namespace`.

## Data streams alimentés

Le dataset nomme l'application, le namespace nomme l'environnement (ADR-010),
la plateforme est le champ `platform.id`. Le collecteur Edge publie les
signaux dont la ressource porte `k8s.namespace.name` = `h0tl-supermarche-app`
dans les topics `otel-<signal>-supermarche-homologation` de la plateforme
`supermarche` et pose le dataset `supermarche` sur les trois signaux
(ADR-015). Le collecteur backend lit dans le nom du topic la plateforme et
le namespace `homologation`. Tous les signaux sont OTel natifs, sans
conversion ECS (ADR-018) :

| Signal | Data stream |
| --- | --- |
| Traces | `traces-supermarche.otel-homologation` |
| Métriques APM agrégées | `metrics-{transaction,service_transaction,service_destination,service_summary}.1m.otel-homologation` |
| Métriques Micrometer et JVM | `metrics-supermarche.otel-homologation` |
| Logs applicatifs | `logs-supermarche.otel-homologation` |

Les trois signaux reçoivent le suffixe `.otel` du mode de mapping OTel. Le
processeur `elasticapm` du collecteur backend enrichit les traces pour l'UI
APM, et le connecteur `elasticapm` en tire les métriques agrégées ; les
intervalles `10m` et `60m` suivent la même règle. Les métriques Kubernetes des pods (`kubeletstats`, `k8s_cluster`) gardent le
dataset de leur receiver, en namespace `homologation`.

### Déclarer une nouvelle application comme plateforme

Un namespace Kubernetes est une plateforme dans un environnement (ADR-015).
Une nouvelle application demande une plateforme et son entrée de namespace.

1. Ajouter le couple à `otel_platforms` dans
   `architecture/ansible/inventory/group_vars/otel_backend_nodes.yml` :

   ```yaml
   - platform: caisse
     environment: homologation
   ```

2. Ajouter une entrée à `otel_edge_namespace_routes` dans
   `architecture/ansible/inventory/group_vars/otel_edge_nodes.yml` :

   ```yaml
   - kubernetes_namespace: h0tl-caisse-app
     platform: caisse
     environment: homologation
     dataset: caisse          # [a-z0-9_.], ou receiver
   ```

   Ses signaux iront dans `logs-caisse.otel-homologation`,
   `metrics-caisse.otel-homologation` et `traces-caisse.otel-homologation`,
   tous avec `platform.id` = `caisse`. Le
   rôle `otel_edge` refuse un namespace dupliqué, un format invalide ou une
   plateforme absente de `otel_platforms`.
3. Valider avec `make otel-config-validate`, créer les topics avec
   `make otel-backend-vm-provision`, puis appliquer la table avec
   `make otel-edge-vm-provision`.

Les attributs `data_stream.dataset`, `data_stream.namespace` et
`platform.id` posés par l'application sont supprimés
par l'Edge. Sans entrée dédiée, les signaux de l'application sont rejetés par
l'Edge et comptés par `make otel-routing-verify`.

Les trois signaux portent la ressource de l'agent sous `resource.attributes`
(`service.name`,
`service.version`, `deployment.environment.name`, `k8s.*`, `telemetry.distro.*`).

### Noms des spans HTTP client

Le collecteur Edge renomme les spans HTTP client de toutes les applications
([ADR-011](../architecture/docs/ADR-011-nom-des-spans-http-client.md)). Un
span `CLIENT` nommé par sa seule méthode (`POST`) devient
`{méthode} {chemin}`, par exemple `POST /api/reservations`. Le chemin vient
de `url.full`, sans hôte, requête ni fragment.

Un segment identifiant devient `{id}` : nombre, UUID, hexadécimal d'au moins
16 caractères, ou code en majuscules contenant un chiffre (`PASTA-500G`).
`GET /api/products/PASTA-500G` devient ainsi `GET /api/products/{id}`. Aucun
span n'est filtré : les sondes de santé et l'export Micrometer
(`POST /v1/metrics`) restent visibles.

Pour une nouvelle application, inventorier ses URL sortantes
(`url.original` des spans `span.type:external`). Si un identifiant échappe à
ces formes, par exemple un code en minuscules, étendre l'expression de
`transform/http-client-span-name` dans
`architecture/ansible/roles/otel_edge/templates/otel-edge.yaml.j2`, puis
appliquer `make otel-edge-vm-provision`.

## Application sans agent OTel

Le collecteur daemon `otel-kube-stack` ne collecte pas les fichiers des pods : une
application Java exporte ses logs par l'agent, ce qui évite les doublons.
Pour une application d'un autre namespace qui ne peut écrire que sur stdout,
ajouter au collecteur `daemon` de
`architecture/platform/helm/opentelemetry-kube-stack-values.yaml` :

- le montage `hostPath` `/var/log/pods` (lecture seule), par `volumes` et
  `volumeMounts` ;
- un receiver `filelog` limité à ce namespace, avec l'opérateur `container` :

  ```yaml
  filelog/kubernetes:
    include: [/var/log/pods/<namespace>_*/*/*.log]
    start_at: end
    include_file_path: true
    operators:
      - type: container
  ```

- un pipeline `logs/files` : `filelog/kubernetes` → `memory_limiter`,
  `batch` → `otlp/edge`, sans `resource/edge-source`.

L'opérateur `container` tire `k8s.namespace.name` et `k8s.pod.name` du chemin
du fichier ; l'Edge route alors ces logs selon le namespace. Ne jamais
inclure `h0tl-supermarche-app` ni `elastic-stack`. Appliquer ensuite
`make kubernetes-validate`, puis `make kubernetes-observability-deploy`.

## Vérifier le résultat

Après le déploiement de l'application, générer une requête métier puis utiliser
Discover avec les filtres suivants :

```kql
# Traces, erreurs et métriques APM en homologation
data_stream.namespace:"supermarche_homologation"
and service.name:"my-service"
and service.environment:"homologation"
and agent.name:"opentelemetry/java/opentelemetry-java-instrumentation"
```

```kql
# Logs applicatifs (data view sur logs-supermarche.otel-*)
data_stream.dataset:"supermarche.otel"
and data_stream.namespace:"homologation"
and service.name:"my-service"
and k8s.namespace.name:"h0tl-supermarche-app"
```

Le contrôle attendu est la présence de la même identité de service dans les
logs, métriques et traces, avec un `trace_id` sur les logs émis dans une
transaction. Le message est dans `body.text` et le niveau dans
`severity_text` ; le template OTel déclare les alias `message`, `log.level`
et `trace.id`, lus par la vue Logs des transactions APM.
`make trace-context-verify` contrôle cette corrélation et
`make observability-schema-verify` la forme des logs.
