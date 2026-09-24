# Spécification du déploiement EDOT standalone supervisé par OpAMP

Cette spécification définit l’ordre de déploiement, les invariants d’idempotence et les contrôles d’acceptation de la plateforme d’observabilité.

|                |                                            |
| -------------- | ------------------------------------------ |
| **Statut**     | Proposition de référence                   |
| **Propriétaire** | Équipe plateforme et observabilité       |
| **Périmètre**  | VM, Fleet, agents EDOT standalone, Kubernetes, applications et Kibana |
| **Hors périmètre** | Gestion des secrets externes, publication distante et règles d’alerte métier |
| **Audience**   | Opérateurs, développeurs plateforme et mainteneurs du POC |
| **Documents liés** | [`ansible/README.md`](../ansible/README.md), [`platform/elk/fleet/README.md`](../platform/elk/fleet/README.md), [`platform/elk/dashboards/README.md`](../platform/elk/dashboards/README.md) |

## 1. Résumé

Le déploiement sépare le plan de contrôle Fleet du chemin de données EDOT. Les agents installés dans les VM restent standalone. Fleet les supervise via OpAMP, tandis que les logs, métriques et traces suivent leur configuration EDOT vers le Collecteur Edge, Kafka, le backend OTel et Elasticsearch.

Le déploiement accepté suit cet ordre :

1. préparer les variables et les secrets locaux ;
2. déployer les VM et l’agent EDOT standalone ;
3. préparer Elasticsearch, Kibana, Fleet, les packages et les clés OpAMP ;
4. configurer et vérifier l’enregistrement OpAMP des agents ;
5. déployer Kubernetes et les applications ;
6. générer une charge de test ;
7. vérifier les logs, métriques et traces ;
8. vérifier les dashboards Kibana.

Le déploiement est réussi uniquement si les contrôles du chapitre 8 sont tous satisfaits.

> **Pourquoi séparer les plans de contrôle et de données ?**
>
> **Choix :** utiliser Fleet et OpAMP pour superviser les agents, sans activer une collecte Fleet concurrente dans les VM.
>
> **Pourquoi :** la configuration EDOT standalone porte le chemin réel de télémétrie vers `otel-edge-01`. Cette séparation évite qu’un enrôlement OpAMP modifie les receivers et les exporteurs locaux.
>
> **Alternative écartée :** enrôler les VM comme agents Fleet collecteurs. Cette approche centralise la configuration, mais elle ne correspond pas au chemin EDOT versionné dans l’architecture et introduit une seconde source de vérité.
>
> **Repli :** conserver l’agent EDOT local et désactiver uniquement son monitoring OpAMP si Fleet est temporairement indisponible.

## 2. Définitions et invariants

### 2.1 Définitions

| Terme | Définition dans cette spécification |
| --- | --- |
| Agent EDOT standalone | Elastic Agent installé dans `/opt/Elastic/Agent/elastic-agent`, configuré avec le fichier EDOT de la VM et un export OTLP vers le Collecteur Edge. |
| OpAMP | Protocole utilisé pour superviser l’agent standalone depuis Fleet Server. |
| Package Fleet | Package installé dans Kibana par l’Elastic Package Manager. Il fournit notamment des assets Kibana et des définitions d’intégration. Il ne constitue pas le chemin de collecte EDOT des VM. |
| Clé OpAMP | Clé d’enrôlement Fleet utilisée temporairement pour rattacher un agent standalone à une policy de supervision. |
| Déploiement idempotent | Nouvelle exécution qui conserve les installations et identités conformes, et ne réinstalle que lorsqu’une précondition explicite n’est plus satisfaite. |
| Fenêtre de fraîcheur | Intervalle glissant utilisé pour vérifier que des documents récents existent dans Elasticsearch. La recette actuelle utilise quinze minutes. |

### 2.2 Invariants

Les règles suivantes sont obligatoires :

