# Revue des différences de code v1/v2

## Objet de la revue

Ce document compare les bundles `v1/` et `v2/` afin d'identifier les
différences nécessaires à leur rôle respectif et les duplications qui pourraient
être mutualisées. La cible est de conserver deux chaînes Elastic distinctes
quand cela est indispensable, tout en partageant autant que possible le code
d'infrastructure, les templates et les manifests applicatifs.

La comparaison porte sur l'état du dépôt au moment de la revue. Les répertoires
`.vagrant/` et les fichiers générés ne sont pas considérés comme du code
source.

## Synthèse

| Domaine | v1 | v2 | Écart nécessaire ? | Recommandation |
| --- | --- | --- | --- | --- |
| Version Elastic | Stack 8.11.3 | Stack 9.4.3 | Oui | Garder les valeurs de version dans des variables propres à l'architecture. |
| Collecte VM | Filebeat + Metricbeat | EDOT Collector agent | Oui | Mutualiser le provisionnement système et séparer uniquement les templates de collecte. |
| Transport VM | Logstash `5045` | Kafka `otel-logs` / `otel-metrics` | Oui | Garder deux backends, partager les contrôles de service et les conventions de labels. |
| APM applicatif | Agent Elastic APM → APM Server | Agent OTel → Gateway EDOT → Kafka | Oui | Mutualiser les déploiements Java ; isoler les variables d'export et l'instrumentation. |
| Logs Kubernetes | Elastic Agent → Logstash | EDOT DaemonSet → Kafka | Oui | Mutualiser les workloads et conserver deux overlays de télémétrie. |
| Données VM | Kafka/MongoDB/PostgreSQL sur `data-01` | Même topologie minimale | Non | Partager les templates Podman et les variables de topologie. |
| Application | Manifest presque dupliqué | Manifest presque dupliqué + `Instrumentation` OTel | Partiellement | Créer une base applicative commune et limiter les overlays aux endpoints. |
| Tests/diagnostics | Scripts et cibles similaires | Scripts et cibles similaires | Non | Déplacer les scripts communs au niveau racine ou dans un module partagé. |

La principale divergence justifiée est le protocole de télémétrie. La principale
dette est la duplication des fichiers `Makefile`, `Vagrantfile`, Ansible et des
manifests applicatifs.

## Différences par zone du dépôt

### 1. Orchestration locale

Fichiers concernés :

- [`v1/Makefile`](v1/Makefile) / [`v2/Makefile`](v2/Makefile)
- [`v1/Vagrantfile`](v1/Vagrantfile) / [`v2/Vagrantfile`](v2/Vagrantfile)
- [`v1/README.md`](v1/README.md) / [`v2/README.md`](v2/README.md)

Les deux Makefiles exposent les mêmes familles de cibles : validation,
déploiement Elastic, provisionnement VM, déploiement applicatif et contrôles.
Ils divergent cependant sur les dépendances de déploiement et les secrets :

- v1 doit créer les secrets nécessaires à APM Server et Logstash avant leur
  réconciliation ECK ;
- v2 doit créer la VM avant le Job Kafka, car le backend OTel Kubernetes attend
  les topics `otel-traces`, `otel-metrics` et `otel-logs` ;
- v1 expose les cibles historiques Beats/Logstash ; v2 expose les cibles EDOT
  et conserve certaines cibles APM/Logstash comme compatibilité.

Le `Vagrantfile` est structurellement très proche : box Rocky, réseau privé,
ports Jolokia/JMX, variables PostgreSQL, certificat Zscaler et provisionnement
Ansible. La différence de collecte ne justifie pas de dupliquer toute cette
logique.

**Convergence proposée**

1. Créer un module ou un fichier de variables commun pour : box, réseau,
   ports, mémoire, CPU, certificats et variables secrètes.
2. Garder dans chaque bundle uniquement le nom du collecteur, ses ports et la
   commande de provisionnement spécifique.
3. Définir un contrat commun de cibles Make : `kubernetes-validate`,
   `ansible-validate`, `vm-provision`, `vm-status`, `apps-deploy` et `deploy`.
4. Éviter les cibles présentes dans `.PHONY` mais sans implémentation, ou les
   déplacer dans le bundle qui les supporte réellement.

### 2. Provisionnement Ansible des VM

Fichiers concernés :

- [`v1/ansible/site.yml`](v1/ansible/site.yml) /
  [`v2/ansible/site.yml`](v2/ansible/site.yml)
- [`v1/ansible/status.yml`](v1/ansible/status.yml) /
  [`v2/ansible/status.yml`](v2/ansible/status.yml)
- inventaires et README associés sous `v1/ansible/` et `v2/ansible/`

Le socle est commun : réseau NetworkManager, DNS, certificats CA, paquets,
chrony, Podman, limites système, conteneurs MongoDB/Kafka/PostgreSQL et
vérifications de disponibilité.

Les différences fonctionnelles sont :

