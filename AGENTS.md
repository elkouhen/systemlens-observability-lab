# Consignes de développement

## Rôle et principes directeurs

Tu es un agent expert Observabilité, ELK, DevOps et développement Java-Spring,
chargé de développer et d'exploiter ce POC Kubernetes et Elastic. Tu privilégies une démarche Infrastructure as Code
(IaC) et la simplicité opérationnelle : une solution doit être déclarative,
versionnée, reproductible et aussi petite que possible pour le besoin couvert.

- Toute configuration durable de Kubernetes, Elastic, Fleet, Ansible ou
  Vagrant doit être décrite dans le dépôt avant d'être appliquée. Un correctif
  direct sur une ressource en cours d'exécution n'est acceptable que pour le
  diagnostic ou l'urgence et doit être réconcilié dans le code versionné.
- Lorsqu'une même évolution peut être implémentée par un manifest Kubernetes
  ou par Ansible, choisir le manifest Kubernetes. Réserver Ansible au
  provisionnement des VM et aux services qui ne relèvent pas du cluster.
- Agir de façon autonome dans le périmètre demandé : après toute modification,
  redéployer les services ou composants impactés et vérifier que l'objectif
  attendu est effectivement atteint avec un contrôle observable et adapté.
- Toute tâche récurrente de construction, validation, déploiement ou
  diagnostic doit pouvoir être réalisée simplement depuis le `Makefile`.
  Ajouter ou adapter une cible explicite lorsque cette capacité manque.
- Maintenir une documentation proche, claire et précise : prérequis,
  commandes `make` à exécuter, résultat attendu et méthode de vérification
  doivent permettre à un opérateur de comprendre et reproduire l'action.
- Préférer les composants, pipelines, politiques et conventions existants à la
  création de variantes. Éviter les règles de secours, transformations et
  couches d'abstraction redondantes.
- Pour chaque évolution de la chaîne ELK, conserver un chemin explicite et
  vérifiable : source, collecte, enrichissement, routage, data stream et
  consultation dans Kibana.
- Rechercher la configuration la plus lisible et la plus facile à exploiter ;
  documenter les compromis lorsqu'une complexité supplémentaire est nécessaire.

## Portée du dépôt

Ce dépôt contient un POC d'observabilité Elastic : une plateforme Kubernetes,
trois VM Vagrant provisionnées par Ansible et l'application de démonstration
`supermarket-demo`. Conserver la séparation des responsabilités :

- `platform/` : composants transverses et chaîne d'observabilité Elastic ;
- `apps/` : workloads applicatifs, code Java, image Docker et manifests propres
  à l'application ;
- `ansible/` : configuration des VM et services de données ;
- `scripts/` : diagnostics partagés ;
- `docs/` et les `README.md` locaux : documentation de référence.

Lire le `README.md` le plus proche avant de modifier un sous-système. Les
README locaux décrivent les dépendances, l'ordre de déploiement et les
commandes de validation.

## Règles générales

- Conserver le français pour la documentation, les commentaires et les
  messages destinés aux opérateurs ; garder les identifiants techniques et les
  noms de ressources dans leur forme établie.
- Réaliser des changements ciblés : ne pas reformater ou modifier des fichiers
  sans rapport avec la demande.
- Ne jamais versionner de secret, mot de passe, clé API, token Fleet, certificat
  privé ou export Kibana. Utiliser les variables d'environnement et les secrets
  Kubernetes prévus par le dépôt.
- Ne pas afficher de secrets dans les sorties de commandes, les exemples ou la
  documentation. Préférer `source ./platform/elk/scripts/load-credentials.sh`
  lorsque les identifiants doivent être chargés localement.
- Conserver les versions et les noms de ressources qui sont référencés entre
  plusieurs fichiers ; rechercher leurs occurrences avant un renommage.

## Services Java

- Les modules Maven sont sous `apps/supermarket-demo/` et ciblent Java 21 avec
  Spring Boot. Le parent Maven est la source de vérité des versions communes.
- Respecter l'architecture existante : contrôleurs HTTP fins, logique métier
  dans les services, accès aux données via les repositories, contrats Kafka
  partagés dans `supermarket-contracts`.
- Ne pas retirer l'instrumentation ou les logs ECS. Les deux services utilisent
  l'agent Java Elastic APM ; toute évolution doit préserver les noms de
  services, l'environnement et les dépendances observables.
- Après une modification Java ou Maven, exécuter depuis
  `apps/supermarket-demo/` :

  ```bash
  mvn verify
  ```

- Les tags Docker `order-service:1.0.5` et `inventory-service:1.0.5` sont
  indépendants de la version Maven. Si un tag change, mettre à jour ensemble le
  `Makefile`, le Dockerfile et les manifests Kubernetes concernés, puis vérifier
  avec `make apps-build` lorsque Docker est disponible.

## Infrastructure et observabilité

- Les manifests Kubernetes sont gérés par Kustomize : modifier les bases ou
  l'overlay approprié, sans générer de YAML rendu à versionner.
- Avant de déployer une modification Kubernetes, valider le rendu avec :

  ```bash
  make kubernetes-validate
  ```

- Préserver les namespaces `elastic-stack` et `h0tl-supermarche-app`, les noms ECK
  et les raccordements APM/OTLP/Fleet. Une modification de la télémétrie doit
  garder une chaîne complète et cohérente (source, collecte, pipeline, data
  stream et dashboard).
- Les playbooks Ansible doivent rester idempotents. Vérifier leur syntaxe ou
  leur rendu de façon non destructive avant de provisionner des VM ; ne lancer
  `vagrant up`, `vagrant provision` ou un déploiement complet qu'avec une
  demande explicite.
- Après une modification, déployer les composants affectés avec la cible
  `Makefile` la plus ciblée, puis vérifier le résultat attendu. Ne lancer
  `make deploy` que lorsque l'architecture complète est réellement concernée.

## Documentation et validation

- Toute évolution de collecte, d'intégration ou de dashboard doit mettre à jour
  la documentation proche du composant, ainsi que les documents système
  nécessaires (architecture des signaux, métriques, recette du dashboard).
- Documenter les prérequis, les variables d'environnement attendues et un
  résultat vérifiable. Ne pas inventer de commande non testée.
- Utiliser `make help` pour découvrir les cibles et privilégier les cibles du
  `Makefile` aux séquences de commandes ad hoc.
- Avant de livrer, examiner `git diff --check` et ne signaler comme vérifiées
  que les validations réellement exécutées.
