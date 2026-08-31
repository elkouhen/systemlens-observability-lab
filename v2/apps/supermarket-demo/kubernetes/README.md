# Déploiement Kubernetes de l'application

`kustomization.yaml` est le point d'entrée IaC de l'application. `namespace.yaml`
isole l'application dans le namespace `h0tl-supermarche-app-v2`.
`deployment.yaml` décrit ses Deployments, Services et variables
d'environnement : adresses Kafka/MongoDB et identité de télémétrie. Les traces
d'`order-service`, d'`inventory-service` et de `restock-service` vont
directement à APM Server via l'agent Java Elastic APM.

Les trois services écrivent leurs logs JSON ECS sur stdout. L'Elastic Agent
Kubernetes les collecte d'abord dans `kubernetes.container_logs`, puis Logstash
utilise `kubernetes.namespace` et les route vers
`logs-kube-<code_plateforme>-<environnement>`. Les logs n'ont donc pas de
variable d'environnement dédiée. Les signaux APM reçoivent le namespace
Kubernetes via `KUBERNETES_NAMESPACE` et respectent la même convention
`<type><plateforme_sur_3_caractères>-<namespace>`, ici
`h0tl-supermarche-app-v2`. Logstash normalise `service.environment` en
`homologation`, tout en ajoutant `labels.ptf: 0tl` et
`labels.namespace: supermarche-app`. Les métriques APM Java applicatives
détaillées sont routées vers leur data stream d'environnement. Les métriques
APM agrégées restent dans leur data stream d'origine, car elles ne portent pas
toujours le namespace Kubernetes.

## Points à contrôler en lisant `deployment.yaml`

1. Les tags d'image doivent correspondre à ceux produits par `make apps-build`.
2. Les variables `ELASTIC_APM_*` des trois services doivent viser APM Server.
   Le token APM et le certificat ECK sont montés par `make apps-deploy`. Les
   logs ECS restent collectés sur stdout par l'Elastic Agent Kubernetes.
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
