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

L'agent Java Elastic APM, défini dans le Dockerfile parent, produit les traces
des interactions Kafka, MongoDB et PostgreSQL sans modifier le code de ce module.
Les transactions Kafka sont exposées directement avec le type `messaging` dans
la vue APM.

Chaque réservation produit un log ECS métier : `INFO` en cas de succès et
`WARN` pour une quantité invalide, un produit absent ou une rupture de stock.
Lorsqu'une réservation épuise le stock, le service publie
`supermarket.stock.depleted`. `restock-service` répond par une demande sur
`supermarket.stock.restock-requested`, appliquée ici afin que ce module reste
propriétaire du catalogue PostgreSQL.
Avec `ELASTIC_APM_ENABLE_LOG_CORRELATION=true`, ces événements contiennent les
identifiants de trace injectés par l'agent et sont donc accessibles depuis la
vue Logs des transactions APM.

## Documentation externe

- [Spring for Apache Kafka](https://docs.spring.io/spring-kafka/reference/)
- [Spring Data MongoDB](https://docs.spring.io/spring-data/mongodb/reference/)
- [Spring Data JPA](https://docs.spring.io/spring-data/jpa/reference/)