- les secrets viennent de variables d’environnement ou de secrets locaux Kubernetes ;
- la valeur `password` reste réservée au profil de développement lorsque aucune variable n’est fournie ;
- aucun secret, token OpAMP ou mot de passe n’est écrit dans Git, un journal ou une sortie opérateur ;
- une VM possède un seul agent EDOT standalone actif et un seul identifiant OpAMP persistant ;
- une deuxième exécution ne crée pas une deuxième clé OpAMP active pour la même VM et la même policy ;
- une deuxième exécution ne réinstalle pas un agent dont le binaire, le mode EDOT et la version sont conformes ;
- Fleet Server doit être `HEALTHY` avant l’enrôlement OpAMP ;
- l’acheminement des données reste `VM EDOT → otel-edge-01 → Kafka → backend OTel → Elasticsearch` ;
- les dashboards natifs des packages Fleet ne sont pas réécrits par défaut.

## 3. Faits vérifiés et sources

Les faits suivants sont établis par le dépôt actif :

| Fait | Source |
| --- | --- |
| Les VM exécutent l’agent en mode EDOT standalone et peuvent être supervisées par OpAMP. | [`ansible/README.md`](../ansible/README.md), [`ansible/roles/elastic_agent/tasks/main.yml`](../ansible/roles/elastic_agent/tasks/main.yml) |
| Le rôle conserve l’installation quand le binaire et le marqueur EDOT existent et que la version correspond. | [`ansible/roles/elastic_agent/tasks/main.yml`](../ansible/roles/elastic_agent/tasks/main.yml) |
| L’identifiant OpAMP est conservé dans `/var/lib/observability/elastic-agent-otel/opamp-instance-uid`. | [`ansible/roles/elastic_agent/tasks/main.yml`](../ansible/roles/elastic_agent/tasks/main.yml) |
| Le script de provisioning réutilise une clé d’enrôlement active par VM et policy. | [`platform/elk/scripts/provision-fleet-vms.sh`](../platform/elk/scripts/provision-fleet-vms.sh) |
| Les packages `kubernetes_otel`, `kafka_otel`, `postgresql_otel` et `mongodb_otel` sont installés par le bootstrap Fleet. | [`platform/elk/scripts/bootstrap-fleet-policies.sh`](../platform/elk/scripts/bootstrap-fleet-policies.sh) |
| Le bootstrap ne réinstalle pas un package déjà présent à la version attendue. | [`platform/elk/scripts/bootstrap-fleet-policies.sh`](../platform/elk/scripts/bootstrap-fleet-policies.sh) |
| La vérification des dashboards et des données est exposée par `make dashboards-verify`. | [`Makefile`](../Makefile), [`platform/elk/dashboards/README.md`](../platform/elk/dashboards/README.md) |

Le processus des chapitres suivants est la cible normative. Une cible Makefile ou un playbook qui ne respecte pas ces invariants doit être corrigé, et non la spécification affaiblie.

## 4. Préconditions et variables

L’opérateur charge les identifiants depuis le mécanisme prévu par le dépôt :

```bash
source ./platform/elk/scripts/load-credentials.sh
```

Les variables principales sont :

| Variable | Usage | Valeur par défaut dans le dépôt |
| --- | --- | --- |
| `ELASTIC_PASSWORD` | Compte `elastic` et bootstrap local | `password` dans les cibles de développement |
| `POSTGRESQL_PASSWORD` | Accès PostgreSQL des services et de l’intégration | `password` dans les cibles de développement |
| `KIBANA_URL` | API Kibana | `http://kibana.observability.test:5601` |
| `ELASTICSEARCH_URL` | API Elasticsearch | `http://elasticsearch.observability.test:9200` |
| `KIBANA_CURL_RESOLVE` | Résolution locale de Kibana | `kibana.observability.test:5601:192.168.33.40` |
| `ELASTICSEARCH_CURL_RESOLVE` | Résolution locale d’Elasticsearch | `elasticsearch.observability.test:9200:192.168.33.40` |
| `APM_SERVER_SECRET_TOKEN` | Secret partagé entre APM Server et l’exporteur OTel backend | dérivé de `ELASTIC_PASSWORD` si absent |

