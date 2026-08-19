# Application APM de démonstration

Cette application Spring Boot possède deux processus : `apm-demo` publie des
tâches vers Kafka et `apm-demo-worker` les consomme puis les persiste dans
MongoDB et PostgreSQL (sur `data-01`). Le Dockerfile produit une image pour chacun.

## Ordre de lecture

1. `pom.xml` : agrégateur Maven et versions communes.
2. `Dockerfile` : build multi-stage et agent Java OpenTelemetry.
3. [`kubernetes/README.md`](kubernetes/README.md) : variables de déploiement
   et raccordement au gateway OTLP.
4. `apm-demo/src/main/resources/application.yml`, puis la même configuration du
   worker : endpoints, Kafka, MongoDB, PostgreSQL et Actuator.
5. Le code des deux modules pour le flux métier.

Construire les deux images avec `make apps-build`, puis déployer uniquement
l'application avec `make apps-deploy`.

## Documentation externe

- [Instrumentation Java OpenTelemetry](https://opentelemetry.io/docs/zero-code/java/agent/)
- [Spring Boot Actuator](https://docs.spring.io/spring-boot/reference/actuator/)
- [Observabilité Kafka avec OpenTelemetry](https://opentelemetry.io/docs/zero-code/java/agent/supported-libraries/)

## Versions d'images

Le build Maven est figé sur `maven:3.9.9-eclipse-temurin-21` et les images
d'exécution sur `eclipse-temurin:21.0.7_6-jre-noble`. Toute mise à jour doit
être testée puis effectuée dans une modification dédiée.

Le tag des images Docker (`apm-demo:1.0.4` / `apm-demo-worker:1.0.4`, fixé
dans `Makefile` et `kubernetes/deployment.yaml`) est géré indépendamment de
`<version>` dans les `pom.xml` (actuellement `1.0.0`, partagée par les trois
modules Maven). Le tag Docker identifie une itération de l'image de
démonstration ; la version Maven identifie une itération du code Java. Bumper
l'un ne doit pas être attendu comme bumpant automatiquement l'autre : mettre à
jour les deux explicitement si un changement doit être visible dans les deux
espaces de version.
