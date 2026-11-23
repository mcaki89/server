# shellcheck shell=bash
# Gemeinsamer Teil (wird von den Einrichtungs-Skripten geladen, nicht selbst starten).
# Installiert zwei kleine Helfer:
#   /usr/local/sbin/server-mail    schickt eine Mail über das Postfach aus /etc/server-meldungen.env
#   /usr/local/sbin/mit-meldung    startet einen Auftrag und schickt nur bei einem Fehler eine Mail
# Solange /etc/server-meldungen.env fehlt (Schritt 8 noch nicht gemacht), laufen die Aufträge einfach ohne Mail.
installiere_meldung() {
  cat > /usr/local/sbin/server-mail <<'SKRIPT'
#!/usr/bin/env bash
# Aufruf:  echo "Text" | server-mail "Betreff"
# Liest Postfach und Empfänger aus /etc/server-meldungen.env. Verschlüsselt über SMTPS (Port 465).
set -uo pipefail
ENV=/etc/server-meldungen.env
[ -r "$ENV" ] || { echo "server-mail: $ENV fehlt, keine Mail verschickt" >&2; exit 1; }
wert() {   # Wert aus der Datei lesen, ohne sie auszuführen. Umschliessende ' oder " werden entfernt.
  local v; v=$(grep -E "^$1=" "$ENV" | tail -1 | cut -d= -f2-)
  v=${v#\'}; v=${v%\'}; v=${v#\"}; v=${v%\"}; printf %s "$v"
}
HOST=$(wert SMTP_HOST); PORT=$(wert SMTP_PORT); USR=$(wert SMTP_USER); PASS=$(wert SMTP_PASS)
VON=$(wert MAIL_FROM); AN=$(wert MAIL_TO)
[ -n "$HOST" ] && [ -n "$USR" ] && [ -n "$PASS" ] && [ -n "$AN" ] || { echo "server-mail: Angaben unvollständig in $ENV" >&2; exit 1; }
VON=${VON:-$USR}; PORT=${PORT:-465}
betreff="[$(hostname)] ${1:-Meldung}"
text=$(cat)
# Passwort nicht auf der Befehlszeile (sonst in der Prozessliste sichtbar), sondern über stdin als curl-Einstellung
esc() { local s=${1//\\/\\\\}; printf '%s' "${s//\"/\\\"}"; }
{
  printf 'url = "smtps://%s:%s"\n' "$(esc "$HOST")" "$PORT"
  printf 'user = "%s:%s"\n' "$(esc "$USR")" "$(esc "$PASS")"
  printf 'mail-from = "%s"\n' "$(esc "$VON")"
  printf 'mail-rcpt = "%s"\n' "$(esc "$AN")"
} | curl -sS -m 30 --retry 2 --ssl-reqd --crlf --config - --upload-file <(
  printf 'From: mcfactory Server <%s>\nTo: <%s>\nSubject: %s\nDate: %s\nMIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\n\n%s\n' \
    "$VON" "$AN" "$betreff" "$(LC_ALL=C date -R)" "$text")
SKRIPT
  chmod 750 /usr/local/sbin/server-mail

  cat > /usr/local/sbin/mit-meldung <<'SKRIPT'
#!/usr/bin/env bash
# Aufruf:  mit-meldung NAME BEFEHL [ARGUMENTE…]
# Startet den Befehl. Geht er schief (Exit-Code nicht 0), kommt eine Mail mit den letzten Zeilen der Ausgabe.
name=$1; shift
aus=$(mktemp)
"$@" >"$aus" 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ -r /etc/server-meldungen.env ]; then
  { echo "Der Auftrag \"$name\" ist fehlgeschlagen (Exit-Code $rc) am $(date '+%d.%m.%Y um %H:%M')."
    echo "Von Hand nochmals starten:  sudo $*"
    echo; echo "Letzte Zeilen der Ausgabe:"; echo "--------------------------"
    tail -n 60 "$aus"
  } | /usr/local/sbin/server-mail "Fehler: $name" || logger -t mit-meldung "Mail für $name ging nicht raus"
fi
cat "$aus"; rm -f "$aus"
exit "$rc"
SKRIPT
  chmod 750 /usr/local/sbin/mit-meldung
}
