# Ajouter une application Java observée

Ce guide décrit le raccordement à la chaîne d'observabilité architecture. Conserver le
socle applicatif commun et ajouter le patch d'instrumentation OTel décrit dans
`kubernetes/apps/supermarket-demo/default/otel-instrumentation.yaml`.

Ce guide décrit l'ajout d'une application Java Spring Boot à la chaîne
d'observabilité du lab. Le chemin des signaux est le suivant :

```text
application Java → agent Java OTel → Collecteur Edge → Kafka → Collector backend → APM Server / Elasticsearch
```

L'agent Java OTel produit les traces et les logs, Micrometer les métriques
applicatives. Les logs sont OTel natifs, sans format ECS (ADR-012).
Le Collecteur Edge reçoit l'OTLP, choisit le topic Kafka de la plateforme
du namespace et pose le dataset ; le Collector backend lit la plateforme et
l'environnement dans le nom du topic (ADR-015).

L'application `apps/demo-api` est l'exemple minimal de ce guide : un seul
service, sa plateforme `demo`, ses manifests sous `kubernetes/apps/demo-api/`.

## Préparer l'application

L'image doit contenir l'agent Java OpenTelemetry et démarrer la JVM avec
`-javaagent:/opt/opentelemetry-javaagent.jar` dans son `ENTRYPOINT`. C'est le
seul agent d'instrumentation : ne pas ajouter l'agent Java Elastic APM. Le
`Dockerfile` de `supermarket-demo` est la référence du dépôt ; chaque cible
d'image y fixe aussi `OTEL_SERVICE_NAME` pour une exécution hors Kubernetes.

Les logs passent par l'agent : son instrumentation Logback exporte chaque
log en OTLP, avec le `trace_id` et le `span_id` du span courant. Ne pas
configurer de format structuré (`logging.structured.format.console`) ni
d'appender d'export : stdout garde le texte par défaut de Spring Boot, lu par
`kubectl logs` mais pas collecté.

## Déclarer les variables Kubernetes

Le patch `otel-instrumentation.yaml` de l'overlay configure l'agent sans
l'attacher une seconde fois. Il monte un fichier `otel.properties` généré par
Kustomize (`otel.service.name`, `otel.service.version`, endpoint OTLP du
collecteur Edge, exporteurs) et ajoute :

```yaml
env:
  - name: OTEL_JAVAAGENT_CONFIGURATION_FILE
    value: /opt/opentelemetry/otel.properties
  - name: OTEL_EDGE_KEY
    valueFrom:
      secretKeyRef:
        name: otel-edge-client-keys
        key: otel-kubernetes-cluster
  - name: OTEL_EXPORTER_OTLP_HEADERS
    value: Authorization=Bearer $(OTEL_EDGE_KEY)
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: service.name=my-service,k8s.namespace.name=h0tl-supermarche-app
```

Le patch réel complète `OTEL_RESOURCE_ATTRIBUTES` avec le pod et le nœud,
fournis par la Downward API. Ces attributs forment la ressource des traces,
des métriques et des logs : `k8s.namespace.name` choisit la plateforme.
L'application ne déclare ni sa plateforme ni son environnement : le
collecteur Edge pose `k8s.cluster.name` et `deployment.environment.name`
depuis l'entrée du namespace dans `otel_edge_namespace_routes`
(`architecture/ansible/inventory/group_vars/otel_edge_nodes.yml`) et écrase
toute valeur envoyée. Un namespace inconnu de l'Edge est rejeté : un nouveau
namespace applicatif demande donc une nouvelle entrée.

Le fichier `otel.properties` active l'export des logs :

```properties
otel.logs.exporter=otlp
otel.instrumentation.logback-appender.experimental.capture-key-value-pair-attributes=true
otel.instrumentation.logback-appender.experimental-log-attributes=true
```

La deuxième ligne transforme les paires SLF4J `addKeyValue` en attributs du
log (`event.action`, `business.units_sold`) ; la troisième ajoute
`thread.name` et `thread.id`. La clé du collecteur Edge reste dans le secret
`otel-edge-client-keys`, créé par `make otel-edge-client-keys-apply` ; ne
jamais l'inscrire dans un manifest ou dans Git.

