# Contrats partagés

Ce module contient les objets échangés entre le producteur et le worker. Il ne
porte aucune configuration d'infrastructure : son rôle est de stabiliser le
format des messages Kafka utilisé par les deux applications.

Lire d'abord le type `WorkRequested`, puis les producteurs et consommateurs
qui l'utilisent dans les deux modules voisins.

## Documentation externe

- [Modéliser des événements Kafka](https://kafka.apache.org/documentation/#design)