Les noms DNS Elastic doivent résoudre vers `elk-01` (`192.168.33.40`). Le relais
HAProxy de `otel-edge-01` est réservé aux endpoints OTLP `4317` et `4318`.

Un opérateur ne doit pas utiliser la valeur par défaut en dehors d’un environnement de développement contrôlé.

## 5. Séquence de déploiement

### 5.1 Déployer les VM et l’agent EDOT

L’opérateur démarre et provisionne `poc-01`, `otel-backend-01`, `otel-edge-01` et `elk-01`. Le rôle Ansible installe l’agent EDOT standalone et configure le service local.

```bash
make vms-up
make vm-status
```

Le contrôle attendu est l’état actif des services de données, du Collecteur Edge, du backend OTel et de Fleet Server lorsque ce dernier est déjà configuré.

Le rôle Ansible doit respecter cette décision :

- agent absent : télécharger et installer la version demandée ;
- agent présent sans marqueur EDOT : convertir explicitement l’installation ;
- version différente : effectuer une migration contrôlée ;
- agent conforme : conserver l’installation ;
- `elastic_agent_reinstall=true` : autoriser une réinstallation explicite et traçable.

### 5.2 Préparer Elasticsearch, Kibana et Fleet

L’opérateur déploie la plateforme Elastic, attend Elasticsearch, Kibana et Fleet Server, crée les secrets nécessaires et installe les packages Fleet aux versions déclarées.

```bash
make elk-deploy
```

Le bootstrap doit être idempotent pour les policies, les package policies, les packages et les clés de Fleet Server. Il doit échouer si Kibana ou Fleet Server n’est pas disponible dans le délai prévu.

Les packages suivants sont attendus dans l’architecture active :

- `system_otel` `0.3.0` ;
- `kubernetes_otel` `2.6.0` ;
- `kafka_otel` `0.3.1` ;
- `postgresql_otel` `0.5.0` ;
- `mongodb_otel` `0.3.1`.

Après le déploiement initial, `make fleet-assets-deploy` installe les packages
et les policies Fleet sans redéployer les VM ni appliquer Kubernetes. Les assets
natifs des packages restent la référence ; aucune réconciliation automatique des
dashboards n’est exécutée.

### 5.3 Créer ou réutiliser les clés OpAMP

Le script de provisioning recherche une clé active portant le nom stable de la VM et de la policy. Il ne crée une clé que si aucune clé active correspondante n’existe.

```bash
make fleet-prerequisites
make fleet-opamp-enable
```

`fleet-opamp-enable` ne dépend pas du déploiement Elastic complet. Il ne doit
pas redimensionner le disque ou redémarrer `elk-01` pour activer OpAMP.

La clé est transmise au provisioning de la VM par l’environnement du sous-processus. Elle ne doit pas apparaître dans la ligne de commande, un fichier versionné ou la sortie standard.

L’identifiant OpAMP persistant de chaque VM doit être réutilisé. Une nouvelle clé ne doit pas entraîner un nouvel identifiant lorsque l’état local de la VM est conservé.

### 5.4 Vérifier l’enregistrement OpAMP

Le contrôle de supervision doit vérifier les deux conditions suivantes :

1. Fleet Server est `HEALTHY` ;
2. les quatre hôtes attendus sont `online` dans Fleet.

Une absence d’agent ou un agent associé à une mauvaise policy doit faire échouer
le déploiement. Deux entrées actives pour `elk-01` sont attendues lorsque l’une
correspond au Fleet Server et l’autre à l’agent OpAMP.

### 5.5 Déployer Kubernetes et les applications

L’opérateur valide les manifests puis déploie les Collectors et les applications.

```bash
make kubernetes-validate
make apps-build
make images-import
make apps-deploy
```

Les rollouts des trois services applicatifs doivent être terminés avant la génération de trafic de validation.

