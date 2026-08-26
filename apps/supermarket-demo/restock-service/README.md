# Module restock-service : réassort asynchrone

Ce microservice consomme l'événement Kafka `supermarket.stock.depleted` et
publie une demande de 500 unités sur
`supermarket.stock.restock-requested`. Il ne lit ni n'écrit dans les bases de
données : `inventory-service` reste propriétaire du catalogue PostgreSQL et
applique la demande de réassort.

Le module est instrumenté par l'agent Java Elastic APM dans le Dockerfile
parent. Ses logs ECS sur `stdout` permettent de suivre l'épuisement et le
réassort d'un produit dans Kibana.

Vérifier le module avec l'ensemble du projet :

```bash
make apps-test
```
