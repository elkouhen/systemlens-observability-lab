# Déploiement Kubernetes de l'application

`kustomization.yaml` est le point d'entrée IaC de l'application. `namespace.yaml`
isole l'application dans le namespace `supermarket-demo`.
`deployment.yaml` décrit ses Deployments, Services et variables
d'environnement : adresses Kafka/MongoDB et identité de télémétrie. Les traces
d'`order-service` vont directement à APM Server via l'agent Java Elastic ;
`inventory-service` est exporté en OTLP vers APM Server.

## Points à contrôler en lisant `deployment.yaml`

1. Les tags d'image doivent correspondre à ceux produits par `make apps-build`.
2. Les variables `ELASTIC_APM_*` d'`order-service` et `OTEL_*`
   d'`inventory-service` doivent viser APM Server. Le token APM est passé à
   l'agent OpenTelemetry sous forme d'en-tête HTTP au démarrage du conteneur.
3. Les endpoints Kafka et MongoDB pointent vers les VM, et non vers Kubernetes.
4. Les probes et ressources doivent être adaptées avant une charge réelle.

Appliquer avec `make apps-deploy`. Cette cible synchronise d'abord dans le
namespace applicatif le token et le certificat APM créés par ECK ; exécuter
`make elk-deploy` au préalable si la chaîne d'observabilité n'existe pas.

## Documentation externe

- [Deployments Kubernetes](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Services Kubernetes](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Configuration OpenTelemetry](https://opentelemetry.io/docs/concepts/sdk-configuration/)
