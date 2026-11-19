# Plateforme d’observabilité

Ce répertoire contient les composants transverses déployés dans Kubernetes et
les objets Elastic associés à l’architecture active.

## Périmètre

- `kubernetes/` : namespace, services Elastic, ingress et Job des topics
  métier Kafka ;
- `elk/` : dashboards, policies, scripts de bootstrap et contrôles Kibana ;
- `helm/` : valeurs du chart `opentelemetry-kube-stack` (opérateur OTel,
  collecteurs Kubernetes, Instrumentation Java, ADR-019) et du déploiement
  ECK lorsqu’il est utilisé.

Les agents EDOT des VM ne sont pas configurés ici. Leur collecte est décrite
dans `architecture/ansible/roles/elastic_agent/` et leur supervision est
activée par OpAMP via Fleet. Les package policies Fleet ne pilotent pas la
collecte des agents standalone.

## Validation

Depuis la racine du dépôt :

```bash
make kubernetes-validate
make ansible-validate
```

## Collecteurs Kubernetes et instrumentation Java (opentelemetry-kube-stack)

Le chart `open-telemetry/opentelemetry-kube-stack` (release `otel-kube-stack`,
namespace `elastic-stack`, version `OTEL_KUBE_STACK_CHART_VERSION` du
`Makefile`) est configuré par `helm/opentelemetry-kube-stack-values.yaml`.
Il installe l'opérateur OpenTelemetry (certificat du webhook généré par le
chart, sans cert-manager) et trois ressources gérées par l'opérateur :

| Ressource | Objet Kubernetes créé | Rôle |
| --- | --- | --- |
| `OpenTelemetryCollector/otel-kube-stack-daemon` | DaemonSet et Service `otel-kube-stack-daemon-collector` | `kubeletstats` + télémétrie interne, marqués `otel.edge.source=kubernetes` ; OTLP des pods (4317/4318) enrichi par `k8sattributes`, sans marqueur |
| `OpenTelemetryCollector/otel-kube-stack-cluster` | Deployment `otel-kube-stack-cluster-collector` | `k8s_cluster`, marqué `otel.edge.source=kubernetes` |
| `Instrumentation/otel-kube-stack` | Webhook d'injection | Agent Java `autoinstrumentation-java:2.28.1`, export vers le daemon |

Les collecteurs utilisent l'image EDOT `elastic-otel-collector:9.5.4`
(ADR-014) ; les presets du chart sont désactivés et la configuration est
écrite en entier dans les values. Le receiver `kubeletstats` utilise l'IP du
nœud injectée par la Downward API (`OTEL_K8S_NODE_IP`, posée par le chart) :
le nom Kubernetes du nœud n'est pas nécessairement résolvable depuis le pod.

```text
kubelet → daemon (marqueur) → OTLP gRPC → otel-edge-01 → Kafka otel-metrics-k3s-homologation
pod annoté inject-java → agent + Micrometer → daemon (k8sattributes, sans marqueur)
  → otel-edge-01 → Kafka otel-<signal>-<plateforme du namespace>-homologation
```

Commandes, depuis `architecture/` :

```bash
make kubernetes-validate              # Kustomize + helm template du chart
make kubernetes-observability-deploy  # Job des topics, puis make otel-kube-stack-deploy
make otel-instrumentation-verify      # agent injecté dans les pods applicatifs
```

`make otel-kube-stack-deploy` supprime d'abord les anciens objets Kustomize
(`otel-kubernetes`, `otel-kubernetes-cluster`, ConfigMaps `*-otel-config`,
clés Edge des namespaces applicatifs) par `make otel-kubernetes-legacy-remove`,
puis exécute `helm upgrade --install --wait` et attend le rollout des deux
collecteurs. Résultat attendu : `kubectl -n elastic-stack get
opentelemetrycollector` affiche `otel-kube-stack-daemon` et
`otel-kube-stack-cluster`, et `make otel-instrumentation-verify` affiche `OK`
pour les quatre services Java. Un pod créé avant l'opérateur doit être
redémarré pour recevoir l'agent.

Le certificat du webhook de l'opérateur est généré par le chart pour
365 jours et conservé à chaque `helm upgrade` (`autoGenerateCert.recreate:
false`). `make otel-operator-cert-status` affiche sa date d'expiration ;
avant cette date, `make otel-operator-cert-renew` le régénère, redémarre
l'opérateur et affiche la nouvelle expiration. Un certificat expiré ne
bloque pas les déploiements (`failurePolicy: Ignore`) mais les pods
démarrent alors sans agent.

Les dashboards `[Kubernetes OTel]` du package `kubernetes_otel` lisent quatre
champs optionnels activés dans `helm/opentelemetry-kube-stack-values.yaml` : `k8s.pod.cpu_limit_utilization`
et `k8s.pod.memory_limit_utilization` (`kubeletstats`, uniquement pour les pods
qui déclarent des limites), `k8s.node.condition_memory_pressure`
(`node_conditions_to_report`) et l'attribut de ressource
`k8s.container.status.last_terminated_reason` (`k8s_cluster`). La cible
`make kubernetes-otel-dashboards-verify` contrôle qu'ils sont alimentés sur les
15 dernières minutes.

Les Services `elasticsearch-vm` et `kibana-vm` pointent vers `elk-01` par des
`Endpoints` et non des `EndpointSlice` : le Traefik 2.11 embarqué par k3s ne
résout les backends des `IngressRoute` qu'à partir des `Endpoints`. Contrôle :
`curl -k --resolve kibana.observability.test:443:192.168.33.50
https://kibana.observability.test/` renvoie `302` (redirection vers la page de
connexion).

Après une modification de cette chaîne, vérifier le rendu avec
`make kubernetes-validate`, puis contrôler les logs des collecteurs et la
présence récente de documents `metrics-*` dans Elasticsearch. Le déploiement
reste volontairement séparé de cette validation : appliquer l'overlay seulement
après revue du rendu.

Les secrets restent hors Git. Les mots de passe et clés utilisés par le lab
peuvent être chargés depuis `.observability-credentials.env`, généré par
`source ./platform/elk/scripts/generate-otel-edge-keys.sh`. Les modifications
durables doivent être faites dans les manifests, templates et scripts
versionnés avant tout déploiement.

La vérification ILM exclut le data stream système
`metrics-endpoint.metadata_current_default`, géré par l'intégration Endpoint
de Fleet. Les flux `logs-*`, `metrics-*` et `traces-*` de la télémétrie du lab
restent couverts par la policy déclarée dans
`platform/elk/ilm/retention.json`.

Les collecteurs Kubernetes s'authentifient auprès d'Edge avec deux clés Bearer
distinctes, la clé `otel-kubernetes` pour le daemon et la clé
`otel-kubernetes-cluster` pour le collecteur cluster. Les pods applicatifs
n'ont plus de clé : ils exportent vers le daemon. Les fournir hors Git avec
`OTEL_EDGE_KEY_KUBERNETES` et `OTEL_EDGE_KEY_KUBERNETES_CLUSTER`, puis exécuter
`make otel-edge-client-keys-apply` avant `make kubernetes-observability-deploy`.
Les clés sont stockées dans le Secret Kubernetes `otel-edge-client-keys` du
namespace `elastic-stack`. Les
VM utilisent chacune leur clé `OTEL_EDGE_KEY_<HOST>` (ADR-015).
