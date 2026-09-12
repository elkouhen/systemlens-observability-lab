# Plateforme

Ce répertoire rassemble les composants transverses, indépendants du code des
applications. Pour ce POC, il contient la plateforme Elastic déployée sur
Kubernetes.

## Parcours conseillé

1. Lire [`kubernetes/README.md`](kubernetes/README.md) pour le point d'entrée
   IaC Kustomize et les overlays d'environnement.
2. Lire [`elk/README.md`](elk/README.md) pour suivre le flux de télémétrie de
   bout en bout, puis `elk/fleet/`.
3. Consulter les scripts et dashboards une fois le déploiement compris.

Pour les impacts et les contrôles APM communs aux applications et à
Kubernetes, consulter le [guide APM applications et Kubernetes](../../docs/apm-application-kubernetes.md).

## Licence ECK

Les fonctions Elastic soumises à licence, notamment les SLO Kibana, exigent
une licence ECK Enterprise ou Trial valide. Utiliser un fichier de licence
**Orchestration** conservé uniquement sur le poste opérateur ; ne jamais le
copier dans le dépôt.

Sans fichier Orchestration, démarrer explicitement l'essai Enterprise de
30 jours (une seule activation par version majeure) :

```bash
make eck-trial-start
make eck-license-status
```

Installer ou remplacer la licence avec :

```bash
make eck-license-apply ECK_LICENSE_FILE=/chemin/local/licence.json
```

La cible valide le JSON, crée le Secret `eck-license` dans le namespace de
l'opérateur `elastic-system` et ajoute le label
`license.k8s.elastic.co/scope=operator`. Elle n'affiche pas le contenu du
fichier. Contrôler ensuite la réconciliation :

```bash
make eck-license-status
```

Le résultat attendu est une licence `active` de type `enterprise`, `platinum`
ou `trial`. Une licence chargée directement dans Elasticsearch n'est pas la
source de vérité de ce déploiement ECK et peut être remplacée par l'opérateur.

## Documentation externe

- [Panorama des options de déploiement Elastic](https://www.elastic.co/docs/deploy-manage/deploy)
- [Elastic Cloud on Kubernetes (ECK)](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
