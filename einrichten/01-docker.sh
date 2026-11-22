#!/usr/bin/env bash
# Schritt 1: Docker installieren und das gemeinsame Netzwerk "proxy" anlegen.
# Ändert nichts an den laufenden Apps (nginx, pip, shoptrail laufen weiter).
# Aufruf:  sudo bash /opt/server/einrichten/01-docker.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
export DEBIAN_FRONTEND=noninteractive

. /etc/os-release
case "$ID" in
  ubuntu|debian) ;;
  *) echo "Nur für Ubuntu oder Debian gedacht (gefunden: $ID)."; exit 1 ;;
esac

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "== Docker ist schon installiert: $(docker --version)"
else
  echo "== Docker aus der offiziellen Quelle von Docker installieren"
  # Alte oder fremde Pakete würden sich mit dem offiziellen Docker streiten
  for p in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt-get remove -y -q "$p" >/dev/null 2>&1 || true
  done
  apt-get update -q
  apt-get install -y -q ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

echo "== Docker-Grundeinstellungen"
# Protokolle pro Container begrenzen, und Container laufen weiter, wenn Docker selbst ein Update bekommt
if [ ! -s /etc/docker/daemon.json ]; then
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
JSON
  systemctl restart docker
else
  echo "   /etc/docker/daemon.json gibt es schon, lasse sie wie sie ist."
fi
systemctl enable --now docker >/dev/null

echo "== Netzwerk \"proxy\" (Caddy, mcf-web und shoptrail-server treffen sich hier)"
if docker network inspect proxy >/dev/null 2>&1; then
  echo "   gibt es schon."
else
  docker network create proxy >/dev/null && echo "   angelegt."
fi

echo
echo "Fertig. Kontrolle:"
docker --version
docker compose version
docker network ls --filter name=^proxy$
