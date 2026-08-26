# Contrats partagés

Ce module contient les objets échangés entre `order-service`,
`inventory-service` et `restock-service`. Il ne porte aucune configuration
d'infrastructure : son rôle est de stabiliser le format des messages Kafka et
des appels REST utilisés par les applications.

Lire d'abord le type `OrderPlaced` (identifiant de commande, produit, quantité,
horodatage), puis `StockDepleted` et `StockRestockRequested` pour le flux de
réassort asynchrone.

## Documentation externe

- [Modéliser des événements Kafka](https://kafka.apache.org/documentation/#design)
