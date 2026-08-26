# Déploiement Kubernetes de l'application

`kustomization.yaml` est le point d'entrée IaC de l'application. `namespace.yaml`
isole l'application dans le namespace `supermarket-demo`.
`deployment.yaml` décrit ses Deployments, Services et variables
d'environnement : adresses Kafka/MongoDB et identité de télémétrie. Les traces
d'`order-service`, d'`inventory-service` et de `restock-service` vont
directement à APM Server via l'agent Java Elastic APM.

Les trois services écrivent leurs logs JSON ECS sur stdout. L'Elastic Agent
Kubernetes les collecte dans `logs-kubernetes.container_logs-*`. La valeur
`service.environment` est commune aux logs et aux signaux APM et respecte la
convention `<type><plateforme_sur_3_caractères>-<namespace>`, par exemple
`h0p1-supermarket`. Logstash le décode et normalise `service.environment` en
`homologation`, tout en ajoutant `labels.ptf: 0p1` et
`labels.namespace: supermarket`. Les métriques APM Java sont routées vers
`metrics-apm.app.kubernetes-homologation`. Les logs et traces restent dans
leurs data streams d'origine.

## Points à contrôler en lisant `deployment.yaml`

1. Les tags d'image doivent correspondre à ceux produits par `make apps-build`.
2. Les variables `ELASTIC_APM_*` des trois services doivent viser APM Server.
   Le token APM et le certificat ECK sont montés par `make apps-deploy`. Les
   logs ECS restent collectés sur stdout par l'Elastic Agent Kubernetes.
3. Les endpoints Kafka et MongoDB pointent vers les VM, et non vers Kubernetes.
4. Les probes et ressources doivent être adaptées avant une charge réelle.

Appliquer avec `make apps-deploy`. Cette cible synchronise d'abord dans le
namespace applicatif le token et le certificat APM créés par ECK ; exécuter
`make elk-deploy` au préalable si la chaîne d'observabilité n'existe pas.

## Documentation externe

- [Deployments Kubernetes](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Services Kubernetes](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Agent Java Elastic APM](https://www.elastic.co/docs/reference/apm/agents/java)
