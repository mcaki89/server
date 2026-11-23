#!/usr/bin/env bash
# Schritt 8: Mail, wenn eine Sicherung oder ein Container-Update ausbleibt oder fehlschlägt (healthchecks.io).
# Jeder Auftrag meldet sich nach dem Lauf. Kommt die Meldung nicht oder mit Fehler, schickt healthchecks.io eine Mail.
# Aufruf:  sudo bash /opt/server/einrichten/08-meldungen.sh   (fragt nach den drei Ping-Adressen)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
. "$(dirname "$0")/_meldung.sh"; installiere_meldung

ENV=/etc/server-meldungen.env
echo "Ping-Adressen von healthchecks.io einfügen (Form: https://hc-ping.com/…). Leer lassen = unverändert."
for n in SERVER_BACKUP BACKUP_EXTERN CONTAINER_UPDATE; do
  read -r -p "PING_$n: " u
  [ -z "$u" ] && continue
  case "$u" in https://hc-ping.com/*) ;; *) echo "!! Sieht nicht wie eine hc-ping.com-Adresse aus, übersprungen."; continue ;; esac
  touch "$ENV"; chmod 600 "$ENV"
  grep -v "^PING_$n=" "$ENV" > "$ENV.neu" || true
  echo "PING_$n=$u" >> "$ENV.neu"; mv "$ENV.neu" "$ENV"; chmod 600 "$ENV"
done

# Bestehende Cron-Aufträge mit der Meldung versehen (falls die Skripte 04/06/07 noch die alte Form eingerichtet haben)
for pair in server-backup:server-backup container-update:container-update backup-extern:backup-extern; do
  datei=/etc/cron.d/${pair%%:*}; name=${pair##*:}
  [ -f "$datei" ] || continue
  grep -q mit-meldung "$datei" || sed -i "s#root /usr/local/sbin/$name #root /usr/local/sbin/mit-meldung $name /usr/local/sbin/$name #" "$datei"
done

echo "== Test-Meldung an alle eingetragenen Adressen"
grep -E '^PING_' "$ENV" 2>/dev/null | while IFS='=' read -r k u; do
  if curl -fsS -m 10 -o /dev/null --data-raw "Test von der Einrichtung" "$u"; then echo "   $k: ok"; else echo "   $k: !! nicht erreichbar"; fi
done
echo
grep -h mit-meldung /etc/cron.d/server-backup /etc/cron.d/container-update /etc/cron.d/backup-extern 2>/dev/null | sed 's/^/Cron: /'
