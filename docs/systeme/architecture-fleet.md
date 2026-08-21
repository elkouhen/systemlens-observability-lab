# Architecture Fleet

Fleet sépare le **pilotage** des collecteurs Elastic de la **collecte** elle-même.
Il ne remplace ni Elasticsearch ni les intégrations : il distribue une
configuration centralisée aux Elastic Agents.

## Les composants

| Composant | Rôle | Présence dans le POC |
| --- | --- | --- |
| Kibana avec Fleet | interface et API de gestion : packages, policies, tokens et état des agents | Kubernetes, géré par ECK |
| Fleet Server | point de contact des Elastic Agents : enrôlement, remise des policies et suivi d'état | Kubernetes, géré par ECK |
| Elastic Agent | exécute les inputs reçus dans une policy et envoie les données | uniquement sur la **VM Elastic Agent** |
| Agent policy | ensemble versionné d'intégrations et de leur configuration | policy `mongodb-hosts` dans la configuration Kibana |
| Package policy | instance d'une intégration dans une agent policy, par exemple System, MongoDB ou Kafka | déclarée dans l'agent policy |
| Output | destination des données et du monitoring de l'Agent | Elasticsearch |

Un Fleet Server n'est donc pas « un Fleet par VM ». Il y a un Fleet Server
central, puis un Elastic Agent sur chaque hôte auquel on veut appliquer une
policy Fleet. Dans l'architecture cible, seule la VM Elastic Agent en exécute
un ; les VM OpenTelemetry et Beats n'ont pas d'Elastic Agent actif.

## Chemin de contrôle et chemin de données

```text
                    création des policies, packages et tokens
Kibana / Fleet API ───────────────────────────────────────────────┐
       │                                                          │
       │ policy Fleet Server                                      ▼
       ├──────────────> Fleet Server <──── enrôlement / contrôle ─ Elastic Agent
       │                    │                                        (VM Elastic Agent)
       │                    │ état et configuration                         │
       ▼                    ▼                                               │ données
Elasticsearch <──────── Fleet Server                         Elasticsearch
     (interne)                                                (output Agent)
```

- La communication Agent → Fleet Server est le **plan de contrôle** : elle sert
  à l'enrôlement, aux politiques, aux mises à jour et au statut.
- La communication Agent → Elasticsearch est le **plan de données** : les logs
  et métriques ne transitent pas normalement par Fleet Server.
- Fleet Server utilise l'output Elasticsearch interne du cluster ; l'Agent de
  la VM utilise l'output Elasticsearch déclaré pour les agents externes.

## Création dans ce dépôt

L'ordre de création est important :

1. ECK déploie Elasticsearch et Kibana.
2. La ressource Kibana préconfigure Fleet : URL publique du Fleet Server,
   outputs, packages requis, policy du Fleet Server et policy de la VM Elastic
   Agent. Cette configuration est dans
   [`platform/kubernetes/base/observability/kibana.yaml`](../platform/kubernetes/base/observability/kibana.yaml).
3. ECK crée le Fleet Server à partir d'une ressource `Agent` en `mode: fleet`,
   avec `fleetServerEnabled: true`. Cette ressource est dans
   [`platform/kubernetes/base/observability/fleet-server.yaml`](../platform/kubernetes/base/observability/fleet-server.yaml).
4. Traefik publie le service HTTPS Fleet Server afin que la VM Elastic Agent
   puisse s'y enrôler. La route est déclarée dans
   [`platform/kubernetes/base/observability/elastic-ingress.yaml`](../platform/kubernetes/base/observability/elastic-ingress.yaml).
5. Un token d'enrôlement est créé dans Kibana pour la policy de la VM Elastic
   Agent et fourni temporairement via `FLEET_ENROLLMENT_TOKEN` lors du
   provisionnement.
6. Ansible installe et enrôle Elastic Agent uniquement sur la VM Elastic Agent.
   L'Agent récupère alors ses intégrations System, MongoDB et Kafka.

`make kibana-fleet-config-deploy` applique la configuration Kibana/Fleet.
`make fleet-sync` synchronise les policies dont la mise à jour exige l'API
Fleet, ainsi que les pipelines Elasticsearch complémentaires.

## Pourquoi créer Fleet Server avec ECK ?

ECK gère le cycle de vie du pod, les certificats, les références vers Kibana et
Elasticsearch, ainsi que la configuration de l'Agent qui porte Fleet Server.
Le Fleet Server est ainsi proche de Kibana et Elasticsearch, sans installer un
serveur de contrôle manuel sur une VM. Les VM ne doivent connaître que son URL
HTTPS publique et le certificat de confiance associé.

Dans ce POC, une seule réplique suffit à l'apprentissage. En production, il
faut dimensionner et répliquer Fleet Server selon le nombre d'Agents, prévoir
un équilibrage de charge et tester la rotation des certificats et tokens.

## Contrôles de recette

```bash
# Ressource ECK et pod Fleet Server
kubectl -n elastic-stack get agent fleet-server
kubectl -n elastic-stack get pods -l agent.k8s.elastic.co/name=fleet-server

# Côté VM Elastic Agent
sudo systemctl status elastic-agent
sudo /opt/Elastic/Agent/elastic-agent status
```

Dans Kibana, ouvrir **Management > Fleet > Agents** : la VM Elastic Agent doit
être `Healthy` et rattachée à la policy attendue. Les VM OpenTelemetry et Beats
ne doivent pas être attendues dans cette vue ; si elles y figurent après une
ancienne installation, elles peuvent rester historiques et `Offline`, mais leur
service doit être arrêté.

## Limites et décisions

- Fleet est utile lorsqu'on veut administrer centralement Elastic Agent et les
  intégrations Elastic ; il n'est pas requis par EDOT ni par les Beats.
- Une même source ne doit pas être collectée à la fois par Fleet et par EDOT ou
  Metricbeat sur un même hôte.
- Les packages préconfigurés par Kibana ne mettent pas toujours à jour une
  package policy déjà créée. Le script de synchronisation remplace explicitement
  les policies MongoDB et Kafka du rôle Elastic Agent pour appliquer les
  changements versionnés.

## Références

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Déployer Fleet Server avec ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/configuration-fleet)
- [Modèles de déploiement Fleet](https://www.elastic.co/docs/reference/fleet/deployment-models)
