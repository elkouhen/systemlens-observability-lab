# ADR-019 : collecte Kubernetes et instrumentation Java par opentelemetry-kube-stack

## Statut

Accepted

Remplace la décision d'[ADR-008](ADR-008-agent-java-opentelemetry-seul.md)
sur l'attachement de l'agent par l'`ENTRYPOINT` (l'agent Java OpenTelemetry
reste le seul agent). Conserve [ADR-014](ADR-014-retour-collecteurs-edot.md)
(collecteurs EDOT) et le routage Edge d'[ADR-015](ADR-015-topics-par-plateforme-et-configuration-edge.md).

## Date

2026-11-19

## Contexte

Les collecteurs Kubernetes (`otel-kubernetes`, `otel-kubernetes-cluster`)
étaient décrits à la main dans `otel-kafka.yaml`, et chaque application :

- embarquait l'agent Java dans son image et l'attachait par l'`ENTRYPOINT` ;
- montait un `otel.properties` par service ;
- recopiait ses attributs Kubernetes dans `OTEL_RESOURCE_ATTRIBUTES`, dont
  `k8s.namespace.name`, qui choisit la plateforme sur l'Edge ;
- lisait la clé Bearer d'un collecteur pour exporter directement vers l'Edge.

Une erreur de recopie du namespace faisait rejeter les signaux par l'Edge, et
la version de l'agent était liée au tag des images.

## Décision

Le chart `open-telemetry/opentelemetry-kube-stack` (version
`OTEL_KUBE_STACK_CHART_VERSION` du `Makefile`, release `otel-kube-stack`,
namespace `elastic-stack`) déploie, depuis
`platform/helm/opentelemetry-kube-stack-values.yaml` :

| Objet | Rôle |
| --- | --- |
| Opérateur OpenTelemetry | Gère les collecteurs et injecte l'agent Java ; certificat du webhook généré par le chart (pas de cert-manager) |
| `OpenTelemetryCollector` `otel-kube-stack-daemon` (DaemonSet) | `kubeletstats` et télémétrie interne → Edge avec le marqueur `otel.edge.source=kubernetes` ; OTLP des applications → `k8sattributes` → Edge sans marqueur |
| `OpenTelemetryCollector` `otel-kube-stack-cluster` (Deployment) | `k8s_cluster` → Edge avec le marqueur |
| `Instrumentation` `otel-kube-stack` | Agent Java `autoinstrumentation-java:2.28.1`, exporteurs, logs Logback, endpoint du daemon |

- Les collecteurs utilisent l'image EDOT `elastic-otel-collector:9.5.4`
  (ADR-014). Les presets du chart sont désactivés : la configuration reste
  écrite en entier dans les values, avec les noms courants des composants
  (`kubelet_stats`, `k8s_attributes`, `otlp_grpc`), sans alias déprécié.
- Une application s'instrumente par deux annotations de pod :
  `instrumentation.opentelemetry.io/inject-java: elastic-stack/otel-kube-stack`
  et `resource.opentelemetry.io/service.version`. Son image ne contient plus
  d'agent ; l'`ENTRYPOINT` lance seulement `java -jar`.
- L'agent et Micrometer exportent vers le Service
  `otel-kube-stack-daemon-collector:4318`. Le daemon pose `k8s.namespace.name`,
  `k8s.pod.*`, `k8s.deployment.name`, `host.name` (nœud) et
  `service.node.name` (pod), puis transmet à l'Edge avec sa propre clé.
- Les pipelines applicatifs du daemon ne posent pas le marqueur
  `otel.edge.source` : l'Edge les route par `k8s.namespace.name` vers la
  plateforme du namespace, sans changement de ses règles.
- Les pods applicatifs ne reçoivent plus de clé Edge ; le Secret
  `otel-edge-client-keys` n'existe plus que dans `elastic-stack`.

## Alternatives considérées

- **Apps → Edge en direct avec l'injection seule** : plus petit, mais garde la
  clé Edge dans les pods et les attributs `k8s.*` recopiés à la main.
- **Image de collecteur amont `opentelemetry-collector-k8s`** : défaut du
  chart, mais revient sur ADR-014 pour la seule partie Kubernetes.
- **Presets du chart** (`kubeletMetrics`, `kubernetesAttributes`,
  `clusterMetrics`) : ils ajoutent leurs receivers et processors à tous les
  pipelines, ce qui mélangerait les signaux marqués et non marqués.

## Conséquences

- Ajouter une application Java : un patch d'annotations et, si elle utilise
  Micrometer, l'URL du daemon (voir `apps/ADDING_APPLICATION.md`).
- La version de l'agent Java change dans les values, sans reconstruire les
  images ; un redémarrage des pods applique la nouvelle Instrumentation.
- Si le webhook de l'opérateur ne répond pas, un pod démarre sans agent
  (`failurePolicy: Ignore`). `make otel-instrumentation-verify` contrôle
  l'injection effective.
- Le certificat du webhook est généré par le chart, valable 365 jours, et
  conservé d'un `helm upgrade` à l'autre. `make otel-operator-cert-renew` le
  régénère ; `make otel-operator-cert-status` affiche son expiration.
- Si le daemon d'un nœud est indisponible, les signaux applicatifs de ce
  nœud ne partent plus vers l'Edge.
- Une image lancée hors Kubernetes n'est pas instrumentée ; seul Micrometer
  exporte, si on le configure.

## Mise en œuvre et vérification

```bash
make kubernetes-validate             # Kustomize + helm template
make kubernetes-observability-deploy # opérateur, collecteurs, Instrumentation
make apps-build images-import apps-deploy
make demo-api-build demo-api-import demo-api-deploy
make otel-instrumentation-verify     # init container injecté, endpoint du daemon
make otel-routing-verify             # aucun rejet par filter/unrouted
make trace-context-verify
make dashboards-verify
```
