# Module consommateur Kafka, MongoDB et PostgreSQL

Ce module reçoit les tâches Kafka, les traite et sauvegarde le résultat dans
MongoDB et PostgreSQL. Les deux écritures partagent le même UUID ; si l'écriture
PostgreSQL échoue, l'écriture MongoDB est compensée. Lire
`src/main/resources/application.yml` avant les classes du package
`worker` pour comprendre les adresses de connexion et le nom du consumer group.

L'agent Java OpenTelemetry, défini dans le Dockerfile parent, produit les traces
des interactions Kafka, MongoDB et PostgreSQL sans modifier le code de ce module.

## Documentation externe

- [Spring for Apache Kafka](https://docs.spring.io/spring-kafka/reference/)
- [Spring Data MongoDB](https://docs.spring.io/spring-data/mongodb/reference/)
- [Spring Data JPA](https://docs.spring.io/spring-data/jpa/reference/)
