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
l’exporteur Kafka. Les sources D2 et leurs rendus PNG haute résolution sont versionnés dans
`diagrams/`. Les captures PNG du support sont générées dans `screenshots/` pour contrôler la
lisibilité avant diffusion.

Pour reconstruire le support et ses captures :

```bash
npm run build
d2 --scale 2 diagrams/topology.d2 diagrams/topology.png
d2 --scale 2 diagrams/logs.d2 diagrams/logs.png
d2 --scale 2 diagrams/metrics.d2 diagrams/metrics.png
d2 --scale 2 diagrams/traces.d2 diagrams/traces.png
npx slidev export slides.md --format png --output screenshots --scale 2
npx slidev export slides.md --output screenshots.pdf
```

La commande d’export nécessite un navigateur Chromium disponible localement.
