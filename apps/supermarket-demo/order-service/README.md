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

## API OpenAPI

Le contrat API First est versionné dans `src/main/resources/static/openapi.yaml`.
Maven le valide avant la compilation ; toute évolution d'endpoint ou de payload
commence donc par ce fichier. Avec le service démarré localement, le contrat est
servi sur `http://localhost:3000/openapi.yaml` et consultable avec Swagger UI
sur `http://localhost:3000/swagger-ui.html`. Vérifier que l'interface liste les
opérations `POST /api/orders`, `GET /api/error` et `GET /api/health`.

## API AsyncAPI

Le contrat API First Kafka est versionné dans
`src/main/resources/static/asyncapi.yaml`. Il définit la publication de
`OrderPlaced` sur `supermarket.order.placed`, avec `orderId` comme clé Kafka.
Le fichier est servi sur `http://localhost:3000/asyncapi.yaml`. Pour le
valider localement, avec Node.js 16 ou supérieur, exécuter :

```bash
npx --yes @asyncapi/cli@5.0.7 validate src/main/resources/static/asyncapi.yaml
```

## Documentation externe

- [Spring Boot externalized configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html)
- [Spring for Apache Kafka](https://docs.spring.io/spring-kafka/reference/)
- [Agent Java Elastic APM](https://www.elastic.co/docs/reference/apm/agents/java)
