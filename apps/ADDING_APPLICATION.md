# Ajouter une application Java observée

Ce guide décrit le raccordement à la chaîne d'observabilité architecture. Conserver le
socle applicatif commun et ajouter le patch d'instrumentation OTel décrit dans
`kubernetes/apps/supermarket-demo/default/otel-instrumentation.yaml`.

Ce guide décrit l'ajout d'une application Java Spring Boot à la chaîne
d'observabilité du lab. Le chemin des signaux est le suivant :

```text
application Java → agent Java OTel → Gateway EDOT → Kafka → Elasticsearch
logs stdout ECS → EDOT DaemonSet → Kafka → Elasticsearch
```

L'agent Java OTel produit les traces applicatives. Le Gateway et le Collector
backend centralisent ensuite la normalisation et le routage des signaux.

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

La valeur source a le format :

```text
<type><ptf_sur_3_caracteres>-<namespace>
```

Le namespace Kubernetes porte cette valeur ; le patch OTel la transmet à
l'agent dans l'attribut de ressource `k8s.namespace.name`.
Exemple : `h0tl-supermarche-app` signifie :

| Partie | Valeur | Rôle |
| --- | --- | --- |
| Type | `h` | Environnement Elastic `homologation` |
| PTF | `0tl` | Ajouté dans `labels.ptf` |
| Namespace | `supermarche-app` | Ajouté dans `labels.namespace` |

Les types acceptés sont `r` (recette), `p` (production), `h` (homologation),
`i` (integration) et `d` (developpement). Logstash normalise ensuite
`service.environment` avec ce nom canonique. Pour les logs, il utilise
`kubernetes.namespace`, y compris pour l'APM.

Les métriques APM dont `agent.name` vaut `java` et qui portent les métadonnées
Kubernetes sont mutualisées par plateforme et routées vers :

```text
metrics-apm.app.<code_plateforme>-<environnement-elastic>
```

Les traces suivent la même règle de dataset mutualisé par plateforme. Les
traces et erreurs portent le `service.environment` normalisé et les labels
d'enrichissement. Les logs
applicatifs Kubernetes dont la valeur source respecte la convention sont
regroupés dans le même namespace Elastic, par exemple :

```text
logs-kube-0tl-homologation
```

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
# Métriques Java en homologation
data_stream.dataset:"apm.app.0tl"
and data_stream.namespace:"homologation"
and agent.name:"java"
```

```kql
# Logs applicatifs normalisés
data_stream.dataset:"kube-0tl"
and service.environment:"homologation"
and labels.ptf:"0tl"
and labels.namespace:"supermarche-app"
```

Le contrôle attendu est la présence de la même identité de service dans les
logs, métriques et traces, avec un `trace.id` sur les logs émis dans une
transaction. L'agent OTel place `trace_id` et `span_id` dans le MDC Logback ;
le formateur ECS de Spring Boot les écrit dans le JSON et le collecteur backend
les recopie en `trace.id` et `span.id`. `make trace-context-verify` contrôle
cette corrélation.
