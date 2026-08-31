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

Traefik reste un prérequis de bootstrap du cluster. La cible `make
elastic-stack-v2-deploy`, appelée par `make elk-deploy`, installe ou met à jour la
release Helm `es-kb-quickstart` avec Elasticsearch et Kibana `9.4.3`. Ses
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
`otel-gateway-v2.poc.test`. Les VM l'utilisent comme endpoint OTLP ; leur EDOT
Collector fonctionne en mode agent et ne se connecte pas à Fleet.

Pour un Elasticsearch déjà existant, la configuration de stockage ne doit pas
être ajoutée rétrospectivement : ECK interdit ce changement. Prévoir une
migration dédiée par snapshot/restauration vers un nouveau cluster avec ses
`volumeClaimTemplates` déclarés dès la création.