Ne pas ajouter `-javaagent` dans `JAVA_TOOL_OPTIONS` : l'agent serait attaché
deux fois, par l'`ENTRYPOINT` et par cette variable.

Une exception traitée par un `@ExceptionHandler` n'atteint pas
l'instrumentation servlet de l'agent et ne produit pas d'erreur APM, même si
la réponse est un 500. Pour qu'elle apparaisse dans l'UI APM, l'enregistrer
sur le span courant avec l'API OpenTelemetry, reliée à l'agent
(`io.opentelemetry:opentelemetry-api`, version gérée par le BOM de Spring
Boot) : `Span.current().recordException(e)` puis
`setStatus(StatusCode.ERROR, ...)`, comme le fait `demo-api`.

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
`supermarche` et pose le dataset `supermarche` sur les logs et les métriques
(ADR-015). Le collecteur backend lit dans le nom du topic la plateforme et
le namespace `homologation`. APM Server impose les datasets `apm`,
`apm.error` et `apm.*` : le namespace des signaux APM porte donc aussi la
plateforme, `<plateforme>_<environnement>` :

| Signal | Data stream |
| --- | --- |
| Traces | `traces-apm-supermarche_homologation` |
| Erreurs APM | `logs-apm.error-supermarche_homologation` |
| Métriques APM agrégées | `metrics-apm.{transaction,service_transaction,service_destination,service_summary}.1m-supermarche_homologation` |
| Métriques Micrometer et JVM | `metrics-supermarche.otel-homologation` |
| Logs applicatifs | `logs-supermarche.otel-homologation` |

Les traces gardent le dataset `apm` d'APM Server, lu par l'UI APM. Les
métriques et les logs reçoivent le suffixe `.otel` du mode de mapping OTel
(ADR-012). APM Server range ses métriques agrégées
dans `default` ; le pipeline Elasticsearch `apm-route-namespace` les déplace
dans le namespace des traces (`make apm-ingest-pipelines-deploy`). Les
intervalles `10m` et `60m`, s'ils sont produits, suivent la même règle. Les
métriques Kubernetes des pods (`kubeletstats`, `k8s_cluster`) gardent le
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

   Ses logs et métriques iront dans `logs-caisse.otel-homologation` et
   `metrics-caisse.otel-homologation`, ses signaux APM dans
   `traces-apm-caisse_homologation`, tous avec `platform.id` = `caisse`. Le
   rôle `otel_edge` refuse un namespace dupliqué, un format invalide ou une
   plateforme absente de `otel_platforms`.
3. Valider avec `make otel-config-validate`, créer les topics avec
   `make otel-backend-vm-provision`, puis appliquer la table avec
   `make otel-edge-vm-provision`.

Les attributs `data_stream.dataset`, `data_stream.namespace`,
`apm.route.namespace` et `platform.id` posés par l'application sont supprimés
par l'Edge. Sans entrée dédiée, les signaux de l'application sont rejetés par
l'Edge et comptés par `make otel-routing-verify`.

Les traces et métriques APM portent `agent.name` égal à
`opentelemetry/java/opentelemetry-java-instrumentation`. Les logs portent la
ressource de l'agent sous `resource.attributes` (`service.name`,
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

Le DaemonSet `otel-kubernetes` ne collecte plus les fichiers des pods : une
application Java exporte ses logs par l'agent, ce qui évite les doublons.
Pour une application d'un autre namespace qui ne peut écrire que sur stdout,
rétablir dans `architecture/platform/kubernetes/base/observability/otel-kafka.yaml` :

- le montage `hostPath` `/var/log/pods` (lecture seule) du DaemonSet ;
- un receiver `filelog` limité à ce namespace, avec l'opérateur `container` :

  ```yaml
  filelog/kubernetes:
    include: [/var/log/pods/<namespace>_*/*/*.log]
    start_at: end
    include_file_path: true
    operators:
      - type: container
  ```

- un pipeline `logs` : `filelog/kubernetes` → `memory_limiter`,
  `resource/environment`, `resource/edge-source`, `batch` → `otlp/edge`.

L'opérateur `container` tire `k8s.namespace.name` et `k8s.pod.name` du chemin
du fichier ; l'Edge route alors ces logs selon le namespace, ou vers
`otel-logs-homologation`. Ne jamais
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
