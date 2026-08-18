# Policies Fleet et Elastic Agent

La configuration Fleet de référence est déclarée dans
[`../kubernetes/kibana-fleet-patch.yaml`](../kubernetes/kibana-fleet-patch.yaml),
dans `xpack.fleet`. ECK la transmet à Kibana au démarrage : aucun script hôte
ne crée les package policies standards MongoDB/Kafka.

## Parcours de lecture

- [`MONGODB.md`](MONGODB.md) : fonctionnement et adaptation de la policy
  `mongodb-fleet`.
- [`KAFKA.md`](KAFKA.md) : fonctionnement et adaptation de la policy
  `kafka-fleet` et de Jolokia.
- `mongodb-package-policy.json` et `kafka-package-policy.json` : modèles API
  réservés au playbook Ansible de policies dédiées par VM ; ils ne sont pas la
  source de vérité du déploiement Kubernetes.
- `kafka-topic-ingest-pipeline.json` : enrichissement du data stream Kafka.
- `system-package-policy.json` : exemple de policy système conservé comme
  référence ; elle n'est pas synchronisée par le script actuel.
- `elastic-agent.yml` : exemple de configuration standalone, distinct de Fleet.

Les deux package policies sont associées à l'agent policy `mongodb-hosts`. Dans
ce POC, un Elastic Agent tourne sur chaque VM : `localhost` désigne donc le
service local à la VM, jamais le poste qui exécute `make fleet-sync`.

Appliquer `make kibana-fleet-config-deploy` (inclus dans `make elk-deploy`) pour
déclarer les policies. `make fleet-sync` ne met plus à jour que les pipelines
Elasticsearch `@custom`, qui ne font pas partie de la configuration Kibana.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
