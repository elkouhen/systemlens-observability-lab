# Agent Package Manager

Le projet déclare son contexte d'agent dans [`apm.yml`](../apm.yml), selon le
format de [Microsoft APM](https://github.com/microsoft/apm). Le manifest est
volontairement minimal : il ne télécharge aucun package d'agent ni serveur MCP
par défaut. Les règles du dépôt restent dans `AGENTS.md` et les compétences
locales sont gérées par l'environnement Codex.

## Installer le CLI

Sur macOS ou Linux :

```bash
curl -sSL https://aka.ms/apm-unix | sh
apm --version
```

Les autres modes d'installation sont décrits dans la
[documentation officielle d'installation](https://microsoft.github.io/apm/).

## Utiliser le projet

Depuis la racine du dépôt :

```bash
make apm-install
make apm-audit
```

`apm-install` lit `apm.yml` et prépare le contexte déclaré. `apm-audit` vérifie
la structure du manifest, les dépendances et les éventuelles dérives du contexte
généré. Le cache `apm_modules/` n'est pas versionné.

Le manifest ne contient actuellement aucune dépendance APM ou MCP. Pour ajouter
une dépendance, utiliser `apm install <source>`, vérifier le diff produit, puis
committer `apm.yml` et `apm.lock.yaml` si APM génère ce lockfile. Ne jamais
ajouter un serveur MCP sans valider sa source, ses permissions et son besoin
pour le projet.

## Contrôle en CI

Le contrôle recommandé est :

```bash
apm audit --ci
```

Il doit être exécuté après toute modification de `apm.yml`, du lockfile ou du
contexte destiné aux agents. Les commandes d'installation et d'audit ne
modifient pas l'infrastructure Kubernetes ou Elastic.
