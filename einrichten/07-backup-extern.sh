#!/usr/bin/env bash
# Schritt 7: Verschlüsselte Sicherung ausser Haus mit restic (täglich 04:15).
# Ziel: Backblaze B2 (EU, mit Object Lock) oder Hetzner Storage Box. Die Daten werden auf dem
# Server verschlüsselt, bevor sie ihn verlassen. Der Anbieter sieht nur Datensalat.
#
# Erster Aufruf: legt /etc/restic/ziel.env an (Vorlage) und hört auf. Datei ausfüllen, dann nochmal starten.
# Aufruf:  sudo bash /opt/server/einrichten/07-backup-extern.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
. "$(dirname "$0")/_meldung.sh"; installiere_meldung
export DEBIAN_FRONTEND=noninteractive
command -v restic >/dev/null || { apt-get update -q >/dev/null; apt-get install -y -q restic >/dev/null; }

install -d -m 700 /etc/restic
ZIEL=/etc/restic/ziel.env
if [ ! -s "$ZIEL" ]; then
  cat > "$ZIEL" <<'VORLAGE'
# Wohin die Sicherung geht. EINE der beiden Varianten ausfüllen, die andere mit # lassen.

# --- Variante A: Backblaze B2 (Rechenzentrum EU Central) ---
# RESTIC_REPOSITORY=s3:https://s3.eu-central-003.backblazeb2.com/BUCKET-NAME
# AWS_ACCESS_KEY_ID=keyID-vom-Application-Key
# AWS_SECRET_ACCESS_KEY=applicationKey

# --- Variante B: Hetzner Storage Box (SSH-Schlüssel von root muss dort hinterlegt sein) ---
# RESTIC_REPOSITORY=sftp:uXXXXXX@uXXXXXX.your-storagebox.de:restic
VORLAGE
  chmod 600 "$ZIEL"
  echo "Vorlage angelegt: $ZIEL"
  echo "Jetzt ausfüllen:  sudo nano $ZIEL   und dann dieses Skript nochmal starten."
  exit 0
fi
grep -q '^RESTIC_REPOSITORY=' "$ZIEL" || { echo "!! In $ZIEL ist noch keine Variante ausgefüllt."; exit 1; }

# Schlüssel für die Verschlüsselung: einmal zufällig erzeugen. OHNE IHN IST DIE SICHERUNG WERTLOS.
PW=/etc/restic/passwort
NEU_PW=no
if [ ! -s "$PW" ]; then
  head -c 32 /dev/urandom | base64 | tr -d '\n' > "$PW"; chmod 600 "$PW"; NEU_PW=yes
fi

cat > /usr/local/sbin/backup-extern <<'SKRIPT'
#!/usr/bin/env bash
# Verschlüsselte Sicherung ausser Haus. Von Hand:  sudo backup-extern
# Protokoll:  /var/log/backup-extern.log
set -uo pipefail
exec > >(while IFS= read -r z; do printf '%s %s\n' "$(date '+%F %T')" "$z"; done | tee -a /var/log/backup-extern.log) 2>&1
set -a; . /etc/restic/ziel.env; set +a
export RESTIC_PASSWORD_FILE=/etc/restic/passwort RESTIC_CACHE_DIR=/var/cache/restic

# Was gesichert wird. Regel für neue Apps: Daten und Einstellungen unter /opt/<app>, dann sind sie automatisch dabei.
QUELLEN=()
for p in /etc /opt /root /home /var/lib/shoptrail /var/backups/pip; do [ -e "$p" ] && QUELLEN+=("$p"); done

# Frische, konsistente ShopTrail-Kopie (die laufende Datenbank selbst wird ausgelassen).
# Flatora: Die laufende Datenbank /opt/flatora/postgres wird ebenso ausgelassen, die Kopien in /opt/flatora/backup sind dabei.
docker exec shoptrail-server node backup.mjs >/dev/null 2>&1 || echo "Hinweis: ShopTrail-Kopie ging nicht, nehme die letzte."

restic backup --one-file-system --tag taeglich \
  --exclude '/var/lib/shoptrail/*.db' --exclude '/var/lib/shoptrail/*.db-*' \
  --exclude '/opt/flatora/postgres' \
  --exclude 'node_modules' --exclude '/root/.cache' --exclude '/home/*/.cache' \
  "${QUELLEN[@]}"
rc=$?
[ "$rc" -le 3 ] || { echo "!! Sicherung fehlgeschlagen (Code $rc)"; exit 1; }   # 3 = einzelne Datei unlesbar, Rest gesichert

# Aufbewahren: 7 Tage, 4 Wochen, 12 Monate
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune --quiet || echo "!! Aufräumen ging nicht"
# Sonntags einen Teil der Daten wirklich lesen und prüfen
[ "$(date +%u)" = 7 ] && { restic check --read-data-subset=10% --quiet && echo "Prüfung ok" || echo "!! Prüfung meldet Fehler"; }
restic snapshots --latest 1 --compact | tail -3
echo "== fertig"
SKRIPT
chmod 750 /usr/local/sbin/backup-extern

cat > /etc/cron.d/backup-extern <<'CRON'
# Repo "server": verschlüsselte Sicherung ausser Haus, täglich 04:15 (nach der lokalen Sicherung 03:45 und einem möglichen Neustart 04:00)
15 4 * * * root /usr/local/sbin/mit-meldung backup-extern /usr/local/sbin/backup-extern >/dev/null 2>&1
CRON
cat > /etc/logrotate.d/backup-extern <<'ROT'
/var/log/backup-extern.log {
  monthly
  rotate 6
  compress
  missingok
  notifempty
}
ROT

set -a
# shellcheck disable=SC1090
. "$ZIEL"
set +a
export RESTIC_PASSWORD_FILE="$PW"
if restic cat config >/dev/null 2>&1; then
  echo "== Sicherungs-Ablage gibt es schon."
else
  echo "== Neue Sicherungs-Ablage anlegen"
  restic init
fi

echo "== Erste Sicherung (kann ein paar Minuten dauern)"
/usr/local/sbin/backup-extern

if [ "$NEU_PW" = yes ]; then
  echo
  echo "############################################################################"
  echo "  WICHTIG: Diesen Schlüssel JETZT in deinen Passwort-Manager kopieren."
  echo "  Fällt der Server aus, kommst du nur damit an die Sicherung:"
  echo
  echo "  $(cat "$PW")"
  echo
  echo "  Dazu auch den Inhalt von $ZIEL (sudo cat $ZIEL)."
  echo "############################################################################"
fi
