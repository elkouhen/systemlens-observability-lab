# Module order-service : commandes du supermarché

Ce module simule la prise de commande côté supermarché. Il expose une API HTTP
pour passer une commande en caisse (`POST /api/orders`, appel synchrone vers
`inventory-service`) et publie périodiquement des commandes en ligne sur Kafka
(commandes traitées en tâche de fond par `inventory-service`). Commencer par
`src/main/resources/application.yml`, qui définit les propriétés Spring, Kafka
et Actuator, puis lire les contrôleurs et le planificateur dans
`src/main/java`.

Les traces sont injectées par l'agent Java Elastic au démarrage du conteneur et
envoyées directement à APM Server ; elles ne nécessitent aucun SDK dans ce
module. L'agent est configuré dans le Deployment Kubernetes, qui lui fournit
l'identité du service, le token APM et le certificat de l'APM Server.

## Documentation externe

- [Spring Boot externalized configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html)
- [Spring for Apache Kafka](https://docs.spring.io/spring-kafka/reference/)
- [Agent Java Elastic APM](https://www.elastic.co/docs/reference/apm/agents/java)
