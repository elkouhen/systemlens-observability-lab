# PRD — POC d'observabilité Elastic

## 1. Vision

Le produit est un POC d'observabilité fondé sur la stack Elastic. Il doit
démontrer, sur une application distribuée représentative, qu'une équipe peut
collecter, corréler et consulter des logs, métriques et traces de façon
reproductible.

L'application de gestion de stock `supermarket-demo` est un support de test.
Son métier reste volontairement simple : il fournit des flux HTTP, Kafka et
base de données suffisamment réalistes pour éprouver la chaîne
d'observabilité. Ce n'est pas un produit de gestion de stock à industrialiser.

## 2. Problème à résoudre

Sans chaîne unifiée, diagnostiquer un incident qui traverse plusieurs services,
Kafka, des bases de données et Kubernetes demande de naviguer entre des outils
et des formats séparés. L'objectif est d'obtenir une preuve cohérente du
parcours d'un événement, depuis l'application jusqu'aux data streams Elastic et
aux dashboards Kibana.

## 3. Objectifs

- Déployer une plateforme Elastic déclarative et reproductible sur Kubernetes.
- Collecter les logs, métriques et traces des applications Java instrumentées.
- Observer les composants de données Kafka, MongoDB et PostgreSQL des VM.
- Normaliser les environnements applicatifs et router les signaux vers les data
  streams Elastic appropriés.
- Mettre à disposition des dashboards et une recette permettant de vérifier les
  signaux de bout en bout.
- Maintenir une exploitation simple : une instance Logstash, configurations
  versionnées, commandes `make` et documentation proche des composants.

## 4. Non-objectifs

- Construire un produit métier complet de gestion de stock.
- Optimiser les quantités de réassort ou prévoir la demande.
- Fournir une architecture Elastic haute disponibilité ou dimensionnée pour la
  production.
- Exposer les entrées Logstash hors du cluster ou couvrir tous les types de
  sources de télémétrie possibles.

## 5. Utilisateurs et parties prenantes

| Public | Besoin principal |
| --- | --- |
| Équipe plateforme / SRE | Déployer, exploiter et diagnostiquer la chaîne de télémétrie. |
| Équipe de développement | Retrouver les traces, logs et métriques d'un service Java. |
| Équipe architecture | Valider les choix d'intégration, de routage et d'IaC. |
| Équipe produit POC | Vérifier que les scénarios représentatifs produisent les preuves attendues. |

## 6. Cas d'usage observables

Le POC doit permettre d'observer les scénarios suivants dans Kibana :

1. Une commande est émise par `order-service` et publiée dans Kafka.
2. `inventory-service` consomme la commande, réserve le stock et écrit son
   résultat dans MongoDB et PostgreSQL.
3. Lorsque le stock atteint zéro, `inventory-service` publie un événement de
   rupture.
4. `restock-service` consomme cet événement et publie une demande de réassort.
5. `inventory-service` applique le réassort, tout en restant propriétaire du
   catalogue et du stock.

Ces scénarios servent à démontrer la corrélation entre les trois services, les
topics Kafka, les bases de données et les signaux Elastic.

## 7. Architecture cible

| Domaine | Composants et responsabilités |
| --- | --- |
| Application | `order-service`, `inventory-service` et `restock-service`, en Java/Spring Boot et instrumentés par l'agent Elastic APM. |
| Événements | Kafka transporte les commandes, ruptures et demandes de réassort ; les contrats sont partagés dans `supermarket-contracts`. |
| Données | MongoDB et PostgreSQL conservent les écritures du scénario applicatif. |
| Collecte | APM Server reçoit les signaux applicatifs ; Elastic Agent collecte les logs Kubernetes ; Agents/Fleet ou Beats collectent les VM. |
| Enrichissement et routage | Une instance Logstash héberge deux pipelines : `apm` reçoit APM sur le port 5044 et `kubernetes-logs` reçoit les logs Kubernetes sur le port 5045. Chacun normalise son identité et route ses data streams. |
| Consultation | Elasticsearch conserve les données et Kibana fournit la recherche, APM, l'infrastructure et les dashboards versionnés. |

L'environnement applicatif respecte le contrat
`<type><plateforme_sur_3_caractères>-<namespace>`, par exemple
`h0tl-supermarche-app`. Dans Logstash, les logs utilisent
`kubernetes.namespace`, y compris pour les signaux APM transmis par le Java
agent. Le dictionnaire `translate` transforme le code `h` en `homologation`,
ajoute les labels de plateforme et de namespace, puis aligne
`service.environment` et les data streams concernés.

## 8. Exigences fonctionnelles

### Collecte et corrélation

- Chaque service Java doit produire des traces APM, des métriques applicatives
  et des logs ECS.
- Les signaux doivent conserver les attributs nécessaires à la corrélation :
  service, environnement, transaction, dépendances et conteneur lorsque
  pertinent.