Avant la charge applicative, l’opérateur exécute :

```bash
make application-data-verify
```

Cette cible vérifie que le déploiement `order-service` est prêt et que la table
`products` contient au moins une ligne. Une commande REST ne doit pas servir à
initialiser ou diagnostiquer le schéma applicatif.

### 5.6 Générer une charge de validation

L’opérateur produit au moins une activité représentative pour chaque signal :

- une commande REST avec `make order-service-command`, qui exécute d’abord
  `make application-data-verify` ;
- une activité Kafka et une activité de réassort ;
- une opération MongoDB et une opération PostgreSQL ;
- les appels applicatifs nécessaires à la génération de logs, métriques et traces.

La charge doit être générée après le déploiement des applications et avant la vérification des data streams. Une vérification sans charge peut conclure à tort que la collecte est cassée.

### 5.7 Vérifier les signaux

L’opérateur exécute la recette de données :

```bash
make dashboards-verify
```

La recette doit vérifier, dans la fenêtre de fraîcheur :

- des logs récents dans les data streams attendus ;
- des métriques récentes pour System, Kubernetes, Kafka, MongoDB, PostgreSQL et les indicateurs métier ;
- des transactions et spans récents pour les applications ;
- l’absence d’erreurs d’export bloquantes ;
- la présence des champs nécessaires aux requêtes Kibana.

Le résultat est négatif si seul le flux APM est alimenté. La présence de traces ne prouve pas la disponibilité des logs et métriques des VM.

### 5.8 Vérifier les dashboards Kibana

Le contrôle des dashboards s’effectue après le contrôle des signaux. Il comporte deux niveaux :

1. vérifier que les assets Fleet attendus existent avec les bonnes versions de packages ;
2. vérifier que leurs requêtes sont valides et qu’elles peuvent lire les data streams réellement alimentés.

Les dashboards Fleet natifs restent l’état de référence après l’installation des packages. Aucune réconciliation automatique des dashboards n’est exécutée.

## 6. Idempotence et reprise

Chaque étape doit pouvoir être relancée après une interruption.

| Ressource | Identité stable | Condition de conservation | Condition de remplacement |
| --- | --- | --- | --- |
| Agent EDOT | hostname de la VM et binaire installé | binaire présent, mode EDOT présent, version conforme | version différente ou réinstallation explicite |
| Identifiant OpAMP | `/var/lib/observability/elastic-agent-otel/opamp-instance-uid` | fichier local présent | fichier absent ou VM reconstruite |
| Clé OpAMP | nom stable de la VM et policy | clé active trouvée dans Fleet | aucune clé active correspondante |
| Package Fleet | nom et version | package installé à la version attendue | package absent ou version différente |
| Policy Fleet | identifiant déclaratif | policy existante et conforme | policy absente ou configuration différente |
| Dashboard Fleet | identifiant d’asset du package | asset fourni par la version installée | réinstallation explicite du package |

Une reprise ne doit pas supprimer les agents actifs ni les dashboards natifs pour traiter un simple échec de vérification des données.

## 7. Échecs et diagnostic

Le déploiement s’arrête dans les cas suivants :

- Kibana ou Fleet Server ne devient pas disponible ;
- une policy ou un package ne peut pas être réconcilié ;
- une clé OpAMP ne peut pas être créée ou réutilisée ;
- un agent n’est pas `online` dans le délai prévu ;
- plusieurs agents OpAMP actifs correspondent au même hostname, hors Fleet
  Server sur `elk-01` ;
- aucun document récent n’est trouvé pour un signal attendu ;
- une requête de dashboard référence un champ absent ou invalide.

L’opérateur diagnostique dans cet ordre :

1. services VM et réseau ;
2. état Kibana, Elasticsearch et Fleet Server ;
3. état des agents OpAMP ;
4. configuration EDOT locale et santé des Collectors ;
5. topics Kafka et exporteur backend ;
6. documents Elasticsearch par data stream ;
7. requêtes et assets Kibana.

