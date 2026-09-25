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

L'architecture doit découpler les clients afin de contrôler séparément les
données remontées par chacun d'eux. Elle doit également bufferiser les signaux
pour absorber les fortes charges et les écarts temporaires entre leur émission
et leur écriture dans Elasticsearch.

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

Cette option est écartée parce que l'architecture doit rester découplée entre
la collecte des signaux et leur écriture dans Elasticsearch.

### Export direct vers Elasticsearch depuis le Collecteur Edge

C'est l'Edge qui porte la responsabilité de la collecte côté client. Un export
direct depuis l'Edge vers Elasticsearch supprimerait le découplage par client
apporté par Kafka et limiterait le contrôle des données remontées par chaque
client. Il serait également plus difficile d'arrêter sélectivement l'acheminement
d'un client sans modifier la collecte des autres. Cette option est écartée pour
conserver un contrôle indépendant par client et un chemin de données découplé.

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
- Kafka fournit le découplage et le buffering attendus dans l'architecture de
  référence Elastic ;
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