- Les événements Kafka doivent permettre de comprendre le passage de la
  commande au réassort, sans couplage HTTP direct entre le service de réassort
  et le catalogue.

### Enrichissement et routage

- Logstash doit utiliser une configuration versionnée et rechargée
  automatiquement.
- Le mapping des codes d'environnement doit être déclaré dans un dictionnaire,
  et non dans des conditions répétées.
- Les logs Kubernetes applicatifs doivent être routés vers
  `logs-kube-<code_plateforme>-<environnement>`, d'après
  `kubernetes.namespace`.
- Les métriques APM Java issues de conteneurs doivent être routées vers
  `metrics-apm.app.<code_plateforme>-<environnement>`.
- Les traces, erreurs et métriques hors de ce périmètre conservent leur data
  stream d'origine.

### Consultation

- Les dashboards pertinents doivent être versionnés, déployables par IaC et
  accompagnés d'une méthode de recette.
- Un opérateur doit pouvoir vérifier le fonctionnement depuis Kibana et avec
  les commandes documentées du dépôt.

## 9. Exigences non fonctionnelles

| Thème | Exigence |
| --- | --- |
| Infrastructure as Code | Les manifests Kubernetes utilisent Kustomize ; les VM sont provisionnées par Ansible et Vagrant. Aucune configuration durable ne dépend d'une modification manuelle. |
| Simplicité | Une seule instance et un seul pipeline Logstash sont retenus pour le POC ; les deux ports distinguent les protocoles APM et Beats. |
| Sécurité | Les secrets, tokens et clés API ne sont pas versionnés ; Elasticsearch est accédé en HTTPS depuis Logstash. |
| Reproductibilité | Les contrôles, constructions et déploiements sont accessibles par des cibles `make`. |
| Exploitabilité | Chaque composant possède une documentation de proximité décrivant son déploiement et sa vérification. |
| Résilience POC | Les erreurs de traitement doivent être visibles dans les logs, métriques et traces ; la haute disponibilité n'est pas un objectif. |

## 10. Critères d'acceptation

| ID | Critère | Preuve attendue |
| --- | --- | --- |
| CA-01 | Le rendu Kubernetes est valide. | `make kubernetes-validate` réussit. |
| CA-02 | Les modules applicatifs et leurs tests sont cohérents. | `make apps-test` réussit. |
| CA-03 | Les trois services sont déployés et sains. | Les Deployments du namespace `h0tl-supermarche-app` sont disponibles. |
| CA-04 | APM Server et Logstash sont disponibles. | Les Deployments correspondants du namespace `elastic-stack` sont disponibles ; les listeners Logstash 5044 et 5045 sont démarrés. |
| CA-05 | Un signal portant `h0tl-supermarche-app` est normalisé. | `service.environment` vaut `homologation`, avec les labels `ptf: 0tl` et `namespace: supermarche-app`. |
| CA-06 | Les logs et métriques applicatives sont routés par plateforme et environnement. | Les data streams `logs-kube-0tl-homologation` et `metrics-apm.app.0tl-homologation` reçoivent des documents. |
| CA-07 | Les cas d'usage commande, rupture et réassort sont consultables. | Les traces, logs et métriques associés sont visibles dans Kibana. |
| CA-08 | Les dashboards utilisés sont reproductibles. | Les définitions versionnées sont déployées et la recette de dashboard documentée est concluante. |

## 11. Plan de livraison

1. Déployer l'infrastructure Kubernetes Elastic et les VM de données selon les
   procédures versionnées.
2. Construire et déployer les trois services de démonstration.
3. Vérifier la collecte, l'enrichissement et le routage des signaux.
4. Exécuter la recette des dashboards et consigner les résultats attendus.
5. Utiliser le POC pour qualifier les conventions de télémétrie avant leur
   adoption par d'autres applications.

## 12. Risques et décisions ouvertes

| Sujet | Décision ou limite actuelle |
| --- | --- |
| Réassort | La quantité est fixe pour générer un scénario observable ; elle ne représente pas une politique métier. |
| Capacité | Les limites de ressources sont adaptées au POC et doivent être redimensionnées avant une charge soutenue. |
| Haute disponibilité | Non couverte : les composants sont volontairement réduits au minimum opérationnel. |
| Évolution des environnements | Tout nouveau code d'environnement doit être ajouté au dictionnaire Logstash et à la documentation de routage. |

## 13. Références d'exploitation

- `README.md` : architecture générale et prérequis.
- `platform/README.md` : déploiement et exploitation de la plateforme.
- `platform/kubernetes/base/observability/README.md` : chaîne APM, Logstash et
  vérifications.
- `platform/elk/dashboards/README.md` : dashboards et recette associée.
- `apps/supermarket-demo/README.md` : application de démonstration et scénario
  métier.
