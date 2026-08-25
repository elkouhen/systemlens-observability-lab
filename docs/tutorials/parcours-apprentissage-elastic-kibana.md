# Parcours d'apprentissage : découvrir Elastic et Kibana

Ce tutoriel s'adresse à une personne technique qui ne connaît ni Elastic ni Kibana. Il propose un ordre de découverte du POC : commencer par les données visibles dans Kibana, puis remonter progressivement vers les collecteurs et l'architecture.

L'objectif n'est pas de maîtriser toute la stack en une séance. À la fin du parcours, vous saurez trouver un signal dans Kibana, relier un log à une trace, et choisir le bon document lorsque vous devrez vérifier ou dépanner une donnée.

## Avant de commencer

Le POC doit déjà être déployé et vous devez pouvoir ouvrir Kibana. Les commandes et prérequis de déploiement sont dans le [README du dépôt](../../README.md).

Prévoyez entre cinq et sept heures, idéalement réparties sur plusieurs séances. Les durées sont indicatives : prenez le temps d'explorer les écrans et de refaire les exercices lorsque nécessaire.

## Les notions à garder en tête

Avant de manipuler l'interface, retenez ce modèle simple :

```text
application ou machine → collecteur → Elasticsearch → Kibana
```

- **Elasticsearch** stocke, indexe et recherche les données d'observabilité.
- **Kibana** est l'interface qui permet de rechercher ces données, de les visualiser dans des dashboards et d'administrer certains composants Elastic.
- Un **log** décrit un événement ponctuel, par exemple une erreur applicative.
- Une **métrique** est une mesure chiffrée dans le temps, par exemple l'usage mémoire d'une machine.
- Une **trace** relie les opérations d'une même requête entre plusieurs services ; elle est constituée de transactions et de spans.
- Un **data stream** est la destination Elasticsearch d'une famille de données, par exemple `logs-*`, `metrics-*` ou `traces-*`.
- Dans Kibana, un **data view** permet d'explorer un ou plusieurs data streams, notamment dans Discover.

Le [glossaire](../reference/technologies.md) complète ces définitions. Ne cherchez pas à retenir tous les sigles dès maintenant : revenez-y à mesure que vous les rencontrez.

## Étape 1 — Comprendre ce que démontre le POC (30 minutes)

Lisez d'abord les [objectifs du POC](../reference/objectifs.md), puis la section « Architecture » du [README racine](../../README.md). Identifiez seulement les éléments suivants :

- les deux services applicatifs, `order-service` et `inventory-service` ;
- les services de données Kafka, MongoDB et PostgreSQL ;
- Elasticsearch, où arrivent les données ;
- Kibana, où vous les consultez.

À ce stade, il est normal que Fleet, OpenTelemetry, ECK ou les détails de Kafka restent abstraits. Votre premier objectif est de comprendre le scénario métier : une commande est produite, traitée, puis son résultat est enregistré.

**Résultat attendu :** vous pouvez expliquer en une phrase que le POC permet d'observer le traitement d'une commande, depuis les applications jusqu'aux services de données.

## Étape 2 — Produire et voir votre première donnée (45 minutes)

Suivez le tutoriel [Première démonstration : suivre une commande de bout en bout](../applicatif/tutorials/premiere-demonstration.md). Générez une commande, puis ouvrez Kibana.

Dans Discover, effectuez ces trois explorations :

1. Sélectionnez le data view `logs-*`, définissez une période couvrant les cinq dernières minutes et recherchez les logs du namespace `supermarket-demo`.
2. Sélectionnez `traces-*` et recherchez les documents des deux services.
3. Sélectionnez `metrics-*` et recherchez les métriques associées à ces services.

Avant de conclure qu'une donnée manque, vérifiez toujours la période. Une trace ou une métrique récente peut ne pas apparaître si le sélecteur temporel porte sur une plage trop ancienne.

**Résultat attendu :** vous avez vu au moins un log et une trace associés à une commande que vous avez vous-même générée.

## Étape 3 — Savoir chercher dans Kibana (45 minutes)

Reprenez les trois data views de l'étape précédente. Dans Discover, entraînez-vous à utiliser des requêtes KQL simples :

```kql
kubernetes.namespace : "supermarket-demo"
```

```kql
service.name : ("order-service" or "inventory-service")
```

```kql
host.name : "data-01"
```

Pour chaque recherche, observez le nombre de documents et leur date, les champs `service.name` ou `host.name`, l'identifiant `trace.id` lorsqu'il est présent dans un log, et le data stream auquel appartient le document.

