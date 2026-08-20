# Scripts partagés des VM

Ce dossier ne contient que les utilitaires d'infrastructure commune, hors ELK
Kubernetes. Les scripts Elastic/Kibana sont dans `platform/elk/scripts/`.

## Fichiers

- `cluster-status.sh` : vérifie les conteneurs, le replica set MongoDB et le
  quorum Kafka dans les trois VM.
- `check-kafka-jolokia.sh` : contrôle que Jolokia expose les MBeans requis par
  les streams Kafka de la policy Fleet.
- `mongodb-elk-workload.js` : génère une charge MongoDB pour observer le flux
  dans Elastic.

Lire d'abord `ansible/README.md` pour comprendre ce que ces scripts vérifient.

## Documentation externe

- [Vagrant CLI](https://developer.hashicorp.com/vagrant/docs/cli)
- [MongoDB replica sets](https://www.mongodb.com/docs/manual/replication/)
- [Kafka KRaft](https://kafka.apache.org/documentation/#kraft)
