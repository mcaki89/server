#!/usr/bin/env bash
# Schritt 6: Container wöchentlich automatisch aktualisieren (Montag 04:30).
# Holt neue Versionen von Caddy und den Grundbausteinen (nginx, Node, Python, PostgreSQL) und baut die Apps neu.
# Ändert sich nichts, wird auch nichts neu gestartet. Startet ein neuer Container nicht sauber,
# kommt automatisch die vorherige Version zurück.
# Aufruf:  sudo bash /opt/server/einrichten/06-container-updates.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
. "$(dirname "$0")/_meldung.sh"; installiere_meldung

cat > /usr/local/sbin/container-update <<'SKRIPT'
#!/usr/bin/env bash
# Aktualisiert alle Container. Von Hand:  sudo container-update
# Protokoll:  /var/log/container-update.log
set -uo pipefail
LOG=/var/log/container-update.log
exec > >(while IFS= read -r z; do printf '%s %s\n' "$(date '+%F %T')" "$z"; done | tee -a "$LOG") 2>&1

# Ordner mit compose.yaml : Art (pull = fertiges Image holen, build = selbst bauen)
PROJEKTE="${PROJEKTE:-/opt/server/caddy:pull /opt/shoptrail/server/docker:build /opt/pips-journey/docker:build /opt/flatora/docker:build}"
FEHLER=0
# Ohne Zusatz-Angaben (Attestations) bekommt ein unverändertes Image dieselbe ID. Sonst würde jeder Lauf alles neu starten.
export BUILDX_NO_DEFAULT_ATTESTATIONS=1

warte_gesund() {   # Wartet bis zu 90 s, bis alle Container des Projekts laufen und (falls geprüft) "healthy" sind
  local s ok
  for _ in $(seq 1 30); do
    ok=1
    for c in $(docker compose ps -aq); do
      s=$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}healthy{{end}}' "$c")
      [ "$s" = "running healthy" ] || ok=0
    done
    [ "$ok" = 1 ] && return 0
    sleep 3
  done
  return 1
}

for eintrag in $PROJEKTE; do
  dir=${eintrag%:*}; art=${eintrag##*:}
  [ -f "$dir/compose.yaml" ] || { echo "-- $dir: keine compose.yaml, übersprungen"; continue; }
  cd "$dir" || continue
  echo "== $dir"
  bilder=$(docker compose config --images)
  # Bisherige Versionen merken (als :vorher), damit es einen Weg zurück gibt
  for b in $bilder; do docker image inspect "$b" >/dev/null 2>&1 && docker tag "$b" "${b%%:*}:vorher"; done
  alt=$(for b in $bilder; do docker image inspect -f '{{.Id}}' "$b" 2>/dev/null; done)

  if [ "$art" = pull ]; then docker compose pull -q || { echo "!! Holen ging nicht"; FEHLER=1; continue; }
  else
    # Fertige Images im selben Projekt (z. B. die Datenbank von Flatora) auch holen, die selbst gebauten auslassen
    docker compose pull -q --ignore-buildable || { echo "!! Holen ging nicht, alte Version läuft weiter"; FEHLER=1; continue; }
    docker compose build --pull -q || { echo "!! Bauen ging nicht, alte Version läuft weiter"; FEHLER=1; continue; }
  fi
  neu=$(for b in $bilder; do docker image inspect -f '{{.Id}}' "$b" 2>/dev/null; done)
  if [ "$alt" = "$neu" ]; then echo "   nichts Neues"; continue; fi

  echo "   neue Version, starte neu"
  docker compose up -d --remove-orphans
  if warte_gesund; then
    echo "   ok"
  else
    echo "!! Neue Version läuft nicht sauber, nehme die vorherige"
    for b in $bilder; do docker image inspect "${b%%:*}:vorher" >/dev/null 2>&1 && docker tag "${b%%:*}:vorher" "$b"; done
    docker compose up -d --remove-orphans
    warte_gesund && echo "   vorherige Version läuft wieder" || echo "!! Auch die vorherige Version läuft nicht sauber, bitte prüfen"
    FEHLER=1
  fi
done

docker image prune -f >/dev/null 2>&1
[ "$FEHLER" = 0 ] && echo "== fertig" || echo "== fertig, mit Problemen (siehe oben)"
exit "$FEHLER"
SKRIPT
chmod 750 /usr/local/sbin/container-update

cat > /etc/cron.d/container-update <<'CRON'
# Repo "server": Container jeden Montag um 04:30 aktualisieren (nach Sicherung 03:45 und möglichem Neustart 04:00)
30 4 * * 1 root /usr/local/sbin/mit-meldung container-update /usr/local/sbin/container-update >/dev/null 2>&1
CRON
chmod 644 /etc/cron.d/container-update

# Protokoll nicht endlos wachsen lassen
cat > /etc/logrotate.d/container-update <<'ROT'
/var/log/container-update.log {
  monthly
  rotate 6
  compress
  missingok
  notifempty
}
ROT

echo "Eingerichtet. Erster Lauf jetzt:"
/usr/local/sbin/container-update
