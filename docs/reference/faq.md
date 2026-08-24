# FAQ d'architecture

## Y a-t-il un intérêt à utiliser Metricbeat avec Elastic Agent piloté par Fleet ?

Oui, mais seulement comme **solution transitoire ou de comparaison**. Pour une
même source, il ne faut pas faire collecter la même métrique par Metricbeat et
par une intégration Elastic Agent : cela crée des doublons, des champs ou data
streams différents, et des dashboards potentiellement incohérents.

### Quand Metricbeat reste pertinent

- une configuration Metricbeat existe déjà et sa migration serait risquée ;
- un module ou une personnalisation disponible dans Metricbeat n'a pas encore
  d'équivalent satisfaisant dans l'intégration Fleet retenue ;
- le POC conserve Metricbeat sur `data-03` afin de comparer son format ECS à
  celui des intégrations Elastic Agent ;
- une collecte doit continuer indépendamment de Fleet pendant une phase de
  migration ou de diagnostic.

### Quand privilégier Elastic Agent + Fleet

- les intégrations nécessaires sont disponibles sous forme de package Elastic ;
- on souhaite administrer les politiques, mises à jour et variables depuis
  Kibana ;
- les dashboards et pipelines fournis par l'intégration sont recherchés ;
- le parc contient plusieurs hôtes et une configuration centrale réduit le
  travail d'exploitation.

### Décision dans ce POC

Le POC affecte `data-01` et `data-02` au profil Fleet, et `data-03` au profil
Beats. Ces profils sont exclusifs sur un hôte afin d'éviter les doublons.

Avant de migrer une source de Metricbeat vers Fleet, vérifier :

1. les métriques effectivement couvertes par l'intégration cible ;
2. les data streams et champs utilisés par les dashboards ;
3. l'absence de doublon durant la bascule ;
4. la procédure de retour arrière.
