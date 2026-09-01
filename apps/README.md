# Applications

Ce répertoire contient le code et les manifests propres aux workloads métier.
Il est volontairement séparé de `platform/` : une application ne doit pas
porter la configuration de la plateforme ELK qui l'observe.

## Parcours conseillé

Lire [`supermarket-demo/README.md`](supermarket-demo/README.md), puis la base
commune et les overlays Kubernetes sous `../kubernetes/apps/`, et enfin les
modules Maven communs. Les overlays v1 et v2 déploient le même métier avec des
raccordements de télémétrie différents.

Pour intégrer une nouvelle application Java dans les chaînes APM/OTel et logs
ECS, suivre [Ajouter une application Java observée](ADDING_APPLICATION.md).
Pour vérifier l’intégration de bout en bout, consulter le
[comparatif v1/v2](../docs/architecture-v1-v2-differences.md), puis le guide
APM correspondant à l'architecture choisie.

## Documentation externe

- [Déployer des workloads Kubernetes](https://kubernetes.io/docs/concepts/workloads/)
- [Agent Java Elastic APM](https://www.elastic.co/docs/reference/apm/agents/java)
