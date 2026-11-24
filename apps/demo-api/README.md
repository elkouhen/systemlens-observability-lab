# demo-api : hello world instrumenté par l'agent Java OTel

API Spring Boot minimale, sans base de données ni Kafka, avec un point
d'entrée par signal. Elle forme à elle seule la plateforme `demo` du lab (namespace
`h0tl-demo-app`, ADR-015). Le seul code d'instrumentation est le compteur
applicatif `demo_api.calls` (voir plus bas) : l'agent Java OpenTelemetry, injecté par l'opérateur de `opentelemetry-kube-stack`
(ADR-019), produit les trois signaux, qui suivent le chemin agent →
collecteur daemon `otel-kube-stack` → collecteur Edge → Kafka
`otel-<signal>-demo-homologation` → collecteur backend → Elasticsearch, en
OTel natif sans conversion ECS (ADR-018).

| Point d'entrée | Signaux |
| --- | --- |
| `GET /api/hello?name=` | Une transaction APM, un log INFO corrélé (`trace_id`, `span_id`) |
| `GET /api/fail?reason=` | Un log ERROR, une transaction en échec HTTP 500 et une erreur APM : l'exception n'est pas traitée et l'instrumentation servlet de l'agent l'enregistre |

En continu, sans trafic, l'agent exporte toutes les 15 secondes les
métriques runtime JVM de la sémantique OTel, celles de l'onglet *Metrics*
de l'UI APM pour un service Java OTel :

| Métrique | Contenu |
| --- | --- |
| `jvm.memory.used`, `jvm.memory.committed`, `jvm.memory.limit`, `jvm.memory.used_after_last_gc` | Mémoire par `jvm.memory.type` (heap, non_heap) et `jvm.memory.pool.name` |
| `jvm.gc.duration` | Histogramme des pauses GC par `jvm.gc.name` et `jvm.gc.action` |
| `jvm.thread.count` | Threads par `jvm.thread.state` et `jvm.thread.daemon` |
| `jvm.class.count`, `jvm.class.loaded`, `jvm.class.unloaded` | Classes chargées |
| `jvm.cpu.recent_utilization`, `jvm.cpu.time`, `jvm.cpu.count` | CPU du processus JVM |
| `jvm.system.cpu.utilization`, `jvm.buffer.memory.used` | Expérimentales, activées par `OTEL_INSTRUMENTATION_RUNTIME_TELEMETRY_EMIT_EXPERIMENTAL_TELEMETRY` |
| `http.server.request.duration` | Histogramme des requêtes HTTP entrantes |

## Métrique applicative `demo_api.calls`

Le filtre `CallMetricsFilter` compte chaque appel `/api/*` avec l'API
OpenTelemetry (`opentelemetry-api`, sans SDK embarqué) : l'agent injecté
raccorde cette API à son SDK et exporte le compteur toutes les 15 secondes
avec les métriques JVM, vers le même data stream. Sans agent (tests), le
compteur est no-op.

| Champ | Contenu |
| --- | --- |
| `metrics.demo_api.calls` | Compteur cumulatif (unité `{call}`) depuis le démarrage du pod |
| `attributes.outcome` | `ok` : statut HTTP < 400 sans exception ; `ko` : statut ≥ 400 ou exception non traitée |
| `attributes.http.route` | Route Spring (`/api/hello`, `/api/fail`) ; un chemin `/api/*` inconnu (404) remonte en `/**`, le handler de ressources statiques |

Le compteur étant cumulatif, le nombre d'appels sur une période se lit dans
Kibana (Lens, *Counter rate* ou différence max − min par `attributes.outcome`)
et non par une somme des documents.

La configuration de l'agent est commune aux applications Java : CR
`Instrumentation` de `architecture/platform/helm/opentelemetry-kube-stack-values.yaml`
(`OTEL_METRICS_EXPORTER=otlp`, `OTEL_METRIC_EXPORT_INTERVAL=15000`). Le patch
`kubernetes/apps/demo-api/default/otel-instrumentation.yaml` n'ajoute que
les annotations d'injection et de `service.version`. Les trois signaux
partent en OTLP HTTP sur le port `4318` du Service
`otel-kube-stack-daemon-collector`. Les sondes Kubernetes sont TCP pour ne
pas créer de transactions.

## Data streams alimentés

