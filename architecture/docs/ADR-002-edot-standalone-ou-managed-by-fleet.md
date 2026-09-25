# ADR-002 : choisir la gestion EDOT standalone avec supervision Fleet

## Statut

WIP

## Date

2026-09-25

## Contexte

Les VM exécutent un Elastic Agent en mode EDOT standalone. Sa configuration
locale décrit les receivers, le traitement des signaux et l'export OTLP vers
`otel-edge-01`. Fleet et OpAMP sont également disponibles sur `elk-01`, mais
ils peuvent soit gérer la collecte des agents, soit superviser des agents dont
la collecte reste déclarée localement.

Le dépôt utilise déjà Ansible comme source de vérité pour la configuration EDOT
des VM. Il doit éviter qu'une policy Fleet de collecte concurrente modifie ou
double le chemin `EDOT standalone → OTLP → otel-edge-01`.

## Décision

Les VM utilisent EDOT standalone pour la collecte et l'export des signaux. La
configuration est installée et maintenue par Ansible. Fleet utilise OpAMP pour
superviser ces agents, sans devenir la source de vérité de leur collecte.

La séparation est donc la suivante :

| Responsabilité | Source de vérité |
| --- | --- |
| Receivers, processeurs et export OTLP des agents VM | Configuration EDOT versionnée et Ansible |
| État, identité et télémétrie interne des agents | OpAMP et Fleet |
| Assets Kibana et packages d'intégration | Fleet et les packages déclarés |

Les agents restent visibles dans Fleet comme collecteurs OTel supervisés. Ils
ne sont pas enrôlés comme agents Fleet classiques collecteurs. La cible
`make fleet-opamp-enable` active la supervision sans modifier le chemin de
données défini dans [ADR-001](ADR-001-choix-chemin-donnees-edot.md).

## Alternatives considérées

### EDOT managed by Fleet

Fleet deviendrait la source de vérité de la collecte et distribuerait la
configuration aux agents. Cette option centralise la gestion, mais introduit
une seconde source de vérité par rapport aux templates EDOT versionnés et peut
modifier le chemin OTLP local des VM. Elle est écartée pour l'architecture de
référence.

### EDOT standalone sans supervision OpAMP

Les agents conserveraient leur configuration locale sans rattachement à Fleet.
Cette option réduit la dépendance au plan de contrôle, mais supprime la
visibilité centralisée de l'état et de la télémétrie interne des agents. Elle
est écartée pour le fonctionnement normal, mais reste un mode de repli si
Fleet est temporairement indisponible.

### Collecte Fleet classique en parallèle d'EDOT standalone

Cette option activerait simultanément la collecte Fleet et la collecte EDOT
locale. Elle peut créer une double collecte et rendre le routage des signaux
ambigu. Elle est exclue.

## Conséquences

### Conséquences positives

- la configuration effective de la collecte reste versionnée dans le dépôt ;
- Fleet fournit une visibilité centralisée sans remplacer le chemin OTLP local ;
- une seconde exécution Ansible peut conserver un agent conforme et son
  identifiant OpAMP persistant ;
- les assets Kibana et la supervision Fleet restent disponibles pour le
  diagnostic.

### Coûts et limites

- la configuration est répartie entre Ansible pour la collecte et Fleet pour la
  supervision et les assets ;
- l'état Fleet peut être sain alors que le chemin EDOT vers Elasticsearch est
  interrompu, ou l'inverse ;
- la recette doit contrôler séparément l'état OpAMP et la présence récente des
  logs, métriques et traces ;
- une modification durable de la collecte doit être faite dans Ansible, puis
  vérifiée sans activer une policy Fleet concurrente.

## Références

- [`ansible/README.md`](../ansible/README.md)
- [`platform/elk/README.md`](../platform/elk/README.md)
- [`platform/elk/fleet/README.md`](../platform/elk/fleet/README.md)
- [`docs/deploiement-opamp-standalone-spec.md`](deploiement-opamp-standalone-spec.md)
