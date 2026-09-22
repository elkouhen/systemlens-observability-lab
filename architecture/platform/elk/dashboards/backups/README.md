# Sauvegardes des dashboards Kibana

Cette arborescence conserve une copie des dashboards réellement déployés dans
Kibana. Le fichier `kibana-dashboards.ndjson` est exporté par l’API Kibana avec
`includeReferencesDeep=true` : il contient les dashboards et les objets
référencés nécessaires pour comparer les panneaux, requêtes, data views,
visualisations et filtres lors d’un prochain déploiement.

Le fichier `manifest.json` donne la date d’export, le hash SHA-256 de l’export,
le nombre de dashboards et, pour chaque dashboard, son ID, son titre et les
types d’objets référencés.

Régénérer la sauvegarde depuis l’environnement déployé :

```bash
make dashboards-backup
```

La sauvegarde ne contient pas de mot de passe, de token ni de secret Kibana.
Elle constitue une référence d’état déployé ; les fichiers versionnés sous
`platform/elk/dashboards/` restent la source de vérité déclarative.
