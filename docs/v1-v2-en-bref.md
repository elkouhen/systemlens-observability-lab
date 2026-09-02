# V1, V2 et V3 en bref

Cette page sert uniquement de point d'orientation. Les procédures et les
comparaisons détaillées sont maintenues dans les documents liés ci-dessous.

## Choisir une version

- **v1** : Elastic APM, Filebeat/Metricbeat et Logstash ; adaptée à la
  reproduction du chemin historique du POC.
- **v2** : OpenTelemetry/EDOT et Kafka comme tampon de télémétrie ; adaptée au
  test du nouveau chemin OTLP.
- **v3** : structure v2 pour les applications et Kubernetes, avec Elastic Agent
  Fleet et sortie directe Elasticsearch pour les VM ; adaptée à l'architecture
  de référence hybride.

Les trois variantes partagent le code Java, utilisent l'unique VM `data-01`, les
services de données en mode minimal et les namespaces Kubernetes
`elastic-stack` et `h0tl-supermarche-app`. Une seule variante doit être active à
la fois.

## Parcours recommandé

1. Lire le [guide de déploiement et d'exploitation](deploiement-et-exploitation.md).
2. Consulter la [référence v1/v2/v3](architecture-v1-v2-v3.md).
3. Utiliser les [schémas historiques v1/v2](observability-flows-v1-v2.md) et
   le schéma v3 de la référence pour suivre
   un signal jusqu'à Elasticsearch.
4. Consulter le [diff de code historique](diff-code-v1-v2.md) uniquement pour les sujets
   de maintenance et de mutualisation.

Pour les détails d'un composant, suivre les README locaux des répertoires
[`v1`](../v1/README.md), [`v2`](../v2/README.md), [`v3`](../v3/README.md), `apps/` et `scripts/`.
