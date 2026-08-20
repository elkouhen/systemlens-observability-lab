# Contrats partagés

Ce module contient les objets échangés entre `order-service` et
`inventory-service`. Il ne porte aucune configuration d'infrastructure : son
rôle est de stabiliser le format des messages Kafka et des appels REST utilisés
par les deux applications.

Lire d'abord le type `OrderPlaced` (identifiant de commande, produit, quantité,
horodatage), puis les producteurs et consommateurs qui l'utilisent dans les
deux modules voisins.

## Documentation externe

- [Modéliser des événements Kafka](https://kafka.apache.org/documentation/#design)
