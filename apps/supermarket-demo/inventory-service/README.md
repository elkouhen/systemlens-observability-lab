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

## Architecture hexagonale

Le module sépare le métier des frameworks et des systèmes externes :

- `domain/` contient les règles métier du stock et ne dépend pas de Spring,
  JPA, MongoDB ou Kafka ;
- `application/` contient le cas d’usage de réservation et les ports entrants
  et sortants ;
- `adapter/in/` contient les adaptateurs REST et Kafka ;
- `adapter/out/` contient les adaptateurs de persistance JPA/MongoDB et de
  publication Kafka.

Toute évolution du stockage ou du transport doit rester dans un adaptateur.
Le cas d’usage ne doit dépendre que des ports et du domaine, afin de préserver
la testabilité et de permettre de remplacer une technologie sans modifier les
règles métier.

## Documentation externe

- [Spring for Apache Kafka](https://docs.spring.io/spring-kafka/reference/)
- [Spring Data MongoDB](https://docs.spring.io/spring-data/mongodb/reference/)
- [Spring Data JPA](https://docs.spring.io/spring-data/jpa/reference/)
