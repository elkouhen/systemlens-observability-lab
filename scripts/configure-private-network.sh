#!/usr/bin/env bash
set -euo pipefail

private_ip="${1:?adresse IP privee requise}"

# L'adaptateur 1 de VirtualBox est le NAT Vagrant : il doit rester la seule
# route par defaut afin d'utiliser la connexion Internet de l'hote (y compris
# lorsque celle-ci provient d'un partage de connexion mobile).
private_device="$({ ip -o -4 addr show | awk -v ip="$private_ip" '$4 ~ ("^" ip "/") { print $2; exit }'; })"

if [ -z "$private_device" ]; then
  echo "Interface du reseau prive ($private_ip) introuvable" >&2
  exit 1
fi

private_connection="$(nmcli -g GENERAL.CONNECTION device show "$private_device")"

if [ -z "$private_connection" ] || [ "$private_connection" = "--" ]; then
  echo "Profil NetworkManager pour $private_device introuvable" >&2
  exit 1
fi

# Vagrant peut creer ce profil avec un contexte SELinux temporaire. NetworkManager
# ne peut alors plus le mettre a jour de facon atomique.
restorecon -Fv "/etc/NetworkManager/system-connections/${private_connection}.nmconnection"
nmcli connection modify "$private_connection" ipv4.never-default yes
nmcli connection up "$private_connection" ifname "$private_device"

# Certains partages de connexion mobiles fournissent un serveur DNS inutilisable
# aux invites VirtualBox. Le NAT conserve la sortie Internet et utilise ici des
# resolvers publics pour que les installations et Fleet puissent joindre leurs
# depots.
nat_device="$(ip route get 1.1.1.1 | awk '/dev/ { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')"
nat_connection="$(nmcli -g GENERAL.CONNECTION device show "$nat_device")"
nmcli connection modify "$nat_connection" ipv4.ignore-auto-dns yes ipv4.dns '1.1.1.1,9.9.9.9'
nmcli device reapply "$nat_device"

# Les VMs atteignent le k3d de l'hote par l'interface VirtualBox host-only,
# dont l'adresse reste stable meme si le partage de connexion change d'IP.
sed -i '/# poc-elastic-hosts$/d' /etc/hosts
sed -i '/\(kibana\|elasticsearch\|fleet\|apm\|kafka-producer-jolokia\|kafka-consumer-jolokia\)\.poc\.test/d' /etc/hosts
echo '192.168.33.1 kibana.poc.test elasticsearch.poc.test fleet.poc.test apm.poc.test kafka-producer-jolokia.poc.test kafka-consumer-jolokia.poc.test # poc-elastic-hosts' >> /etc/hosts
