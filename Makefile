SHELL := /bin/bash
.DEFAULT_GOAL := help

ARCH_VERSION ?= $(shell test -f .architecture-version && sed -n '1p' .architecture-version || echo v1)

.PHONY: help architecture-switch architecture-status apm-install apm-audit ci

help: ## Afficher les tâches de l'architecture sélectionnée
	@printf 'Architecture active : %s\n' '$(ARCH_VERSION)'
	@printf 'Usage : make <cible> [VERSION=v1|v2|v3]\n'
	@printf '  architecture-switch  Sélectionner v1, v2 ou v3\n'
	@printf '  architecture-status  Afficher la version active\n'
	@printf '  apm-install          Installer le contexte APM déclaré dans apm.yml\n'
	@printf '  apm-audit            Auditer le contexte APM du projet\n'
	@printf "  ci                   Exécuter les validations de l'architecture sélectionnée\n"
	@printf '  make <cible>         Déléguer la cible au bundle sélectionné\n'

architecture-status: ## Afficher la version active
	@$(MAKE) -C $(ARCH_VERSION) architecture-status

apm-install: ## Installer le contexte APM déclaré dans apm.yml
	@command -v apm >/dev/null 2>&1 || { echo "APM CLI absent : voir docs/agent-package-manager.md" >&2; exit 1; }
	@apm install

apm-audit: ## Auditer le contexte APM du projet
	@command -v apm >/dev/null 2>&1 || { echo "APM CLI absent : voir docs/agent-package-manager.md" >&2; exit 1; }
	@apm audit --ci

ci: ## Exécuter les validations de l'architecture sélectionnée
	@$(MAKE) -C $(ARCH_VERSION) ci

architecture-switch: ## Sélectionner une architecture persistante (VERSION=v1|v2|v3)
	@test '$(VERSION)' = v1 -o '$(VERSION)' = v2 -o '$(VERSION)' = v3 || { echo 'VERSION doit valoir v1, v2 ou v3' >&2; exit 1; }
	@printf '%s\n' '$(VERSION)' > .architecture-version
	@echo "Architecture sélectionnée : $(VERSION)"

%:
	@case '$(ARCH_VERSION)' in v1|v2|v3) ;; *) echo 'ARCH_VERSION doit valoir v1, v2 ou v3' >&2; exit 1;; esac
	@$(MAKE) -C $(ARCH_VERSION) '$@'
