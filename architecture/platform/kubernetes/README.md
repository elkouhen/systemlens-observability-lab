# Kubernetes IaC

Ce répertoire est le point d'entrée déclaratif de la plateforme Kubernetes.

- `base/observability/` contient les services Elastic publiés directement sur `elk-01` et les
  collecteurs Elastic EDOT Kubernetes pour les logs, métriques et traces.
- `overlays/local/` décrit l'environnement POC local. Les futurs environnements
  (`recette`, `production`) seront des overlays distincts, sans duplication des
  ressources de base.

Déployer l'environnement local :

```bash
make elk-deploy
```

Traefik reste un prérequis de bootstrap du cluster. La cible
`elastic-stack-deploy`, appelée par `make elk-deploy`, provisionne les unités
Quadlet Elasticsearch, Kibana et Fleet Server sur `elk-01`. Le manifeste
Kustomize contient les services externes et le routage Traefik optionnel vers
les ports publiés de `elk-01`. Les accès directs depuis l'environnement
opérateur utilisent les noms DNS résolus vers `192.168.33.40`.
`ELASTIC_PASSWORD` doit être fourni hors dépôt lors d'une installation neuve.

La licence et les identifiants du stack Quadlet sont gérés directement par
Elasticsearch sur `elk-01`.

Kibana utilise le registre public Elastic (`https://epr.elastic.co`) pour les
packages Fleet. Le cluster doit donc autoriser les connexions HTTPS sortantes
vers ce registre avant d’exécuter `make elk-deploy`. La cible
`fleet-registry-wait` vérifie cette connectivité depuis `elk-01` avant
l’installation des packages.

Le Collecteur EDOT Edge est référencé dans Kubernetes par le Service `otel-edge-vm`,
exposé sur les ports `4317` et `4318`. Les applications, le DaemonSet Kubernetes
et le collecteur cluster l'utilisent directement comme endpoint OTLP. Edge
publie ensuite les trois signaux dans le Kafka OTel de `otel-backend-01` et l'exporteur EDOT sur `otel-backend-01` les
écrit dans Elasticsearch ou APM Server. Les VM utilisent Elastic Agent en mode
EDOT et suivent le même chemin Edge, Kafka et Backend.

Les URL fonctionnelles de l’architecture utilisent les noms suivants :
`elasticsearch.observability.test`, `kibana.observability.test` et `fleet.observability.test`. Ces noms
résolvent directement vers `elk-01`; seul le service OTLP passe par `otel-edge-01`. Fleet Server
n'est pas une interface web : la racine `/` peut répondre `404`. Pour vérifier
son état, utiliser `http://fleet.observability.test:8220/api/status` ; une réponse `200`
confirme que l'accès direct et le service sont opérationnels.

Pour un Elasticsearch déjà existant, restaurer un snapshot dans le volume
`/var/lib/observability/elasticsearch` avant la mise en service de Fleet Server.
