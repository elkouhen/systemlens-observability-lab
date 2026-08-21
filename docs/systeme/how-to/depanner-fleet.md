# Dépanner un Elastic Agent piloté par Fleet

Utilisez ce guide lorsqu'un Elastic Agent est `Offline`, `Unhealthy` ou ne
produit pas les métriques attendues. Dans ce POC, seule la **VM Elastic Agent**
doit être pilotée par Fleet ; les profils OpenTelemetry et Beats ne doivent pas
être considérés comme des erreurs s'ils n'apparaissent pas dans Fleet.

## 1. Vérifier l'état local de l'Agent

Sur la VM Elastic Agent :

```bash
sudo systemctl status elastic-agent
sudo /opt/Elastic/Agent/elastic-agent status
```

Le service doit être actif et l'état doit indiquer une connexion saine. En cas
d'échec, relever le message et consulter les journaux systemd avant de
réenrôler l'Agent :

```bash
sudo journalctl -u elastic-agent --since '15 minutes ago'
```

## 2. Vérifier Fleet et la policy

Dans Kibana, ouvrir **Management > Fleet > Agents**. L'Agent doit être
`Healthy` et rattaché à la policy `mongodb-hosts`. Vérifier que les intégrations
System, MongoDB et Kafka sont présentes. PostgreSQL n'appartient pas au profil
Fleet actuel : ses métriques sont collectées par EDOT sur la VM OpenTelemetry.

La création déclarative de la policy est dans
`platform/kubernetes/base/observability/kibana.yaml`. Après une modification de
policy ou de pipeline versionnée, synchroniser sans modifier les secrets :

```bash
make kibana-fleet-config-deploy
make fleet-sync
```

## 3. Distinguer contrôle et données

Une connexion réussie à Fleet Server valide le plan de contrôle ; elle ne
prouve pas que des documents arrivent dans Elasticsearch. Dans Discover,
chercher d'abord les métriques et logs attendus par `host.name`, puis suivre
[Vérifier un signal de bout en bout](verifier-un-signal.md).

L'[architecture Fleet](../architecture-fleet.md) décrit la différence entre
Fleet Server, qui distribue la configuration, et Elasticsearch, qui reçoit
normalement les données de l'Agent.