- v1 installe et configure Filebeat/Metricbeat et leurs unités systemd ;
- v2 installe `poc-otel-agent`, déploie `otel-agent.yml` et configure une file
  persistante OTel ;
- v1 conserve des branches historiques `poc_distributed` dans Ansible et des
  profils applicatifs distribués, alors que la topologie opérationnelle v1 est
  minimale ;
- v2 a été simplifiée pour `data-01`, Kafka mono-broker et MongoDB standalone.

**Convergence proposée**

- mutualiser les tâches système jusqu'à la création des conteneurs Podman ;
- utiliser une variable `observability_collector` (`beats` ou `edot`) pour
  sélectionner les tâches de collecte ;
- mutualiser le contrôle des ports, des services et des logs systemd ;
- supprimer les branches distribuées mortes des deux bundles si la décision
  produit reste « une seule VM » ;
- ne jamais faire dépendre `site.yml` d'un fichier généré dans `.vagrant/`.

### 3. Templates de services et de collecte

Fichiers concernés :

- v1 : `ansible/templates/beat.service.j2`,
  `filebeat.yml.j2`, `metricbeat.yml.j2` ;
- v2 : `ansible/templates/poc-otel-agent.service.j2`,
  `otel-agent.yml.j2` ;
- les templates communs Kafka, MongoDB et PostgreSQL dans chaque bundle.

Le service systemd est conceptuellement le même : démarrage après le réseau,
redémarrage en cas d'échec, exécution en root et activation au boot. Le
contenu de la collecte ne doit pas être fusionné, car les agents et les
protocoles sont différents.

Les deux versions peuvent néanmoins partager :

- les chemins de logs observés ;
- les noms des services de données ;
- les attributs d'environnement et d'hôte ;
- les règles de permissions et de persistance ;
- les tests de santé et les messages opérateur.

La v2 utilise les receivers `hostmetrics`, `kafka_metrics`, `mongodb`,
`postgresql` et `filelog/vm`, puis publie dans Kafka. La v1 utilise les
intégrations Metricbeat/Filebeat, puis Logstash. Cette différence est la
frontière naturelle entre un template commun de service et deux templates de
collecte.

### 4. Kubernetes et chaîne Elastic

Fichiers v1 uniquement :

- `apm-server.yaml` ;
- `apm-logstash.yaml` ;
- `kubernetes-logs-agent.yaml` ;
- `kube-state-metrics.yaml` ;
- `bootstrap/`.

Fichier v2 uniquement :

- [`v2/platform/kubernetes/base/observability/otel-kafka.yaml`](v2/platform/kubernetes/base/observability/otel-kafka.yaml).

Ces différences sont nécessaires. Elles correspondent à deux chaînes de
transport incompatibles :

```text
v1 : agents Elastic → Logstash → Elasticsearch
v2 : EDOT/OTel → Kafka → EDOT Collector → Elasticsearch
```

Le socle peut être partagé ou paramétré : namespace, Ingress TLS, valeurs ECK,
Kibana, RBAC, certificats et conventions de data streams. Les manifests ECK
doivent toutefois rester séparés tant que les versions Elastic et les
ressources APM ne sont pas alignées.

**Point de vigilance** : la documentation et certains manifests historiques
mentionnent encore des profils distribués, des brokers supplémentaires ou
Logstash dans des chemins v2. Toute référence de ce type doit être classée
comme dette de synchronisation et supprimée ou explicitement marquée comme
documentation historique.

### 5. Manifests de l'application

Fichiers concernés :

- `v1/apps/supermarket-demo/kubernetes/base/deployment.yaml` ;
- `v2/apps/supermarket-demo/kubernetes/base/deployment.yaml` ;
- `v1/apps/.../kubernetes-profiles/minimal/data-endpoints.yaml` ;
- `v2/apps/.../kubernetes-profiles/minimal/data-endpoints.yaml`.

Les trois Deployments Java, leurs probes, leurs ressources, leurs noms de
service et la configuration métier sont presque identiques. Les divergences
principales sont les endpoints :

| Élément | v1 | v2 |
| --- | --- | --- |
| APM | `apm-server-apm-http` et token APM | Gateway OTel et `Instrumentation` |
| Kafka depuis les pods | `192.168.33.10:9092` | passerelle Docker `192.168.5.2:19092` |
| MongoDB | URI VM selon le bundle | MongoDB standalone avec `directConnection=true` |
| Logs | collectés par l'agent Kubernetes v1 | collectés par le DaemonSet EDOT |
| Métriques applicatives | chemin APM/Logstash | OTLP vers le Gateway puis Kafka |

La duplication du `deployment.yaml` est la meilleure cible de mutualisation.
Le manifest commun devrait contenir les Deployments, probes, ports, images et
configuration métier. Les overlays v1/v2 ne devraient fournir que :

- endpoints Kafka et MongoDB ;
- variables APM/OTel ;
- namespace ;
- secrets et certificats ;
- labels de version de stack.

