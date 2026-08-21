# Comparatif des solutions d'intégration

Ce document distingue le **mode de gestion** (Fleet ou standalone), le
**collecteur** et le **chemin d'ingestion**. Fleet ne remplace pas à lui seul un
collecteur : il pilote Elastic Agent et ses intégrations.

## Logs

| Solution | Chemin | Points forts | Limites / vigilance | Usage dans le POC |
| --- | --- | --- | --- | --- |
| Elastic Agent + Fleet | fichier/stdout → Agent → Elasticsearch | gestion centralisée, intégrations et assets Kibana, enrichissement Kubernetes | dépend de Fleet ; moins adapté aux transformations très spécifiques | logs des pods Kubernetes |
| Filebeat | fichier → Filebeat → Elasticsearch | simple, léger, configuration lisible ; contrôle fin des fichiers | configuration distribuée, pas de gestion Fleet | logs OS, MongoDB, Kafka et PostgreSQL des VM |
| OpenTelemetry Collector (OTLP Logs) | application → OTLP → Collector → Elasticsearch | unifie les trois signaux, transformations OTel, routage possible | éviter les doublons avec stdout ; compatibilité dashboard à vérifier | alternative documentée, désactivée pour les logs applicatifs |
| Logstash / Kafka | émetteur → Kafka/Logstash → Elasticsearch | tampon, transformations riches, découplage | coût d'exploitation et latence supplémentaires | alternative à évaluer, non active |

## Métriques

| Solution | Chemin | Points forts | Limites / vigilance | Usage dans le POC |
| --- | --- | --- | --- | --- |
| Elastic Agent + Fleet | intégration → Agent → Elasticsearch | packages officiels, dashboards préconstruits, politiques centrales | version de package et variables Fleet à maîtriser | MongoDB et Kafka sur la VM Elastic Agent |
| Metricbeat | module → Metricbeat → Elasticsearch | mature, efficace pour les métriques système, format ECS historique | gestion séparée ; migration future vers Agent/OTel à planifier | métriques système de la VM Beats |
| EDOT / OTel Collector | receiver → processeurs → Elasticsearch | standard ouvert, pipeline explicite, enrichissement et routage multi-backend | schéma OTel : vérifier les champs attendus par les dashboards Elastic | métriques système, MongoDB, Kafka et PostgreSQL de la VM OpenTelemetry, ainsi que Kubernetes |
| Micrometer + OTLP | application → OTLP → gateway → Elasticsearch | métriques applicatives proches du code ; corrélation avec service et traces | cardinalité à maîtriser ; temporality/histogrammes à configurer | métriques des services applicatifs |

## APM, transactions et traces

| Solution | Chemin | Points forts | Limites / vigilance | Usage dans le POC |
| --- | --- | --- | --- | --- |
| Agent Elastic APM → APM Server | application → APM Server → Elasticsearch | expérience Elastic APM native ; configuration directe | spécifique Elastic ; APM Server à opérer | chemin actif d'`order-service` |
| Agent OpenTelemetry → APM Server (OTLP) | application → OTLP → APM Server → Elasticsearch | instrumentation standard avec backend APM Elastic | capacités et version OTLP/APM Server à valider | alternative de comparaison |
| Agent OpenTelemetry → EDOT → Elasticsearch | application → OTLP → Collector → Elasticsearch | pipeline ouvert, enrichissement/routage contrôlé | mapping OTel et compatibilité APM Kibana à valider | base de la chaîne active |
| Agent OpenTelemetry → EDOT → Kafka → EDOT → Elasticsearch | application → OTLP → gateway → Kafka → backend → Elasticsearch | tampon, reprise après indisponibilité courte, montée en charge des consommateurs | latence ; supervision du topic, consumer lag et rétention indispensable | chemin actif des traces d'`inventory-service` |

## Choix actuellement démontrés

Le POC maintient volontairement trois profils exclusifs afin de les comparer
sur des données réelles :

- EDOT pour les logs et métriques de la VM OpenTelemetry ;
- Elastic Agent piloté par Fleet pour la VM Elastic Agent ;
- Filebeat + Metricbeat pour la VM Beats ;
- l'agent Java Elastic et APM Server pour les traces d'`order-service`, et
  l'agent Java OpenTelemetry avec les collectors EDOT pour les signaux
  d'`inventory-service` ;
- Kafka exclusivement sur le chemin des traces, pas des métriques applicatives.

Pour chaque modification, consigner dans la matrice des métriques le format
effectivement indexé et vérifier le dashboard associé. Le meilleur mécanisme
de collecte dépend du signal et de l'objectif : il n'existe pas de collecteur
unique qui soit automatiquement le meilleur pour tous les cas.
