# Applications

Ce répertoire contient le code et les manifests propres aux workloads métier.
Il est volontairement séparé de `platform/` : une application ne doit pas
porter la configuration de la plateforme ELK qui l'observe.

## Parcours conseillé

Lire [`supermarket-demo/README.md`](supermarket-demo/README.md), puis la base
commune et l'overlay v3 sous `../kubernetes/apps/`, et enfin les modules Maven
communs. L'application est raccordée à l'architecture d'observabilité v3.

Pour intégrer une nouvelle application Java dans les chaînes APM/OTel et logs
ECS, suivre [Ajouter une application Java observée](ADDING_APPLICATION.md).
Pour vérifier l’intégration de bout en bout, consulter le
guide de déploiement et d'exploitation de l'architecture v3.

## Documentation externe

- [Déployer des workloads Kubernetes](https://kubernetes.io/docs/concepts/workloads/)
- [Agent Java Elastic APM](https://www.elastic.co/docs/reference/apm/agents/java)
