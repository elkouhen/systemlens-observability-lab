# Première démonstration : suivre une commande de bout en bout

Ce tutoriel s'adresse à une personne technique qui découvre un environnement
déjà déployé. En moins de dix minutes, vous allez générer une commande puis
constater son effet dans les logs, les métriques et les traces.

## Résultat attendu

À la fin, Kibana affiche des documents récents pour `order-service` et
`inventory-service`. La commande a produit une trace distribuée, des logs de
pods Kubernetes et, après l'intervalle de collecte, des métriques associées aux
services et à l'infrastructure.

## Prérequis

- Le déploiement est terminé ; pour le créer, suivre le [README du dépôt](../../../README.md).
- `kubectl`, `curl` et l'accès à Kibana sont disponibles depuis le poste hôte.
- Les pods applicatifs sont prêts. Vérifier d'abord :

  ```bash
  make platform-status
  kubectl -n supermarket-demo get pods
  ```

  Les deux pods applicatifs doivent être `Running` et prêts (`1/1`).

## 1. Ouvrir temporairement l'application

Dans un premier terminal, transférer le port du service de commande :

```bash
kubectl -n supermarket-demo port-forward service/order-service 8080:3000
```

Laisser cette commande en cours d'exécution. Elle expose seulement le service
localement sur `127.0.0.1:8080` et ne modifie pas le déploiement.

## 2. Générer une commande

Dans un second terminal, envoyer une commande avec un produit du catalogue :

```bash
curl --fail --show-error \
  -X POST http://127.0.0.1:8080/api/orders \
  -H 'Content-Type: application/json' \
  --data '{"productId":"PASTA-500G","quantity":1}'
```

Une réponse JSON contenant notamment `orderId`, `productId` et
`remainingStock` confirme le chemin HTTP synchrone entre les deux services.
Pour produire volontairement une erreur observable, appeler ensuite
`http://127.0.0.1:8080/api/error` ; une réponse HTTP 500 est attendue.

## 3. Vérifier les données dans Kibana

Ouvrir Kibana, sélectionner une période incluant les cinq dernières minutes,
puis utiliser Discover :

1. Dans le data view `logs-*`, rechercher
   `kubernetes.namespace : "supermarket-demo"`. Des logs des deux pods doivent
   apparaître avec des métadonnées Kubernetes et, lorsque présentes, les champs
   `trace.id` et `span.id`.
2. Dans `traces-*`, rechercher
   `service.name : ("order-service" or "inventory-service")`. Ouvrir une trace
   récente : elle doit montrer le traitement de la commande et ses dépendances.
3. Dans `metrics-*`, rechercher
   `service.name : ("order-service" or "inventory-service")`. Attendre au moins
   deux intervalles de collecte avant de conclure qu'une métrique manque.

Les noms des data streams et les champs à contrôler sont récapitulés dans les
[matrices des dashboards](../../systeme/dashboards.md) et des
[métriques](../../systeme/metriques-sources.md).

## Si un résultat manque

Ne modifiez pas encore les configurations. Suivez d'abord le guide
[Vérifier un signal de bout en bout](../../systeme/how-to/verifier-un-signal.md), puis le
guide [Diagnostiquer un dashboard vide](../../systeme/how-to/diagnostiquer-dashboard-vide.md).
