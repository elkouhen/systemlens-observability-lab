# Vérifier un signal de bout en bout

Utilisez ce guide lorsqu'un log, une métrique ou une trace doit être démontré
ou validé après un déploiement. Il s'adresse à un opérateur disposant de l'accès
à `kubectl`, aux VM Vagrant et à Kibana.

## 1. Identifier le signal et son chemin attendu

Avant toute commande, relever dans [l'architecture des signaux](../architecture-signaux.md)
l'émetteur, le collecteur et la destination. Pour les métriques, la
[matrice sources](../metriques-sources.md) est la référence : elle évite de
vérifier un mauvais data stream ou un collecteur inactif sur ce rôle de VM.

## 2. Vérifier les composants producteurs

```bash
make platform-status
./scripts/cluster-status.sh
kubectl -n elastic-stack get pods
kubectl -n supermarket-demo get pods
```

Les pods applicatifs et les collectors nécessaires doivent être prêts. Le
script de statut doit confirmer que les services de données des VM répondent.
Pour une VM, vérifier également le collecteur correspondant à son profil :

| Rôle de VM | Vérification principale |
| --- | --- |
| VM OpenTelemetry | `sudo systemctl status poc-otel-collector` |
| VM Elastic Agent | `sudo /opt/Elastic/Agent/elastic-agent status` |
| VM Beats | `sudo systemctl status filebeat metricbeat` |

Exécuter ces commandes depuis la VM concernée, par exemple avec `vagrant ssh`
si vous utilisez l'environnement local.

## 3. Vérifier un document brut avant la visualisation

Dans Discover, choisir le data view indiqué par la matrice, régler une période
couvrant au moins deux intervalles de collecte, puis chercher un document de
la source attendue. Contrôler au minimum :

- l'horodatage est récent ;
- l'identité (`host.name` ou `service.name`) est celle attendue ;
- les champs nécessaires au dashboard sont présents ;
- le document est dans le data stream attendu.

Un document brut présent établit que l'émission, la collecte et l'indexation
fonctionnent. Le problème est alors situé dans les filtres, l'agrégation ou la
fenêtre temporelle de la visualisation ; voir
[Diagnostiquer un dashboard vide](diagnostiquer-dashboard-vide.md).

## 4. Consigner la validation

Pour rendre la vérification rejouable, noter dans la ligne de matrice concernée
la version des composants, la date, la requête utilisée, le data stream observé
et la décision prise. Une capture d'écran peut compléter la preuve, mais ne la
remplace pas.
