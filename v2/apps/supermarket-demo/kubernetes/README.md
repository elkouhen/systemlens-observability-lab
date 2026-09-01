# Déploiement Kubernetes de l'application

`kustomization.yaml` est le point d'entrée IaC de l'application. `namespace.yaml`
isole l'application dans le namespace `h0tl-supermarche-app`.
`deployment.yaml` décrit ses Deployments, Services et variables
d'environnement : adresses Kafka/MongoDB et identité de télémétrie. Les traces
d'`order-service`, d'`inventory-service` et de `restock-service` vont au
Gateway EDOT via l'agent Java OpenTelemetry.

Les trois services écrivent leurs logs JSON ECS sur stdout. Le DaemonSet EDOT
Kubernetes les collecte avec `filelog`, les publie dans Kafka `otel-logs`, puis
le Collector backend les exporte vers Elasticsearch. Les logs n'ont donc pas
de variable d'environnement dédiée. Les signaux OTel reçoivent le namespace
Kubernetes via l'instrumentation et conservent les identifiants de trace pour
la corrélation avec APM.

## Points à contrôler en lisant `deployment.yaml`

1. Les tags d'image doivent correspondre à ceux produits par `make apps-build`.
2. L'instrumentation OTel des trois services doit viser le Gateway EDOT.
   Le token APM et le certificat ECK ne sont pas requis pour ce chemin ; les
   logs ECS restent collectés sur stdout par le DaemonSet EDOT Kubernetes.
3. Les endpoints Kafka et MongoDB pointent vers les VM, et non vers Kubernetes.
4. Les probes et ressources doivent être adaptées avant une charge réelle.

Appliquer avec `make apps-deploy`. Cette cible crée d'abord le namespace depuis
`namespace.yaml`, puis y synchronise le token et le certificat APM créés par
ECK ; exécuter `make elk-deploy` au préalable si la chaîne d'observabilité
n'existe pas.

## Documentation externe

- [Deployments Kubernetes](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Services Kubernetes](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Agent Java Elastic APM](https://www.elastic.co/docs/reference/apm/agents/java)
