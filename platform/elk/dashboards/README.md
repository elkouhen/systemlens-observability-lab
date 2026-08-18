# Dashboards Kibana

Les fichiers `.ndjson` sont des exports d'objets sauvegardés Kibana. Ils sont
versionnés afin que les visualisations du POC puissent être recréées sans clic
manuel dans Kibana.

## Fichiers

- `mongodb-cluster-primary.ndjson` : dashboard SystemLens du replica set
  MongoDB et de son primary.
- `primary-cluster.ndjson` : export complémentaire de visualisation de cluster.

Importer le premier avec `make dashboard-deploy`, ou sélectionner un fichier en
argument de `platform/elk/scripts/deploy-kibana-dashboard.sh`.

## Documentation externe

- [Importer et exporter des objets sauvegardés Kibana](https://www.elastic.co/docs/explore-analyze/visualize/kibana/management)
- [Créer des dashboards Kibana](https://www.elastic.co/docs/explore-analyze/dashboards)
