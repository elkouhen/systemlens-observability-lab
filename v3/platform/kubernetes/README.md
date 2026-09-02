# Kubernetes IaC

Ce répertoire est le point d'entrée déclaratif de la plateforme Kubernetes.

- `base/observability/` contient toutes les ressources Elastic,
  Fleet et la collecte des logs Kubernetes.
- `overlays/local/` décrit l'environnement POC local. Les futurs environnements
  (`recette`, `production`) seront des overlays distincts, sans duplication des
  ressources de base.

Installer ou mettre à jour ECK 3.5.0, puis déployer l'environnement local :

```bash
make eck-deploy
make elk-deploy
```

Traefik reste un prérequis de bootstrap du cluster. La cible
`elastic-stack-deploy`, appelée par `make elk-deploy`, installe ou met à jour la
release Helm `elastic-stack` avec Elasticsearch et Kibana `9.4.3`. Ses
valeurs d'installation sont versionnées dans
`platform/helm/eck-stack-values.yaml`; Elasticsearch est volontairement exclu
du bundle Kustomize pour éviter deux contrôleurs de cycle de vie sur la même
ressource. Les secrets ne sont pas stockés ici : ils doivent
être fournis par un gestionnaire de secrets (SOPS ou External Secrets) avant un
déploiement GitOps autonome.

Kibana utilise le registre public Elastic (`https://epr.elastic.co`) pour les
packages Fleet. Le cluster doit donc autoriser les connexions HTTPS sortantes
vers ce registre avant d’exécuter `make elk-deploy`.

Le service `otel-gateway` est exposé par l'hôte TLS
`otel-gateway-v3.observability.test`. Les applications Kubernetes l'utilisent
comme endpoint OTLP. Les logs et métriques Kubernetes suivent le chemin EDOT
vers Kafka. Les VM utilisent l'Elastic Agent enrôlé dans Fleet et publient
directement vers Elasticsearch.

Les URL fonctionnelles v3 utilisent les mêmes noms que v1 et v2 :
`elasticsearch.observability.test`, `kibana.observability.test` et `fleet.observability.test`. Fleet Server
n'est pas une interface web : la racine `/` peut répondre `404`. Pour vérifier
son état, utiliser `https://fleet.observability.test/api/status` ; une réponse `200`
confirme que le routage et le service sont opérationnels.

Pour un Elasticsearch déjà existant, la configuration de stockage ne doit pas
être ajoutée rétrospectivement : ECK interdit ce changement. Prévoir une
migration dédiée par snapshot/restauration vers un nouveau cluster avec ses
`volumeClaimTemplates` déclarés dès la création.
