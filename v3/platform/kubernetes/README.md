# Kubernetes IaC

Ce répertoire est le point d'entrée déclaratif de la plateforme Kubernetes.

- `base/observability/` contient le routage Traefik vers `elk-01` via `edge-01` et les
  collecteurs Kubernetes pour les logs et métriques Prometheus.
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
Kustomize ne contient que les services externes et le routage Traefik vers les
ports publiés de cette VM. `ELASTIC_PASSWORD` doit être fourni hors dépôt lors
d'une installation neuve.

Le manifeste historique `eck-trial-license.yaml` n'est plus utilisé par la v3.
La licence et les identifiants du stack Quadlet sont gérés directement par
Elasticsearch sur `elk-01`.

Kibana utilise le registre public Elastic (`https://epr.elastic.co`) pour les
packages Fleet. Le cluster doit donc autoriser les connexions HTTPS sortantes
vers ce registre avant d’exécuter `make elk-deploy`.

Le Gateway OTLP est exécuté sur la VM `otel-backend-01`, derrière HAProxy sur `edge-01`, publié aux
conteneurs k3d via `192.168.33.30:4317` et `192.168.33.30:4318`. Les applications
Kubernetes l'utilisent comme endpoint OTLP. Les applications exportent leurs
métriques Micrometer directement en OTLP ; le DaemonSet conserve la collecte des logs et des
métriques Kubernetes suivent le chemin EDOT vers Kafka, puis l'exporteur EDOT
sur `otel-backend-01` les écrit dans Elasticsearch. Les VM utilisent l'Elastic Agent
enrôlé dans Fleet et publient directement vers Elasticsearch.

Les URL fonctionnelles v3 utilisent les mêmes noms que v1 et v2 :
`elasticsearch.observability.test`, `kibana.observability.test` et `fleet.observability.test`. Fleet Server
n'est pas une interface web : la racine `/` peut répondre `404`. Pour vérifier
son état, utiliser `https://fleet.observability.test/api/status` ; une réponse `200`
confirme que le routage et le service sont opérationnels.

Pour un Elasticsearch déjà existant, restaurer un snapshot dans le volume
`/var/lib/observability/elasticsearch` avant la mise en service de Fleet Server.
