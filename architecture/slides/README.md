# Présentation de l’architecture

Support Slidev de présentation de l’architecture **EDOT hybride**.

## Pré requis

- Node.js 20 ou plus récent ;
- npm ou pnpm.

## Démarrer le diaporama

Depuis ce répertoire :

```bash
npm install
npm run dev
```

Le serveur Slidev affiche l’URL locale dans le terminal. Pour produire une
version statique :

```bash
npm run build
```

Depuis la racine du dépôt, `make slides` délègue à cette installation.

Le contenu est aligné sur `architecture/README.md`, `architecture/platform/elk/README.md`, les
manifests Kustomize de l’architecture et les templates Ansible du Gateway OTLP et de
l’exporteur Kafka.
