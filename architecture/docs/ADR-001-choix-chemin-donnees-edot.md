# ADR-001 : choisir le chemin de données EDOT avec Kafka

## Statut

WIP

## Date

2026-09-25

## Contexte

Les agents EDOT des VM, les collecteurs Kubernetes et les applications doivent
converger vers une chaîne de collecte observable et reproductible. Le dépôt
décrit déjà un Collecteur Edge sur `otel-edge-01`, un Kafka OTel sur
`otel-backend-01`, un exporteur Kafka EDOT sur le backend et Elasticsearch sur
`elk-01`.

Le tampon Kafka sépare l'émission des signaux et leur écriture dans
Elasticsearch. Les topics sont séparés par signal afin que les logs, métriques
et traces soient décodés par le receiver Kafka avec leur format attendu.

## Décision

L'architecture de référence suit le chemin suivant pour les signaux EDOT :

```text
EDOT standalone → OTLP → otel-edge-01 → Kafka OTel → backend OTel → Elasticsearch
```

Les applications et les collecteurs Kubernetes utilisent également le
Collecteur Edge comme point d'entrée OTLP. Le backend consomme les topics Kafka
séparés par signal et exporte les données vers Elasticsearch. Les traces
peuvent passer par APM Server selon la configuration du backend ; les métriques
et les logs sont exportés vers Elasticsearch.

Cette décision fixe le chemin de données. Elle ne décide pas du mode de gestion
des agents EDOT, qui est traité dans [ADR-002](ADR-002-edot-standalone-ou-managed-by-fleet.md).

## Alternatives considérées

### Export direct vers Elasticsearch

Cette option réduit le nombre de composants intermédiaires, mais couple les
émetteurs à Elasticsearch et supprime le tampon Kafka commun aux signaux
Kubernetes et VM. Elle est écartée pour l'architecture de référence.

### Export direct vers Elasticsearch depuis le Collecteur Edge

Cette option conserve un point d'entrée OTLP, mais ne fournit pas le tampon
Kafka partagé ni la séparation explicite des topics par signal. Elle est
écartée pour le chemin de référence.

### Un topic Kafka partagé pour tous les signaux

Cette option simplifie le nombre de topics, mais le receiver Kafka EDOT utilisé
par le dépôt ne route pas automatiquement des payloads de logs, métriques et
traces mélangés dans un même topic. Elle est écartée pour éviter les erreurs de
décodage.

## Conséquences

### Conséquences positives

- le chemin des signaux est identique pour les sources Kubernetes et VM après
  leur entrée OTLP ;
- Kafka absorbe les écarts temporaires entre la production et l'export vers
  Elasticsearch ;
- les topics séparés rendent le routage et le diagnostic par signal explicites ;
- le point d'entrée OTLP, le buffer et l'exporteur sont déployables et
  vérifiables séparément.

### Coûts et limites

- le chemin ajoute Kafka, un exporteur backend et des contrôles de santé ;
- une panne du backend ou de Kafka peut retarder l'apparition des données dans
  Elasticsearch ;
- les limites de rétention et de capacité Kafka bornent la période pendant
  laquelle les signaux peuvent attendre leur export ;
- la recette doit vérifier chaque signal et chaque étape du chemin, pas seulement
  la présence de traces.

## Références

- [`platform/elk/README.md`](../platform/elk/README.md)
- [`ansible/README.md`](../ansible/README.md)
- [`platform/kubernetes/base/observability/README.md`](../platform/kubernetes/base/observability/README.md)
- [`platform/elk/fleet/README.md`](../platform/elk/fleet/README.md)
- [`docs/deploiement-opamp-standalone-spec.md`](deploiement-opamp-standalone-spec.md)
