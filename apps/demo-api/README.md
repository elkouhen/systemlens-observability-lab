# demo-api : API de démonstration de la remontée de signaux

API Spring Boot minimale, sans base de données ni Kafka, dont chaque point
d'entrée produit un type de signal. Elle forme à elle seule la plateforme
`demo` du lab (namespace `h0tl-demo-app`, ADR-015) : ses signaux suivent le
chemin complet, agent Java OTel et Micrometer → collecteur Edge → Kafka
`otel-<signal>-demo-homologation` → collecteur backend → APM Server et
Elasticsearch.

| Point d'entrée | Signal démontré |
| --- | --- |
| `GET /api/hello?name=` | Une transaction, un log INFO avec les attributs `demo.name` et `event.action`, le compteur `demo.requests{endpoint=hello}` |
| `GET /api/work?ms=` | Un span dont la durée varie, le timer `demo.work.duration` avec histogramme de percentiles |
| `GET /api/chain?name=` | Un appel HTTP sortant vers sa propre API : trace distribuée sur deux transactions, span client renommé `GET /api/hello` (ADR-011) |
| `GET /api/fail?reason=` | Un log ERROR, une transaction en échec HTTP 500 et une erreur APM : l'exception, traitée par un `@ExceptionHandler`, est enregistrée sur le span courant via l'API OpenTelemetry |
| `GET /api/health` | Sonde des probes Kubernetes |

Un battement de cœur toutes les 30 secondes émet un log et la jauge
`demo.heartbeat.count`, pour que les data streams restent alimentés sans
trafic.

## Data streams alimentés

| Signal | Data stream | Filtre |
| --- | --- | --- |
| Logs | `logs-demo.otel-homologation` | `platform.id: demo`, `service.name: demo-api` |
| Métriques Micrometer et JVM | `metrics-demo.otel-homologation` | idem |
| Traces et erreurs | `traces-apm-demo_homologation`, `logs-apm.error-demo_homologation` | `service.environment: homologation` |
| Métriques APM agrégées | `metrics-apm.*.1m-demo_homologation` | rangées par le pipeline `apm-route-namespace` |

## Prérequis

- La plateforme `demo` déclarée dans `otel_platforms`
  (`architecture/ansible/inventory/group_vars/otel_backend_nodes.yml`) et le
  namespace `h0tl-demo-app` dans `otel_edge_namespace_routes`
  (`architecture/ansible/inventory/group_vars/otel_edge_nodes.yml`), puis
  `make otel-backend-vm-provision` (topics) et `make otel-edge-vm-provision`
  (table de routage). Sans cette déclaration, l'Edge rejette les signaux.
- Docker pour construire l'image, le cluster k3s et le Secret
  `otel-edge-client-keys` (`make otel-edge-client-keys-apply`, inclus dans
  `make demo-api-deploy`).

## Commandes

Depuis `architecture/` :

```bash
make demo-api-test        # tests Maven (Java 21)
make demo-api-build       # image demo-api:1.0.0 avec l'agent Java OTel
make demo-api-import      # import de l'image dans k3s
make demo-api-deploy      # applique kubernetes/apps/demo-api/default et attend le rollout
make demo-api-scenario    # hello, work, chain puis fail
make demo-api-call DEMO_API_PATH='/api/work?ms=500'
make demo-api-logs-follow
```

`DEMO_API_IMAGE_TAG` fixe le tag de l'image (`1.0.1` par défaut) ; un tag est
immuable, en choisir un nouveau à chaque image, en cohérence avec
`kubernetes/apps/demo-api/default/kustomization.yaml`.

## Vérification

```bash
make otel-routing-verify
```

Le contrôle attend des logs et des métriques portant `platform.id: demo`.
Dans Kibana : l'UI APM liste `demo-api` en `homologation` avec ses quatre
transactions et l'erreur de `/api/fail` ; Discover sur `logs-*` avec
`service.name: demo-api` montre les logs, `trace_id` renseigné pour ceux
émis dans une requête ; `metrics-*` avec `data_stream.dataset: demo.otel`
montre `demo.requests`, `demo.work.duration` et `demo.heartbeat.count`.

## Structure

```text
apps/demo-api/
  pom.xml                       Spring Boot 3.4.5, Java 21, Micrometer OTLP
  Dockerfile                    build Maven, agent Java OTel attaché par l'ENTRYPOINT
  src/main/java/io/systemlens/demo/
    DemoApiApplication.java     démarrage, RestTemplate
    SignalController.java       points d'entrée HTTP
    SignalService.java          logs, métriques, appel sortant, erreur contrôlée
    HeartbeatScheduler.java     battement de cœur
kubernetes/apps/demo-api/
  base/                         namespace h0tl-demo-app, Deployment, Service
  default/                      overlay : otel.properties, patch d'instrumentation
```

Le raccordement suit [`apps/ADDING_APPLICATION.md`](../ADDING_APPLICATION.md).
