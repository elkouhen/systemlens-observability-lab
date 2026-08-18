# Module producteur HTTP et Kafka

Ce module expose les endpoints HTTP de démonstration et publie périodiquement
des tâches Kafka. Commencer par `src/main/resources/application.yml`, qui
définit les propriétés Spring, Kafka et Actuator, puis lire les contrôleurs et
le planificateur dans `src/main/java`.

La télémétrie est injectée par l'agent Java au démarrage du conteneur ; elle ne
nécessite donc pas de SDK OpenTelemetry dans ce module.

## Documentation externe

- [Spring Boot externalized configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html)
- [Spring for Apache Kafka](https://docs.spring.io/spring-kafka/reference/)