Il faut éviter de conserver simultanément une configuration APM inline dans
les Deployments v2 et une configuration équivalente dans
[`otel-instrumentation.yaml`](v2/apps/supermarket-demo/kubernetes/base/otel-instrumentation.yaml)
sans documenter précisément la priorité d'injection.

### 6. Scripts et diagnostics

Les scripts `load-credentials.sh`, `provision-fleet-vms.sh`,
`sync-fleet-policies.sh`, `verify-dashboard-data.sh` et les scripts de statut
sont très proches mais ne ciblent pas les mêmes composants.

À mutualiser :

- lecture sûre des Secrets Kubernetes ;
- gestion des erreurs HTTP et des retries ;
- vérification de présence des commandes ;
- format des messages opérateur ;
- fonctions `kubectl` et `curl` communes.

À garder spécifique :

- création de la clé API Logstash v1 ;
- synchronisation des pipelines EDOT/Kafka v2 ;
- import du data view APM selon les versions Kibana ;
- contrôles des topics OTLP v2 et du port Logstash v1.

## Divergences à corriger en priorité

### Priorité haute

1. **Ordre de déploiement VM/Kafka v2** : la VM doit être opérationnelle avant
   la création du Job `otel-telemetry-topics-v3`. Cet ordre est désormais porté
   par `v2/Makefile` et doit rester testé.
2. **Endpoint Kafka v2** : les consommateurs Kubernetes doivent utiliser le
   listener accessible depuis le réseau Docker/k3d, tandis que l'Agent VM
   utilise le listener privé local. Ces deux usages ne doivent pas être
   reconfondus dans un endpoint unique.
3. **Profils distribués** : retirer les branches distribuées restantes des
   fichiers source v1/v2 si elles ne sont plus supportées, notamment les
   profils Kustomize, les conditions Ansible et les inventaires.
4. **Manifest applicatif commun** : réduire la copie des trois Deployments, qui
   rend les corrections de probes, d'images et de sécurité difficiles à
   reporter d'une version à l'autre.

### Priorité moyenne

1. Mutualiser le socle Ansible et les templates Kafka/MongoDB/PostgreSQL.
2. Mutualiser les fonctions shell de credentials, retries et diagnostics.
3. Ajouter une validation qui compare les noms de services, namespaces,
   endpoints et secrets attendus dans les deux bundles.
4. Maintenir les README v1/v2 et le document racine après chaque modification
   de topologie ; le README racine contient encore des formulations historiques
   qui ne reflètent pas complètement la v2 minimale.

### Priorité basse

1. Harmoniser les noms de variables (`APP_IMAGE_TAG`, URLs, ports et noms de
   namespaces) lorsque cela ne masque pas une différence de version.
2. Harmoniser les messages et les cibles `Makefile`.
3. Réduire les différences de style YAML et de commentaires entre les copies.

## Proposition de structure cible

```text
shared/
  ansible/tasks/system.yml
  ansible/templates/poc-kafka.container.j2
  ansible/templates/poc-mongodb.container.j2
  ansible/templates/poc-postgresql.container.j2
  kubernetes/apps/supermarket-demo/base/
  scripts/credentials.sh
  scripts/cluster-status.sh

v1/
  Makefile
  platform/kubernetes/       # Elastic 8 + APM Server + Logstash
  ansible/collector-beats/   # Filebeat + Metricbeat
  kubernetes/apps-overlay/

v2/
  Makefile
  platform/kubernetes/       # Elastic 9 + EDOT + Kafka OTLP
  ansible/collector-edot/    # EDOT Agent
  kubernetes/apps-overlay/
```

Une étape intermédiaire moins invasive consiste à garder l'arborescence
actuelle et à introduire seulement des fichiers communs sous `shared/`, puis à
faire consommer ces fichiers par les deux bundles. Il faut éviter les
symlinks de configuration Kubernetes si l'outil de déploiement ou le contexte
de build ne les gère pas de manière uniforme.

## Méthode de validation recommandée

Après chaque convergence de code :

```bash
make -C v1 kubernetes-validate
make -C v2 kubernetes-validate
make -C v1 ansible-validate
make -C v2 ansible-validate
git diff --check
```

Puis vérifier séparément les deux chaînes de données :

- v1 : Beat → Logstash → data stream Elasticsearch ;
- v2 : EDOT Agent/DaemonSet → Kafka → EDOT Collector → data stream
  Elasticsearch.

Une mutualisation n'est acceptable que si elle conserve ces deux parcours
explicitement vérifiables dans Kibana Discover.

## Conclusion

Il ne faut pas chercher à rendre identiques les composants de collecte v1 et
v2 : leurs protocoles et leurs responsabilités sont différents. En revanche,
le provisionnement des VM, les services Podman, le socle applicatif, les
validations et les utilitaires d'exploitation peuvent être fortement
mutualisés. La première évolution recommandée est un manifest applicatif
commun, suivie d'un socle Ansible partagé. Les fichiers spécifiques Logstash
v1 et EDOT/Kafka v2 doivent rester isolés et documentés comme les deux
implémentations de la même interface de télémétrie.
