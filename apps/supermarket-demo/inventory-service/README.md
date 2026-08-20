# Module inventory-service : gestion du stock

Ce module reçoit les commandes (via Kafka pour les commandes en ligne, via REST
pour les commandes en caisse), vérifie et décrémente le stock du produit
demandé, puis sauvegarde le résultat dans MongoDB (journal d'audit
`order_fulfillments`) et PostgreSQL (registre `stock_movements` et catalogue
`products`). Les deux écritures partagent le même identifiant de commande ; si
l'écriture PostgreSQL échoue, l'écriture MongoDB et la décrémentation de stock
sont compensées. Une quantité demandée supérieure au stock disponible déclenche
une rupture de stock (`OutOfStockException`, HTTP 409). Lire
`src/main/resources/application.yml` avant les classes du package `inventory`
pour comprendre les adresses de connexion et le nom du consumer group.

L'agent Java OpenTelemetry, défini dans le Dockerfile parent, produit les traces
des interactions Kafka, MongoDB et PostgreSQL sans modifier le code de ce module.

## Documentation externe

- [Spring for Apache Kafka](https://docs.spring.io/spring-kafka/reference/)
- [Spring Data MongoDB](https://docs.spring.io/spring-data/mongodb/reference/)
- [Spring Data JPA](https://docs.spring.io/spring-data/jpa/reference/)
