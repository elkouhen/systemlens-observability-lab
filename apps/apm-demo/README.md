# Application APM de démonstration

Cette application Spring Boot possède deux processus : `apm-demo` publie des
tâches vers Kafka et `apm-demo-worker` les consomme puis les persiste dans
MongoDB. Le Dockerfile produit une image pour chacun.

## Ordre de lecture

1. `pom.xml` : agrégateur Maven et versions communes.
2. `Dockerfile` : build multi-stage et agent Java OpenTelemetry.
3. [`kubernetes/README.md`](kubernetes/README.md) : variables de déploiement
   et raccordement au gateway OTLP.
4. `apm-demo/src/main/resources/application.yml`, puis la même configuration du
   worker : endpoints, Kafka, MongoDB et Actuator.
5. Le code des deux modules pour le flux métier.

Construire les deux images avec `make apps-build`, puis déployer uniquement
l'application avec `make apps-deploy`.

## Documentation externe

- [Instrumentation Java OpenTelemetry](https://opentelemetry.io/docs/zero-code/java/agent/)
- [Spring Boot Actuator](https://docs.spring.io/spring-boot/reference/actuator/)
- [Observabilité Kafka avec OpenTelemetry](https://opentelemetry.io/docs/zero-code/java/agent/supported-libraries/)
