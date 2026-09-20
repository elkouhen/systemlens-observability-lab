SHELL := /bin/bash
.DEFAULT_GOAL := help

ARCH_VERSION ?= $(shell test -f .architecture-version && sed -n '1p' .architecture-version || echo v3)
ARCH_NAME := Hybride Fleet
SYSTEMLENS ?= systemlens
VAGRANT ?= vagrant

.PHONY: help architecture-list architecture-switch architecture-status apps-architecture-graph apps-codeql-module-graph apm-install apm-audit vagrant-destroy ci

help: ## Afficher les tâches de l'architecture sélectionnée
	@printf 'Architecture active : %s — %s\n' '$(ARCH_VERSION)' '$(ARCH_NAME)'
	@printf 'Usage : make <cible>\n'
	@printf '  architecture-list    Afficher l\x27architecture disponible\n'
	@printf '  architecture-status  Afficher la version active\n'
	@printf '  apps-architecture-graph  Indexer les sources Java et générer le graphe SystemLens\n'
	@printf '  apps-codeql-module-graph Analyser les dépendances de modules Java et actualiser le graphe\n'
	@printf '  apm-install          Installer le contexte APM déclaré dans apm.yml\n'
	@printf '  apm-audit            Auditer le contexte APM du projet\n'
	@printf '  vagrant-destroy      Détruire les VM de l’architecture active\n'
	@printf "  ci                   Exécuter les validations de l'architecture sélectionnée\n"
	@printf '  make <cible>         Déléguer la cible au bundle sélectionné\n'

architecture-status: ## Afficher la version active
	@$(MAKE) -C $(ARCH_VERSION) architecture-status

architecture-list: ## Lister les architectures disponibles
	@printf '* v3 — Hybride Fleet\n'

apps-architecture-graph: ## Indexer les sources Java et générer le graphe SystemLens
	@command -v '$(SYSTEMLENS)' >/dev/null 2>&1 || { echo 'SystemLens absent : installez une version compatible avec import-facts.' >&2; exit 1; }
	@cd apps/supermarket-demo && \
	  '$(SYSTEMLENS)' doctor && \
	  '$(SYSTEMLENS)' index && \
	  jq empty architecture.application-inventory.json && \
	  jq empty architecture.supermarket.flows.json && \
	  flows_file=$$(mktemp architecture.systemlens-flows.json.XXXXXX) && \
	  trap 'rm -f "$$flows_file"' EXIT && \
	  '$(SYSTEMLENS)' flows --json > "$$flows_file" && \
	  mv "$$flows_file" architecture.systemlens-flows.json && \
	  '$(SYSTEMLENS)' import-facts architecture.ai-java.pass-004.json --namespace ai-java-architecture --complete && \
	  '$(SYSTEMLENS)' export microservices --html architecture.java.html --root-path .

apps-codeql-module-graph: ## Analyser les dépendances de modules Java avec CodeQL
	@command -v codeql >/dev/null 2>&1 || { echo 'CodeQL absent : installez la CLI et le pack codeql/java-all.' >&2; exit 1; }
	@cd apps/supermarket-demo && ./codeql/export-module-dependencies.sh

apm-install: ## Installer le contexte APM déclaré dans apm.yml
	@command -v apm >/dev/null 2>&1 || { echo "APM CLI absent : voir docs/agent-package-manager.md" >&2; exit 1; }
	@apm install

apm-audit: ## Auditer le contexte APM du projet
	@command -v apm >/dev/null 2>&1 || { echo "APM CLI absent : voir docs/agent-package-manager.md" >&2; exit 1; }
	@apm audit --ci

vagrant-destroy: ## Détruire les VM de l’architecture active
	@cd '$(ARCH_VERSION)' && '$(VAGRANT)' destroy --force

ci: ## Exécuter les validations de l'architecture sélectionnée
	@$(MAKE) -C $(ARCH_VERSION) ci

architecture-switch: ## Vérifier l'architecture persistante (VERSION=v3)
	@test '$(VERSION)' = v3 || { echo 'VERSION doit valoir v3' >&2; exit 1; }
	@printf '%s\n' 'v3' > .architecture-version
	@echo 'Architecture sélectionnée : v3'

%:
	@case '$(ARCH_VERSION)' in v3) ;; *) echo 'ARCH_VERSION doit valoir v3' >&2; exit 1;; esac
	@$(MAKE) -C $(ARCH_VERSION) '$@'