La [matrice des dashboards](../systeme/dashboards.md) fournit d'autres requêtes de départ et les champs utiles par vue.

**Résultat attendu :** vous savez répondre à la question « est-ce que la donnée existe dans Elasticsearch ? » avant d'ouvrir un dashboard.

## Étape 4 — Lire une trace et la relier aux logs (1 heure)

Ouvrez une trace récente depuis Discover ou depuis la vue APM. Repérez le service qui a démarré le traitement, les appels HTTP, Kafka et base de données représentés par les spans, la durée et le résultat de chaque opération, ainsi que le `trace.id` commun aux événements corrélés.

Recherchez ensuite ce même `trace.id` dans `logs-*`. Ce lien est l'un des usages les plus utiles de l'observabilité : une trace donne le contexte global, tandis qu'un log apporte le détail d'un événement précis.

Pour comprendre le vocabulaire trace, transaction et span, lisez la section [Traces, transactions et spans](../systeme/architecture-signaux.md#traces-transactions-et-spans).

**Résultat attendu :** vous pouvez passer d'une lenteur ou erreur visible dans une trace aux logs correspondants.

## Étape 5 — Explorer les dashboards sans leur faire confiance aveuglément (1 heure)

Ouvrez successivement les vues APM, Infrastructure et les dashboards MongoDB, Kafka ou PostgreSQL disponibles dans Kibana. Pour chaque vue :

1. Réglez la période sur une fenêtre assez large pour couvrir au moins deux intervalles de collecte.
2. Notez la question à laquelle répond le dashboard, par exemple « quel hôte utilise le plus de mémoire ? » ou « quel service a produit des erreurs ? ».
3. Vérifiez un document brut dans Discover avec la requête proposée par la [matrice des dashboards](../systeme/dashboards.md).
4. Comparez le champ du document avec le filtre ou la dimension visible dans le dashboard.

Un dashboard est une visualisation de données déjà indexées ; il ne constitue pas, à lui seul, une preuve que la collecte fonctionne.

**Résultat attendu :** vous savez distinguer « le dashboard est vide » de « la donnée n'a pas été collectée ».

## Étape 6 — Comprendre qui collecte les données (1 heure 30)

Lisez d'abord l'[architecture des signaux](../systeme/architecture-signaux.md), puis l'[architecture Fleet](../systeme/architecture-fleet.md). Gardez cette distinction en tête :

- **Fleet** pilote centralement des Elastic Agents ;
- **Elastic Agent**, Filebeat et Metricbeat collectent des données ;
- **OpenTelemetry** est un standard utilisé pour instrumenter et transporter des signaux applicatifs ;
- les collecteurs envoient finalement leurs données vers Elasticsearch ;
- Kibana les lit, mais ne les collecte pas.

Consultez ensuite le [comparatif des intégrations](../systeme/integrations.md). Ne cherchez pas encore à choisir une solution de collecte : l'objectif est de comprendre pourquoi le POC en montre plusieurs et quels compromis elles illustrent.

**Résultat attendu :** vous pouvez expliquer la différence entre Kibana, Elasticsearch, Fleet et un collecteur.

## Étape 7 — Apprendre à diagnostiquer (1 heure)

Simulez un cas simple : un dashboard n'affiche pas ce que vous attendez. Suivez les guides dans cet ordre :

1. [Vérifier un signal de bout en bout](../systeme/how-to/verifier-un-signal.md) ;
2. [Diagnostiquer un dashboard vide](../systeme/how-to/diagnostiquer-dashboard-vide.md) ;
3. [Dépanner un Elastic Agent Fleet](../systeme/how-to/depanner-fleet.md), seulement si le signal concerné est collecté par cet Agent.

La méthode à retenir est toujours la même : identifier le signal attendu, vérifier son producteur, chercher un document brut dans Elasticsearch via Discover, puis seulement examiner la visualisation.

**Résultat attendu :** vous disposez d'une démarche reproductible plutôt que d'essayer des réglages Kibana au hasard.

## Après ce parcours

Vous pouvez approfondir selon votre besoin :

- **développement applicatif** : lire la [documentation applicative](../applicatif/README.md), puis comparer les intégrations des deux services ;
- **exploitation de la plateforme** : suivre la [documentation système](../systeme/README.md) et la matrice des métriques ;
- **administration de Fleet** : reprendre l'architecture Fleet et les guides de dépannage ;
- **création de visualisations** : partir d'une donnée vérifiée dans Discover, puis documenter pour chaque dashboard son data view, ses champs, ses filtres et sa requête de contrôle.
