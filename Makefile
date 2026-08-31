SHELL := /bin/bash
.DEFAULT_GOAL := help

ARCH_VERSION ?= $(shell test -f .architecture-version && sed -n '1p' .architecture-version || echo v1)

.PHONY: help architecture-switch architecture-status

help: ## Afficher les tâches de l'architecture sélectionnée
	@printf 'Architecture active : %s\n' '$(ARCH_VERSION)'
	@printf 'Usage : make <cible> [VERSION=v1|v2]\n'
	@printf '  architecture-switch  Sélectionner v1 ou v2\n'
	@printf '  architecture-status  Afficher la version active\n'
	@printf '  make <cible>         Déléguer la cible au bundle sélectionné\n'

architecture-status: ## Afficher la version active
	@$(MAKE) -C $(ARCH_VERSION) architecture-status

architecture-switch: ## Sélectionner une architecture persistante (VERSION=v1|v2)
	@test '$(VERSION)' = v1 -o '$(VERSION)' = v2 || { echo 'VERSION doit valoir v1 ou v2' >&2; exit 1; }
	@printf '%s\n' '$(VERSION)' > .architecture-version
	@echo "Architecture sélectionnée : $(VERSION)"

%:
	@case '$(ARCH_VERSION)' in v1|v2) ;; *) echo 'ARCH_VERSION doit valoir v1 ou v2' >&2; exit 1;; esac
	@$(MAKE) -C $(ARCH_VERSION) '$@'
