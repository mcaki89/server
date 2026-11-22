#!/usr/bin/env bash
# Schritt 3: Automatische Sicherheits-Updates (auch für Docker), Neustart falls nötig um 04:00.
# Aufruf:  sudo bash /opt/server/einrichten/03-updates.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -q unattended-upgrades >/dev/null

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CONF

cat > /etc/apt/apt.conf.d/52server <<'CONF'
// Repo "server": Docker-Pakete auch automatisch aktualisieren
Unattended-Upgrade::Origins-Pattern {
        "origin=Docker,label=Docker CE";
};
// Falls ein Update einen Neustart braucht: um 04:00, Container starten danach von selbst
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
CONF
# Ersetzt die gleichnamige Einstellung aus der Pip-Einrichtung
rm -f /etc/apt/apt.conf.d/52pip-reboot

echo "== Wöchentlich alte Docker-Images wegräumen (Platz sparen)"
cat > /etc/cron.weekly/docker-aufraeumen <<'CRON'
#!/bin/sh
docker image prune -f >/dev/null 2>&1
docker builder prune -f --filter until=168h >/dev/null 2>&1
CRON
chmod 755 /etc/cron.weekly/docker-aufraeumen

echo "== Protokolle kurz halten (Datenschutz): 14 Tage, höchstens 200 MB"
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/server.conf <<'CONF'
[Journal]
MaxRetentionSec=14day
SystemMaxUse=200M
CONF
rm -f /etc/systemd/journald.conf.d/pip.conf
systemctl restart systemd-journald || true

echo "Probelauf (ändert nichts):"
unattended-upgrade --dry-run 2>&1 | tail -3 || true
echo "Fertig."
