#!/usr/bin/env bash
# Schritt 4: Tägliche Sicherung des ganzen Servers nach /var/backups/server (14 Tage).
# Die bestehende Spiel-Sicherung /etc/cron.daily/pip-backup bleibt wie sie ist.
# Aufruf:  sudo bash /opt/server/einrichten/04-backup.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
. "$(dirname "$0")/_meldung.sh"; installiere_meldung

cat > /usr/local/sbin/server-backup <<'SKRIPT'
#!/usr/bin/env bash
# Sichert Einstellungen, Zertifikate und App-Daten in eine Datei pro Tag.
# Von Hand:  sudo server-backup
set -uo pipefail
ZIEL=/var/backups/server
TAGE=14
mkdir -p "$ZIEL" && chmod 700 "$ZIEL"
DATEI="$ZIEL/server-$(date +%F).tgz"

# Was gesichert wird (fehlende Ordner werden übersprungen):
#  /etc                          alle Einstellungen, auch /etc/shoptrail/shoptrail.env und SSH-Schlüssel des Servers
#  /opt/server/caddy             Caddyfile und Zertifikate von Caddy
#  /opt/pips-journey/docker/.env und /opt/shoptrail/server/docker/.env
#  /opt/pip-server/data          Rangliste, Käufe, Sperrliste (wie pip-backup)
#  /var/lib/shoptrail/backup     ShopTrail-Datenbank-Kopien (macht shoptrail-server um 03:30 selbst, sicher im laufenden Betrieb)
#  /root/.ssh /home/*/.ssh       hinterlegte Anmelde-Schlüssel
LISTE=()
for p in /etc /opt/server/caddy /opt/pips-journey/docker/.env /opt/shoptrail/server/docker/.env \
         /opt/pip-server/data /var/lib/shoptrail/backup /root/.ssh /home/*/.ssh; do
  [ -e "$p" ] && LISTE+=("$p")
done

tar czf "$DATEI.tmp" --warning=no-file-changed "${LISTE[@]}" 2>/tmp/server-backup.err
rc=$?
# tar meldet 1, wenn sich eine Datei während des Lesens ändert (z. B. Protokolle). Das ist harmlos.
if [ "$rc" -gt 1 ]; then
  echo "!! Sicherung fehlgeschlagen:"; cat /tmp/server-backup.err; rm -f "$DATEI.tmp"; exit 1
fi
mv "$DATEI.tmp" "$DATEI"
chmod 600 "$DATEI"
find "$ZIEL" -name 'server-*.tgz' -mtime +"$TAGE" -delete
echo "Sicherung: $DATEI ($(du -h "$DATEI" | cut -f1)), frei: $(df -h "$ZIEL" | awk 'NR==2{print $4}')"
SKRIPT
chmod 750 /usr/local/sbin/server-backup

cat > /etc/cron.d/server-backup <<'CRON'
# Repo "server": täglich um 03:45 alles sichern (nach der ShopTrail-Kopie um 03:30, vor einem möglichen Update-Neustart um 04:00)
45 3 * * * root /usr/local/sbin/mit-meldung server-backup /usr/local/sbin/server-backup >/dev/null
CRON
chmod 644 /etc/cron.d/server-backup

echo "Erste Sicherung jetzt:"
/usr/local/sbin/server-backup
