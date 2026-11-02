# Ajouter une application Java observée

Ce guide décrit le raccordement à la chaîne d'observabilité architecture. Conserver le
socle applicatif commun et ajouter le patch d'instrumentation OTel décrit dans
`kubernetes/apps/supermarket-demo/default/otel-instrumentation.yaml`.

Ce guide décrit l'ajout d'une application Java Spring Boot à la chaîne
d'observabilité du lab. Le chemin des signaux est le suivant :

```text
application Java → agent Java OTel → Collecteur Edge → Kafka → Collector backend → Elasticsearch
logs stdout ECS → DaemonSet OTel → Collecteur Edge → Kafka → Collector backend → Elasticsearch
```

L'agent Java OTel produit les traces et Micrometer les métriques applicatives.
Le Collecteur Edge reçoit l'OTLP ; le Collector backend centralise ensuite la
normalisation et le routage des signaux.

## Préparer l'application

L'image doit contenir l'agent Java OpenTelemetry et démarrer la JVM avec
`-javaagent:/opt/opentelemetry-javaagent.jar` dans son `ENTRYPOINT`. C'est le
seul agent d'instrumentation : ne pas ajouter l'agent Java Elastic APM. Le
`Dockerfile` de `supermarket-demo` est la référence du dépôt ; chaque cible
d'image y fixe aussi `OTEL_SERVICE_NAME` pour une exécution hors Kubernetes.

L'application doit écrire des logs JSON ECS sur stdout, avec Spring Boot :

```yaml
logging:
  structured:
    format:
      console: ecs
```

Ne pas expédier les logs directement depuis l'application : le DaemonSet OTel
Kubernetes les collecte sur le nœud.

## Déclarer les variables Kubernetes

Le Deployment de base définit l'identité ECS des logs :

```yaml
env:
  - name: LOGGING_STRUCTURED_FORMAT_CONSOLE
    value: ecs
  - name: LOGGING_STRUCTURED_ECS_SERVICE_NAME
    value: my-service
  - name: LOGGING_STRUCTURED_ECS_SERVICE_VERSION
    value: "1.0.0"
```

Le patch `otel-instrumentation.yaml` de l'overlay configure l'agent sans
l'attacher une seconde fois. Il monte un fichier `otel.properties` généré par
Kustomize (`otel.service.name`, `otel.service.version`, endpoint OTLP du
collecteur Edge) et ajoute :

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
fournis par la Downward API. La clé du collecteur Edge reste dans le secret
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

Le collecteur backend écrit en mode de mapping ECS. Le namespace des data
streams dérive du suffixe du topic Kafka (ADR-007). Le collecteur Edge publie
les signaux dont la ressource porte `k8s.namespace.name` =
`h0tl-supermarche-app` dans les topics `otel-<signal>-supermarche` (ADR-009) :

| Signal | Data stream |
| --- | --- |
| Traces | `traces-apm-supermarche` |
| Erreurs APM | `logs-apm.error-supermarche` |
| Métriques Micrometer et JVM | `metrics-generic.otel-supermarche` |
| Logs stdout | `logs-filelogreceiver-supermarche` |
| Métriques APM agrégées | `metrics-apm.transaction.1m-default`, `metrics-apm.service_destination.1m-default` et voisins |

APM Server calcule les métriques APM agrégées sans reprendre le namespace des
traces : elles restent dans `default`. Les métriques Kubernetes des pods
(`kubeletstats`, `k8s_cluster`) vont dans le namespace `k8s`. Les données
antérieures au 2026-11-02 sont dans les data streams `*-default`.

### Donner son propre namespace à une nouvelle application

1. Ajouter une entrée à `otel_edge_application_routes` dans
   `architecture/ansible/inventory/group_vars/otel_edge_nodes.yml` :
   `kubernetes_namespace` est le namespace Kubernetes de l'application,
   `data_stream_namespace` le namespace de data stream (`[a-z0-9_]`).
2. Ajouter les trois topics `otel-{traces,metrics,logs}-<namespace>` à la
   boucle du job `otel-telemetry-topics` dans
   `architecture/platform/kubernetes/base/observability/otel-kafka.yaml`.
3. Appliquer `make kubernetes-observability-deploy` (création des topics),
   puis `make otel-edge-vm-provision`.

Sans entrée dédiée, les signaux de l'application partent dans les topics de
base et le namespace `default`.

Les traces et métriques APM portent `agent.name` égal à
`opentelemetry/java/opentelemetry-java-instrumentation`. Les logs ne portent
ni `agent.name` ni `service.environment` : le formateur ECS n'écrit que
`service.name`, `service.version` et `service.node.name`.

## Raccorder la collecte des logs

L'Agent Kubernetes actuel cible les fichiers des pods du namespace
`h0tl-supermarche-app`. Pour une application dans un autre namespace, élargir de
façon explicite le chemin `paths` dans
`architecture/platform/kubernetes/base/observability/otel-kafka.yaml`, ou ajouter
un stream dédié. Appliquer ensuite `make kubernetes-validate`, puis
`make otel-validation`.

## Vérifier le résultat

Après le déploiement de l'application, générer une requête métier puis utiliser
Discover avec les filtres suivants :

```kql
# Traces et métriques APM en homologation
service.name:"my-service"
and service.environment:"homologation"
and agent.name:"opentelemetry/java/opentelemetry-java-instrumentation"
```

```kql
# Logs applicatifs
data_stream.dataset:"filelogreceiver"
and data_stream.namespace:"supermarche"
and service.name:"my-service"
and kubernetes.namespace:"h0tl-supermarche-app"
```

Le contrôle attendu est la présence de la même identité de service dans les
logs, métriques et traces, avec un `trace.id` sur les logs émis dans une
transaction. L'agent OTel place `trace_id` et `span_id` dans le MDC Logback ;
le formateur ECS de Spring Boot les écrit dans le JSON et le collecteur backend
les recopie en `trace.id` et `span.id`. `make trace-context-verify` contrôle
cette corrélation.