Une correction directe dans une ressource active est temporaire. Toute correction durable doit être reportée dans Ansible, les manifests ou les scripts versionnés.

## 8. Critères d’acceptation

Le processus est accepté lorsque toutes les conditions suivantes sont vraies :

| Contrôle | Preuve attendue |
| --- | --- |
| Validation des manifests | `make kubernetes-validate` retourne un code nul. |
| Validation Ansible | `make ansible-validate` retourne un code nul. |
| VM | `make vm-status` confirme les services attendus. |
| Fleet Server | l’API Fleet retourne `HEALTHY`. |
| Agents OpAMP | chaque VM attendue possède un agent OpAMP actif et `online` ; `elk-01` peut aussi porter l’agent Fleet Server. |
| Agent EDOT | une seconde exécution Ansible ne réinstalle pas un agent conforme. |
| Packages Fleet | les cinq packages OTel sont installés aux versions déclarées. |
| Logs | des documents récents existent dans les data streams attendus. |
| Métriques | les familles System, Kubernetes, Kafka, MongoDB, PostgreSQL et métier attendues sont alimentées. |
| Traces | des transactions et spans récents existent pour les applications. |
| Dashboards | les assets Fleet attendus existent ; les data streams alimentant les dashboards sont vérifiés par `make dashboards-verify`. |
| Propreté du dépôt | `git diff --check` retourne un code nul. |

## 9. Coûts et limites

Cette séparation conserve deux responsabilités de configuration : Ansible pour l’agent standalone et Fleet pour la supervision OpAMP et les assets Kibana. Elle exige donc des contrôles distincts et rend une panne partielle visible : Fleet peut être sain alors que le chemin de données EDOT est arrêté, ou l’inverse.

La vérification des données dépend aussi d’une charge récente. Un environnement sans trafic doit être distingué d’un environnement dont la collecte est défaillante.

La valeur `password` par défaut facilite le démarrage local, mais elle ne constitue pas une configuration de sécurité. Un déploiement partagé doit fournir explicitement les secrets et vérifier qu’ils ne sont pas exposés dans les logs.

## 10. Questions ouvertes

- **Propriétaire : équipe plateforme.** La cible `make deploy` doit-elle appeler automatiquement la préparation OpAMP et la vérification finale, ou rester une composition minimale laissant ces étapes séparées ?
- **Propriétaire : équipe observabilité.** Quelle charge minimale doit être générée pour valider chaque famille de métriques sans dépendre d’un scénario manuel ?
- **Propriétaire : équipe plateforme.** Quelle politique de rétention doit s’appliquer aux anciennes clés OpAMP inactives ?

## Annexe A. Références d’implémentation

- [`Makefile`](../Makefile)
- [`ansible/roles/elastic_agent/tasks/main.yml`](../ansible/roles/elastic_agent/tasks/main.yml)
- [`platform/elk/scripts/bootstrap-fleet-policies.sh`](../platform/elk/scripts/bootstrap-fleet-policies.sh)
- [`platform/elk/scripts/provision-fleet-vms.sh`](../platform/elk/scripts/provision-fleet-vms.sh)
- [`platform/elk/scripts/validate-fleet-prerequisites.sh`](../platform/elk/scripts/validate-fleet-prerequisites.sh)
- [`platform/elk/scripts/verify-dashboard-data.sh`](../platform/elk/scripts/verify-dashboard-data.sh)
- [`platform/elk/scripts/verify-postgresql-otel-dashboards.sh`](../platform/elk/scripts/verify-postgresql-otel-dashboards.sh)
- [`platform/elk/scripts/verify-kubernetes-otel-dashboards.sh`](../platform/elk/scripts/verify-kubernetes-otel-dashboards.sh)

Cette spécification sépare les faits vérifiés dans le dépôt de la séquence normative proposée. Les écarts entre les cibles existantes et les critères d’acceptation doivent être traités comme des travaux d’implémentation, pas comme des exceptions implicites.