| Signal | Data stream | Filtre |
| --- | --- | --- |
| Logs et erreurs | `logs-demo.otel-homologation` ; une erreur est un événement `exception` avec `attributes.processor.event: error` | `platform.id: demo`, `service.name: demo-api` |
| Métriques JVM et HTTP de l'agent | `metrics-demo.otel-homologation`, champs `metrics.jvm.*` | `service.name: demo-api` |
| Métrique applicative | `metrics-demo.otel-homologation`, champ `metrics.demo_api.calls` | `service.name: demo-api` |
| Traces | `traces-demo.otel-homologation` | `platform.id: demo` |
| Métriques APM agrégées | `metrics-{transaction,service_transaction,service_destination,service_summary}.1m.otel-homologation` | `service.name: demo-api` |

## Prérequis

- La plateforme `demo` déclarée dans `otel_platforms`
  (`architecture/ansible/inventory/group_vars/otel_backend_nodes.yml`) et le
  namespace `h0tl-demo-app` dans `otel_edge_namespace_routes`
  (`architecture/ansible/inventory/group_vars/otel_edge_nodes.yml`), puis
  `make otel-backend-vm-provision` (topics) et `make otel-edge-vm-provision`
  (table de routage). Sans cette déclaration, l'Edge rejette les signaux.
- Docker pour construire l'image, le cluster k3s et la stack
  `opentelemetry-kube-stack` (`make otel-kube-stack-deploy`, incluse dans
  `make kubernetes-observability-deploy`).

## Commandes

Depuis `architecture/` :

```bash
make demo-api-test                # test Maven (Java 21)
make demo-api-build               # image demo-api:1.2.0 (agent injecté par l'opérateur)
make demo-api-import              # import de l'image dans k3s
make demo-api-deploy              # applique kubernetes/apps/demo-api/default et attend le rollout
                                  # (build, import et déploiement sont inclus dans make deploy)
make demo-api-call                # GET /api/hello?name=lab depuis le cluster
make demo-api-call DEMO_API_PATH='/api/fail?reason=demo'
make demo-api-jvm-metrics-verify  # métriques JVM des 5 dernières minutes
make demo-api-app-metrics-verify  # appels ok/ko cumulés (demo_api.calls), 5 dernières minutes
make demo-api-logs-follow
```

`DEMO_API_IMAGE_TAG` fixe le tag de l'image (`1.2.0` par défaut) ; un tag est
immuable, en choisir un nouveau à chaque image, en cohérence avec
`kubernetes/apps/demo-api/default/kustomization.yaml`.

## Vérification

```bash
make demo-api-jvm-metrics-verify
make demo-api-call                                    # un appel ok
make demo-api-call DEMO_API_PATH='/api/fail?reason=demo'  # un appel ko
make demo-api-app-metrics-verify                      # après 15 s d'export
make otel-routing-verify
```

`demo-api-app-metrics-verify` affiche, par `outcome` et `http.route`, la
valeur cumulée la plus récente de `demo_api.calls` (au moins `ok /api/hello`
et `ko /api/fail` après les deux appels) ; il échoue sans document.

`demo-api-jvm-metrics-verify` affiche `OK` pour `jvm.memory.used`,
`jvm.memory.limit`, `jvm.gc.duration`, `jvm.thread.count`, `jvm.class.count`
et `jvm.cpu.recent_utilization`. Dans Kibana : l'UI APM liste `demo-api` en
`homologation`, ses transactions `GET /api/hello` et `GET /api/fail`,
l'erreur `DemoFailureException` et l'onglet *Metrics* (tableau JVM, mémoire
heap et non-heap, GC, threads, CPU) ; Discover sur `metrics-demo.otel-*` avec
`service.name: demo-api` montre les champs `metrics.jvm.*`.

## Structure

```text
apps/demo-api/
  pom.xml                       Spring Boot 3.4.5, Java 21, starter web et opentelemetry-api
  Dockerfile                    build Maven, agent Java OTel attaché par l'ENTRYPOINT
  src/main/java/io/systemlens/demo/
    DemoApiApplication.java     démarrage
    HelloController.java        GET /api/hello, GET /api/fail
    CallMetricsFilter.java      compteur demo_api.calls (outcome ok/ko, http.route)
kubernetes/apps/demo-api/
  base/                         namespace h0tl-demo-app, Deployment, Service
  default/                      overlay : patch d'annotations d'injection de l'agent
```

Le raccordement suit [`apps/ADDING_APPLICATION.md`](../ADDING_APPLICATION.md).
