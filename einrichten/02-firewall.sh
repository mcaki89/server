#!/usr/bin/env bash
# Schritt 2: Firewall (ufw). Offen sind nur SSH, 80 und 443.
# Spiel-Ports braucht es keine: Die Online-Runden laufen per WebSocket über 443.
# Aufruf:  sudo bash /opt/server/einrichten/02-firewall.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
export DEBIAN_FRONTEND=noninteractive
command -v ufw >/dev/null || apt-get install -y -q ufw

ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
# SSH zuerst, damit die Verbindung nie abreisst. "limit" bremst Passwort-Rater.
ufw limit OpenSSH >/dev/null
ufw allow 80/tcp comment 'Caddy http (Umleitung, Zertifikate)' >/dev/null
ufw allow 443/tcp comment 'Caddy https + WebSocket' >/dev/null
ufw allow 443/udp comment 'Caddy HTTP/3' >/dev/null
# Die alte Regel von nginx braucht es nicht mehr (80/443 sind oben schon offen)
ufw status | grep -q 'Nginx Full' && ufw delete allow 'Nginx Full' >/dev/null || true
ufw --force enable >/dev/null

echo "Firewall aktiv:"
ufw status verbose
echo
echo "Hinweis: Docker öffnet Ports an ufw vorbei. Darum gibt nur Caddy Ports frei (80/443),"
echo "alle anderen Container haben keine 'ports:' in ihrer compose.yaml. Kontrolle:  sudo docker ps --format '{{.Names}}  {{.Ports}}'"
