# Flux potentiels des applications Java

## Périmètre et méthode

- Profil SystemLens : `flows`.
- Périmètre : sources de production Java de `order-service`,
  `inventory-service` et `restock-service`.
- Révision : `d3c15deef70536b06677528ee6475811bce64f89` avec changements locaux.
- Nature : parcours potentiels visibles dans le code, pas traces d'exécution.
- Sources : trois flux conservateurs matérialisés par `systemlens flows`, puis
  prolongement assisté uniquement à travers des appels directs ou des ports
  ayant une seule implémentation dans le dépôt.

Les étapes ordonnées restent dans ce rapport : elles ne sont pas importées
comme des arêtes de topologie. Le graphe référence seulement leurs identifiants
dans les métadonnées des relations concernées.

## Socle SystemLens

| Identifiant | Entrée | Effet dans la même méthode | Statut |
|---|---|---|---|
| `e9ea4940d67a092f` | `POST /api/orders` | `POST /api/reservations` | potentiel, confiance moyenne |
| `2f3538eca0f04901` | `GET /api/error` | `POST /api/reservations` | potentiel, confiance moyenne |
| `432c14ecee0d2898` | Kafka `supermarket.stock.depleted` | publication Kafka `supermarket.stock.restock-requested` | potentiel, confiance moyenne |

## `java.checkout-reservation`

Entrée : `POST /api/orders`. Provenance : `systemlens` pour les deux premières
étapes, puis `source-assisted`. Statut : potentiel. Confiance : moyenne.

1. `OrderController.placeOrder` reçoit la commande et construit `OrderPlaced`
   (`order-service/src/main/java/io/systemlens/supermarket/order/OrderController.java:42`).
2. Le contrôleur appelle `POST /api/reservations` avec `RestTemplate`
   (`OrderController.java:47`).
3. Frontière de configuration : la propriété Java
   `order-service.inventory-service-url` nomme `inventory-service`, mais sa
   valeur runtime n'est pas prouvée par le Java. La suite vaut si cette cible
   proposée est effectivement résolue.
4. `InventoryController.reserve` délègue à l'unique implémentation
   d'`InventoryUseCase`, `InventoryApplicationService`
   (`inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/in/web/InventoryController.java:16`,
   `inventory-service/src/main/java/io/systemlens/supermarket/inventory/application/InventoryApplicationService.java:27`).
5. Une frontière `@Transactional` commence sur `reserve`
   (`InventoryApplicationService.java:62`). Le gestionnaire de transaction
   effectif n'est pas déterminable à partir de cette annotation seule.
6. Le service lit `products`, applique `Product.reserve`, puis réécrit le
   produit (`InventoryApplicationService.java:72`, `:76`, `:77`; adaptateur
   unique `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/persistence/jpa/ProductPersistenceAdapter.java:13`).
7. Il écrit `order_fulfillments` dans MongoDB
   (`InventoryApplicationService.java:81`;
   `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/persistence/mongodb/OrderFulfillmentPersistenceAdapter.java:12`).
8. Il écrit `stock_movements` dans PostgreSQL
   (`InventoryApplicationService.java:83`;
   `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/persistence/jpa/StockMovementPersistenceAdapter.java:11`).
9. Branche de compensation : si l'écriture du mouvement échoue, le document
   MongoDB est supprimé puis l'exception est relancée
   (`InventoryApplicationService.java:82-86`).
10. Branche conditionnelle : si le stock restant vaut zéro, l'unique
    `StockDepletedPort` publie `StockDepleted` sur
    `supermarket.stock.depleted` (`InventoryApplicationService.java:98-100`;
    `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/messaging/KafkaStockDepletedAdapter.java:13`).

Alternatives terminales avant les écritures : requête invalide, produit absent
ou stock insuffisant. Elles deviennent respectivement HTTP 400, 404 ou 409 via
les handlers d'`InventoryController` (`InventoryController.java:19-24`).

## `java.controlled-error`

Entrée : `GET /api/error`. Provenance : `systemlens`, puis `source-assisted`.
Statut : potentiel. Confiance : moyenne.

