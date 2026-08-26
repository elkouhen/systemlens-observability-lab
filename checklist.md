# Checklist de qualité et recette d'observabilité

Cette checklist permet de vérifier qu'une évolution respecte l'architecture
cible du POC et que les logs et métriques remontent jusqu'à Elastic. Cocher une
tâche uniquement après avoir exécuté le contrôle indiqué et constaté le résultat
attendu.

## Cohérence avec l'architecture cible

- [ ] La modification est placée dans le bon périmètre : `platform/` pour les
  composants transverses, `apps/` pour les workloads, `ansible/` pour les VM.
- [ ] Les manifests Kubernetes sont modifiés via une base ou un overlay
  Kustomize ; aucun YAML rendu n'est ajouté au dépôt.
- [ ] Les namespaces `elastic-stack` et `supermarket-demo`, les ressources ECK
  et les conventions de nommage existantes sont conservés.
- [ ] Les services `order-service` et `inventory-service` gardent leur agent
  Java Elastic APM, leurs logs JSON ECS sur `stdout` et leur environnement
  `homologation`.
- [ ] Aucun secret, mot de passe, clé API, token Fleet ou certificat privé
  n'est ajouté à Git.
- [ ] Les dépendances et le routage restent cohérents avec le flux cible :
  application Java -> APM Server / Elastic Agent Kubernetes -> Logstash ->
  Elasticsearch -> Kibana.

## Validation du code et des manifests

- [ ] Exécuter `make kubernetes-validate` ; les deux rendus Kustomize se
  terminent sans erreur.
- [ ] Exécuter `make apps-test` ; Maven termine avec succès pour tous les
  modules de `apps/supermarket-demo/`.
- [ ] Exécuter `make ci` ; la validation reproductible complète réussit.
- [ ] Exécuter `git diff --check` ; aucune erreur d'espaces n'est signalée.
- [ ] Vérifier que les versions Maven, tags Docker et références de manifests
  restent alignés lorsqu'ils sont modifiés.
- [ ] Mettre à jour le README le plus proche si le déploiement, un prérequis,
  une variable ou une méthode de vérification a changé.

## Recette après déploiement ciblé

- [ ] Déployer uniquement le périmètre touché avec la cible `make` appropriée
  (par exemple `make elk-deploy`, `make apps-deploy` ou
  `make apm-logstash-deploy`).
- [ ] Exécuter `make kubernetes-status` ; Elasticsearch, Kibana, APM Server,
  Elastic Agent et les pods applicatifs sont disponibles.
- [ ] Si les VM sont concernées, exécuter `make vm-status` ; MongoDB, Kafka et
  PostgreSQL attendus sont actifs.
- [ ] Déclencher une transaction applicative avec `make order-service-command`
  et constater une réponse HTTP réussie.
- [ ] Vérifier les logs des services avec `make order-service-logs-follow` ou
  `make inventory-service-logs-follow` ; les événements sont au format ECS et
  ne présentent pas d'erreur récurrente.

## Remontée des logs et métriques

- [ ] Dans Kibana Discover, confirmer l'arrivée récente de logs applicatifs
  dans `logs-kubernetes.container_logs-homologation`, avec
  `service.environment: homologation` et l'identité du service attendue.
- [ ] Dans Kibana Discover, confirmer l'arrivée récente de métriques APM Java
  dans `metrics-apm.app.kubernetes-homologation` pour les deux services.
- [ ] Dans Observability > APM, confirmer que `order-service` et
  `inventory-service` reçoivent transactions, erreurs éventuelles et métriques
  JVM après la transaction de recette.
- [ ] Vérifier les logs de `apm-logstash` ; aucune erreur persistante de
  connexion, d'authentification ou d'indexation n'est présente.
- [ ] Exécuter `make dashboards-verify` après une évolution de collecte ou de
  dashboard ; les jeux de données attendus sont récents.
- [ ] Consulter les dashboards de supervision utilisés et vérifier que chacun
  affiche des données récentes, avec les filtres `service.environment`,
  `service.name` et `host.name` adaptés : **[Metrics System] Overview**,
  **[Metrics Kubernetes] Cluster Overview**, **Nodes**, **Deployments** et
  **Pods**, **[Metrics Kafka] Overview**, **[Metrics MongoDB] Overview**,
  **SystemLens · MongoDB clusters**, **[Metrics PostgreSQL] Database
  Overview**, **[Elastic Agent] Agent metrics** et Observability > APM >
  Services. Pour PostgreSQL, ne retenir que `data-01`.
- [ ] Si Fleet ou Beats est modifié, confirmer dans Kibana que les agents Fleet
  de `data-01` et `data-02` sont sains, et que Filebeat et Metricbeat sont
  actifs sur `data-03`.

## Livraison

- [ ] Documenter dans le commit ou la pull request les commandes réellement
  exécutées et leurs résultats.
- [ ] Vérifier `git status --short --branch` avant le commit : seuls les
  fichiers attendus sont présents.
