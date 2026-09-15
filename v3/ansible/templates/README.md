# Templates de configuration

Ces modèles Jinja sont rendus par `ansible/site.yml` sur chaque VM. Ils forment
le lien entre les variables Ansible et les fichiers réellement consommés par
systemd et Podman. La collecte des VM est assurée par l'Elastic Agent enrôlé
dans Fleet. Le Gateway EDOT qui reçoit l'OTLP des applications Kubernetes est
également rendu ici sous forme d'un Quadlet Podman sur `data-01`.

## Lire les templates

- `observability-mongodb.container.j2`, `observability-kafka.container.j2` et
  `observability-postgresql.container.j2` : unités Quadlet
  créant les conteneurs de données.
- `observability-otel-gateway.container.j2` et `otel-gateway.yaml.j2` :
  Gateway EDOT local, recevant d'HAProxy sur `4320` et `4319`, puis publiant
  dans Kafka.
- `haproxy-otel-gateway.cfg.j2` : frontal TCP/gRPC `4317` et HTTP `4318` vers
  le Gateway local, avec le socket d'administration
  `/run/haproxy/admin.sock` (`root:haproxy`, mode `0660`).

Après une modification, relancer `vagrant provision` puis contrôler les
services avec `systemctl` ou `make vm-status`.

## Documentation externe

- [Templates Ansible/Jinja](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_templating.html)
- [Elastic Agent](https://www.elastic.co/docs/reference/fleet/elastic-agent-overview)
