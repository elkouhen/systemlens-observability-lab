# Supermarché en ligne — démonstration observabilité

Ce POC simule le système d'information d'un supermarché avec deux
microservices Spring Boot : `order-service` gère la prise de commande
(caisse et commandes en ligne) et `inventory-service` gère le stock du
catalogue. Le Dockerfile produit une image pour chacun.

## Scénario métier

- **`order-service`** expose `POST /api/orders` (commande passée en caisse :
  produit + quantité) et appelle `inventory-service` de façon synchrone via
  REST pour réserver le stock. Il publie aussi, toutes les minutes, une
  commande aléatoire du catalogue sur Kafka, pour simuler les commandes
  passées en ligne et traitées en tâche de fond.
- **`inventory-service`** consomme ces commandes (Kafka pour le flux en ligne,
  REST pour la caisse), vérifie le stock du produit dans son catalogue
  PostgreSQL, le décrémente, puis journalise la commande dans MongoDB
  (`order_fulfillments`) et dans le registre PostgreSQL (`stock_movements`).
  Si le stock est insuffisant, une rupture de stock (HTTP 409) est renvoyée.
- `GET /api/error` sur `order-service` déclenche volontairement une commande
  dont la quantité dépasse toujours le stock disponible, pour observer la
  propagation d'une erreur métier (rupture de stock) entre les deux services.

## Ordre de lecture

1. `pom.xml` : agrégateur Maven et versions communes.
2. `Dockerfile` : build multi-stage, avec l'agent Java Elastic APM pour les
   deux services.
3. [`kubernetes/README.md`](kubernetes/README.md) : variables de déploiement
   et raccordement d'`order-service` à APM Server et d'`inventory-service` à
   APM Server.
4. `order-service/src/main/resources/application.yml`, puis la même
   configuration d'`inventory-service` : endpoints, Kafka, MongoDB,
   PostgreSQL et Actuator.
5. Le code des deux modules pour le flux métier (`order-service/.../order`,
   `inventory-service/.../inventory`).

Construire les deux images avec `make apps-build`, puis déployer uniquement
l'application avec `make apps-deploy`.

Pour déclencher une commande de recette via le service Kubernetes, exécuter
`make order-service-command`. La cible crée un pod `curl` éphémère, appelle
`POST /api/orders`, affiche la réservation et supprime le pod. Les variables
`ORDER_PRODUCT_ID` et `ORDER_QUANTITY` permettent d'adapter la commande, par
exemple :

```bash
make order-service-command ORDER_PRODUCT_ID=PASTA-500G ORDER_QUANTITY=2
```

## Documentation externe

- [Agent Java Elastic APM](https://www.elastic.co/docs/reference/apm/agents/java)
- [Spring Boot Actuator](https://docs.spring.io/spring-boot/reference/actuator/)

## Versions d'images

Le build Maven est figé sur `maven:3.9.9-eclipse-temurin-21` et les images
d'exécution sur `eclipse-temurin:21.0.7_6-jre-noble`. Toute mise à jour doit
être testée puis effectuée dans une modification dédiée.

Le tag des images Docker (`order-service:1.0.8` / `inventory-service:1.0.8`,
fixé dans `Makefile` et `kubernetes/deployment.yaml`) est géré indépendamment
de `<version>` dans les `pom.xml` (actuellement `1.0.0`, partagée par les trois
modules Maven). Le tag Docker identifie une itération de l'image de
démonstration ; la version Maven identifie une itération du code Java. Un tag
Docker est immuable : choisir un nouveau `APP_IMAGE_TAG` à chaque image. Par
exemple, `make apps-build APP_IMAGE_TAG=1.0.8`, puis
`make images-import apps-deploy APP_IMAGE_TAG=1.0.8`. La cible de déploiement
met explicitement à jour l'image des Deployments et attend leur rollout.