1. `OrderController.error` crée une commande de quantité `999_999`
   (`order-service/src/main/java/io/systemlens/supermarket/order/OrderController.java:54-61`).
2. Le même appel proposé vers `POST /api/reservations` franchit la frontière
   HTTP (`OrderController.java:61`).
3. Si la cible runtime est `inventory-service`, le parcours rejoint
   `InventoryApplicationService.reserve` par l'unique `InventoryUseCase`.
4. `Product.reserve` lève `OutOfStockException` lorsque le stock est inférieur
   à la quantité (`inventory-service/src/main/java/io/systemlens/supermarket/inventory/domain/Product.java:18-23`).
5. `InventoryController` transforme cette exception en HTTP 409
   (`InventoryController.java:19-20`).
6. `order-service` intercepte l'erreur HTTP et lève son exception locale
   (`OrderController.java:62-65`), ensuite transformée en HTTP 500
   (`OrderController.java:69-72`).

Ce chemin décrit l'intention du code ; la disponibilité du service distant et
la valeur effective de l'URL restent des limites runtime.

## `java.online-order-fulfillment`

Entrée : tâche planifiée `ScheduledOrderPublisher.publishOnlineOrder`.
Provenance : `source-assisted`. Statut : potentiel. Confiance : moyenne.

1. Le scheduler crée un `OrderPlaced` puis le publie sur
   `supermarket.order.placed`
   (`order-service/src/main/java/io/systemlens/supermarket/order/ScheduledOrderPublisher.java:33-39`).
2. Frontière asynchrone Kafka : l'exécution producteur et l'exécution
   consommateur ne constituent pas une même trace garantie.
3. `KafkaOrderConsumer.consume` reçoit le message et appelle l'unique
   `InventoryUseCase.reserve` avec le canal `kafka`
   (`inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/in/messaging/KafkaOrderConsumer.java:18-24`).
4. Le parcours rejoint les étapes transactionnelles 5 à 10 de
   `java.checkout-reservation` : lecture/écriture `products`, écriture
   `order_fulfillments`, écriture `stock_movements`, compensation éventuelle
   et publication conditionnelle de `StockDepleted`.

Aucun retry, dead-letter topic ou mécanisme d'idempotence n'est explicite dans
le code Java inspecté ; une exception du listener termine donc l'analyse à la
frontière du conteneur Kafka.

## `java.stock-restock-cycle`

Entrée : branche `remainingStock == 0` d'une réservation réussie. Provenance :
`systemlens` pour le relais au sein de `restock-service`, puis
`source-assisted`. Statut : potentiel. Confiance : moyenne.

1. `inventory-service` publie `StockDepleted` sur
   `supermarket.stock.depleted` (`InventoryApplicationService.java:98-100` et
   `KafkaStockDepletedAdapter.java:13`).
2. Frontière asynchrone Kafka.
3. `StockDepletedConsumer.requestRestock` consomme l'événement, crée une
   demande de 500 unités et publie `StockRestockRequested` sur
   `supermarket.stock.restock-requested`
   (`restock-service/src/main/java/io/systemlens/supermarket/restock/StockDepletedConsumer.java:37-48`).
4. Nouvelle frontière asynchrone Kafka.
5. `KafkaStockRestockConsumer.consume` appelle l'unique
   `InventoryUseCase.restock`
   (`inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/in/messaging/KafkaStockRestockConsumer.java:18-24`).
6. Une frontière `@Transactional` commence sur `restock`; le service lit le
   produit, augmente le stock puis l'écrit dans `products`
   (`InventoryApplicationService.java:108-115`).

Le cycle est conditionnel : il n'est amorcé que par une réservation réussie
qui porte exactement le stock restant à zéro. Aucun retry ou dead-letter topic
n'est explicite dans les sources Java inspectées.

## Limites

- Les routes `GET /api/health` n'ont aucun effet externe et ne forment donc pas
  de flux utile selon ce profil.
- Les valeurs de configuration, le broker Kafka et les bases réellement
  atteints à l'exécution ne sont pas validés par cette passe Java.
- Les tests n'ont pas été utilisés comme preuve de production.
- Les enchaînements interservices et Kafka restent potentiels jusqu'à une
  corrélation par traces runtime.
