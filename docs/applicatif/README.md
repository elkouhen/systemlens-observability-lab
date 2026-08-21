# Documentation applicative

Cette partie s'adresse aux développeurs qui travaillent sur les services de
démonstration. Son objectif est de générer un flux métier, de comprendre les
signaux qui en résultent et de vérifier leur présence dans Kibana.

Elle traite `order-service`, `inventory-service`, les scénarios de commande et
leur instrumentation. L'exploitation de Kubernetes, Fleet et des collecteurs
reste dans la [documentation système](../systeme/README.md).

## Découvrir les services et leurs signaux

1. [Supermarché de démonstration](../../apps/supermarket-demo/README.md) :
   scénario métier, endpoints et flux HTTP/Kafka.
2. [Déploiement Kubernetes de l'application](../../apps/supermarket-demo/kubernetes/README.md) :
   identités de service et raccordement aux backends de télémétrie.
3. [Modes d'intégration testés](integrations.md) : comparaison, côté
   application, de l'agent Java Elastic/APM Server et de l'agent Java
   OpenTelemetry/EDOT/Kafka.
4. [Architecture des signaux](../systeme/architecture-signaux.md) : détail
   système des chemins distincts d'`order-service` et d'`inventory-service`.

## Tutoriel

[Première démonstration : suivre une commande de bout en bout](tutorials/premiere-demonstration.md)
explique comment générer une commande puis retrouver ses logs, métriques et
traces.

## Quand le problème dépasse l'application

Si le trafic est généré mais qu'aucun document n'est indexé, suivre le guide
système [Vérifier un signal de bout en bout](../systeme/how-to/verifier-un-signal.md).
