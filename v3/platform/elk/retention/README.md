# Rétention du POC v3

## Règles

| Stockage | Règle déclarée | Suppression |
| --- | --- | --- |
| Kafka, broker et topics métier/OTLP existants | 24 h ; 512 MiB par partition ; segments de 64 MiB ou 1 h | `delete`, vérification toutes les 5 minutes |
| Elasticsearch `logs-*`, `metrics-*`, `traces-*` | ILM `poc-observability-24h` : rollover à 6 h ou 512 MiB par shard primaire | Suppression 24 h après rollover |
| journald, dont stdout Podman | 24 h, segments de 1 h, plafond persistant 256 MiB et volatile 128 MiB | Suppression automatique des anciens journaux |
| MongoDB, PostgreSQL, logs actifs Kafka | logrotate quotidien, `rotate 0` | Troncature sans archive |
| rsyslog et HAProxy | logrotate quotidien, `rotate 0` | Suppression sans archive et réouverture via rsyslog |
| Archives natives Kafka, anciens logs Elastic Agent et archives des fichiers précédents | Nettoyage horaire des fichiers non ouverts dont la dernière écriture date de plus de 24 h | Suppression des fichiers expirés |

Kafka conserve 512 MiB **par partition**, et non par topic. Avec trois
partitions et un réplica, chaque topic OTLP a un seuil de 1,5 GiB. Ce seuil
n'est pas un quota disque strict : segments actifs, index et délais de
nettoyage ajoutent une marge. Les paramètres de topics peuvent remplacer ceux
du broker ; le déploiement réconcilie explicitement les topics `supermarket.*`
et `otel-*`. Les topics internes Kafka conservent leurs règles spécifiques.

ILM supprime des indices entiers, pas les événements un par un à leur
24e heure. Le délai normal est donc de 24 à environ 30 h, plus le délai de
traitement ILM ; les index time series attendent également la fin de leur fenêtre
d'écriture. Le rollover de 6 h limite le nombre de petits shards dans ce POC.
Les indices vides ne sont pas renouvelés inutilement. Les anciens indices
qui ne reçoivent plus d'écritures utilisent la politique de transition
`poc-observability-24h-existing` (suppression seule), en conservant leur date
ILM d'origine. Les indices déjà expirés deviennent éligibles à la suppression.

La rotation quotidienne des fichiers n'est pas une fenêtre glissante : elle
supprime le contenu à chaque passage, sans conserver d'archive. `copytruncate`
préserve les descripteurs MongoDB/PostgreSQL/Kafka, avec une petite fenêtre de
perte possible pendant la copie/troncature. Les fichiers encore ouverts sont
exclus du nettoyage des archives. Les logs actifs Elastic Agent restent gérés
par sa rotation native. Le nettoyage horaire peut ajouter jusqu'à une heure.

Ces règles concernent les signaux de télémétrie et les journaux des VM v3.
Elles ne suppriment pas les données métier MongoDB/PostgreSQL. Les logs locaux
des nœuds Kubernetes et les images Docker ne sont pas gérés par ce playbook.
La collecte reste inchangée : applications/Kubernetes → OTel → Kafka →
exporteur → Elasticsearch ; VM → Fleet → Elasticsearch → Kibana.

## Appliquer et vérifier

Prérequis : v3 active, quatre VM démarrées, accès SSH de l'inventaire Vagrant,
Python 3, Ansible et ses collections habituelles, kubectl et accès au Secret
`elastic-stack/elasticsearch-es-elastic-user`. Le mot de passe peut aussi être
fourni par `ELASTICSEARCH_PASSWORD` ou `ELASTIC_PASSWORD`, sans le versionner.
`RETENTION_ELASTICSEARCH_URL` remplace l'adresse VM par défaut
`http://192.168.33.40:9200` si nécessaire.

Depuis la racine du dépôt :

```bash
make retention-validate
make retention-plan
make retention-deploy
make retention-verify
```

La validation contrôle les playbooks, Python et JSON sans mutation. Le plan
lit Elasticsearch et affiche les politiques et le nombre de data streams et
d'indices concernés. Le déploiement applique les règles des VM, redémarre
Kafka seulement si sa déclaration change, puis applique et vérifie ILM.
Il exécute le nettoyage des archives expirées après modification des règles et
renouvelle les segments journald avant leur purge. Il ne force pas la
troncature des logs actifs par logrotate et ne lance pas de provisionnement complet.

Le contrôle attend les timers actifs, une configuration logrotate valide,
les durées et plafonds effectifs Kafka et la politique ILM sur tous les indices
et templates de télémétrie, sans étape ILM en erreur. Le passage réel du temps
reste nécessaire pour observer une expiration à 24 h. L'absence de données
anciennes n'est pas simulée par une suppression forcée.

Le rôle est inclus dans les futurs provisionnements Ansible et `elk-deploy`
réconcilie ILM après les intégrations Fleet. Après ajout d'une intégration,
`make ilm-deploy` vérifie que ses templates héritent bien de la politique.

Références : [ILM et Fleet](https://www.elastic.co/docs/reference/fleet/data-streams-ilm-tutorial),
[configuration Kafka](https://kafka.apache.org/39/configuration/broker-configs/),
[journald](https://www.freedesktop.org/software/systemd/man/252/journald.conf.html).
