# Module consommateur Kafka et MongoDB

Ce module reçoit les tâches Kafka, les traite et sauvegarde le résultat dans
MongoDB. Lire `src/main/resources/application.yml` avant les classes du package
`worker` pour comprendre les adresses de connexion et le nom du consumer group.

L'agent Java OpenTelemetry, défini dans le Dockerfile parent, produit les traces
des interactions Kafka et MongoDB sans modifier le code de ce module.

## Documentation externe

- [Spring for Apache Kafka](https://docs.spring.io/spring-kafka/reference/)
- [Spring Data MongoDB](https://docs.spring.io/spring-data/mongodb/reference/)
