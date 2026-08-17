#!/usr/bin/env bash
# Installe ou redemarre Elastic Agent Fleet sur une VM. Le token est fourni par
# Vagrant au moment du provisionnement et n'est jamais ecrit dans le depot.
set -euo pipefail

enrollment_token="${1:?Token Fleet requis}"
agent_version="${ELASTIC_AGENT_VERSION:-9.5.1}"
fleet_url="${FLEET_URL:-https://fleet.poc.test}"

if systemctl is-active --quiet elastic-agent; then
  echo "Elastic Agent is already running"
  exit 0
fi

if [[ -x /opt/Elastic/Agent/elastic-agent ]]; then
  systemctl enable --now elastic-agent
  echo "Elastic Agent restarted"
  exit 0
fi

case "$(uname -m)" in
  aarch64|arm64) agent_arch="arm64" ;;
  x86_64|amd64) agent_arch="x86_64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
archive="elastic-agent-${agent_version}-linux-${agent_arch}.tar.gz"
curl --fail --location --silent --show-error \
  "https://artifacts.elastic.co/downloads/beats/elastic-agent/${archive}" \
  -o "${work_dir}/${archive}"
tar -xzf "${work_dir}/${archive}" -C "${work_dir}"
"${work_dir}/elastic-agent-${agent_version}-linux-${agent_arch}/elastic-agent" install \
  --non-interactive --url="${fleet_url}" --enrollment-token="${enrollment_token}" --insecure
