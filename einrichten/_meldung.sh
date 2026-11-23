# shellcheck shell=bash
# Gemeinsamer Teil (wird von den Einrichtungs-Skripten geladen, nicht selbst starten).
# Installiert /usr/local/sbin/mit-meldung: startet einen Auftrag und meldet Erfolg oder Fehler an healthchecks.io.
# Ohne eingetragene Adresse in /etc/server-meldungen.env läuft der Auftrag einfach ohne Meldung.
installiere_meldung() {
  cat > /usr/local/sbin/mit-meldung <<'SKRIPT'
#!/usr/bin/env bash
# Aufruf:  mit-meldung NAME BEFEHL [ARGUMENTE…]
# Meldet an die Adresse PING_<NAME> aus /etc/server-meldungen.env (Bindestriche werden zu _ , gross geschrieben).
name=$1; shift
var="PING_$(printf %s "$name" | tr '[:lower:]-' '[:upper:]_')"
url=""
if [ -r /etc/server-meldungen.env ]; then
  url=$(grep -E "^${var}=" /etc/server-meldungen.env | tail -1 | cut -d= -f2- | tr -d "'\" ")
fi
[ -n "$url" ] && curl -fsS -m 10 --retry 3 -o /dev/null "$url/start" || true
aus=$(mktemp)
"$@" >"$aus" 2>&1
rc=$?
# Exit-Code und die letzten Zeilen des Protokolls mitschicken, dann sieht man bei healthchecks.io, was los war
[ -n "$url" ] && tail -c 10000 "$aus" | curl -fsS -m 10 --retry 3 -o /dev/null --data-binary @- "$url/$rc" || true
rm -f "$aus"
exit "$rc"
SKRIPT
  chmod 755 /usr/local/sbin/mit-meldung
}
