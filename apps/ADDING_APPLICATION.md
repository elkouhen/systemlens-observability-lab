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
Le Collecteur Edge reçoit l'OTLP ; le Collector backend centralise ensuite la
normalisation et le routage des signaux.

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
    value: deployment.environment=homologation,service.name=my-service,k8s.namespace.name=h0tl-supermarche-app
```

Le patch réel complète `OTEL_RESOURCE_ATTRIBUTES` avec le pod et le nœud,
fournis par la Downward API. Ces attributs forment la ressource des traces et
des logs : `k8s.namespace.name` choisit la route Edge des logs.

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

## Convention d'environnement

Le namespace Kubernetes suit le format
`<type><ptf_sur_3_caracteres>-<namespace>`, par exemple
`h0tl-supermarche-app` : `h` pour homologation, `0tl` pour la plateforme,
`supermarche-app` pour le périmètre applicatif.

Aucun traitement ne découpe cette valeur. L'environnement Elastic vient de
l'attribut de ressource `deployment.environment` du patch OTel, indexé en
`service.environment` sur les traces et les métriques APM. Le namespace est
transmis par `k8s.namespace.name` et indexé en `kubernetes.namespace`.

## Data streams alimentés

Le dataset nomme l'application, le namespace nomme l'environnement (ADR-010).
Le collecteur Edge publie les signaux dont la ressource porte
`k8s.namespace.name` = `h0tl-supermarche-app` dans les topics
`otel-<signal>-supermarche` (ADR-009) et pose le dataset `supermarche` sur
leurs logs et métriques. Le collecteur backend pose le namespace depuis
`deployment.environment` (`homologation`). APM Server impose les datasets
`apm`, `apm.error` et `apm.*` : le namespace des signaux APM porte donc aussi
l'application, `<dataset>_<environnement>` (ADR-010, note du 2026-11-02) :

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

### Donner son propre dataset à une nouvelle application

1. Ajouter une entrée à `otel_edge_application_routes` dans
   `architecture/ansible/inventory/group_vars/otel_edge_nodes.yml` :
   `kubernetes_namespace` est le namespace Kubernetes de l'application,
   `kafka_topic_suffix` le suffixe de ses topics et `data_stream_dataset` le
   dataset de ses logs et métriques (`[a-z0-9_]`). Ce dataset préfixe aussi le
   namespace de ses signaux APM : `traces-apm-<dataset>_<environnement>`.
2. Ajouter les trois topics `otel-{traces,metrics,logs}-<suffixe>` à la
   boucle du job `otel-telemetry-topics` dans
   `architecture/platform/kubernetes/base/observability/otel-kafka.yaml`.
3. Déclarer `deployment.environment` dans `OTEL_RESOURCE_ATTRIBUTES` : il
   fixe le namespace (`default` à défaut).
4. Appliquer `make kubernetes-observability-deploy` (création des topics),
   puis `make otel-edge-vm-provision`.

Sans entrée dédiée, les signaux de l'application partent dans les topics de
base, avec le dataset de leur source et le namespace `default`.

Les traces et métriques APM portent `agent.name` égal à
`opentelemetry/java/opentelemetry-java-instrumentation`. Les logs portent la
ressource de l'agent sous `resource.attributes` (`service.name`,
`service.version`, `deployment.environment`, `k8s.*`, `telemetry.distro.*`).

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
`otel-logs-k8s`. Ne jamais
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
