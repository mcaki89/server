#!/usr/bin/env bash
# Schritt 8: Mail, wenn eine Sicherung oder ein Container-Update fehlschlägt oder die Festplatte voll wird.
# Verschickt wird über das bestehende Postfach (dieselben SMTP-Angaben wie ShopTrail), ohne Drittanbieter.
# Aufruf:  sudo bash /opt/server/einrichten/08-meldungen.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
. "$(dirname "$0")/_meldung.sh"; installiere_meldung

ENV=/etc/server-meldungen.env
QUELLE=/etc/shoptrail/shoptrail.env
if [ ! -f "$ENV" ]; then
  [ -r "$QUELLE" ] || { echo "!! $QUELLE fehlt. SMTP-Angaben bitte von Hand in $ENV eintragen (siehe ANLEITUNG)."; exit 1; }
  # Postfach-Angaben von ShopTrail übernehmen. Das Passwort wird nur kopiert, nie angezeigt.
  umask 077
  grep -E '^SMTP_(HOST|PORT|USER|PASS)=' "$QUELLE" > "$ENV"
  absender=$(grep -E '^SMTP_FROM=' "$QUELLE" | tail -1 | grep -oE '[^<> ]+@[^<> ]+' | head -1 || true)
  echo "MAIL_FROM=${absender:-$(grep -E '^SMTP_USER=' "$QUELLE" | cut -d= -f2- | tr -d "'\"")}" >> "$ENV"
fi
chmod 600 "$ENV"

aktuell=$(grep -E '^MAIL_TO=' "$ENV" | cut -d= -f2- || true)
read -r -p "An welche Adresse sollen Fehler-Mails gehen? [${aktuell:-info@mcfactory.ch}] " an
an=${an:-${aktuell:-info@mcfactory.ch}}
case "$an" in *@*.*) ;; *) echo "!! Das sieht nicht wie eine Mail-Adresse aus."; exit 1 ;; esac
grep -v '^MAIL_TO=' "$ENV" > "$ENV.neu" || true
echo "MAIL_TO=$an" >> "$ENV.neu"; mv "$ENV.neu" "$ENV"; chmod 600 "$ENV"

# Bestehende Cron-Aufträge mit der Meldung versehen (falls 04/06/07 noch die alte Form eingerichtet haben)
for name in server-backup container-update backup-extern; do
  datei=/etc/cron.d/$name
  [ -f "$datei" ] || continue
  grep -q mit-meldung "$datei" || sed -i "s#root /usr/local/sbin/$name#root /usr/local/sbin/mit-meldung $name /usr/local/sbin/$name#" "$datei"
done

# Täglich prüfen, ob die Festplatte voll wird (ab 85 %)
cat > /usr/local/sbin/platz-pruefen <<'SKRIPT'
#!/usr/bin/env bash
voll=$(df --output=pcent / | tail -1 | tr -dc 0-9)
[ "$voll" -lt 85 ] && exit 0
echo "Die Festplatte ist zu ${voll} % voll."; echo; df -h /; echo
echo "Grösste Ordner unter /var:"; du -xsh /var/* 2>/dev/null | sort -rh | head -8
exit 1
SKRIPT
chmod 750 /usr/local/sbin/platz-pruefen
cat > /etc/cron.d/platz-pruefen <<'CRON'
# Repo "server": täglich um 08:00 prüfen, ob die Festplatte voll wird (Mail ab 85 %)
0 8 * * * root /usr/local/sbin/mit-meldung platz-pruefen /usr/local/sbin/platz-pruefen >/dev/null 2>&1
CRON
chmod 644 /etc/cron.d/platz-pruefen

echo "== Test-Mail an $an"
if echo "Test von der Einrichtung: Fehler-Mails vom Server kommen bei dir an. Du musst nichts tun." \
   | /usr/local/sbin/server-mail "Test: Fehler-Mails eingerichtet"; then
  echo "   verschickt. Bitte im Postfach (und im Spam-Ordner) nachsehen."
else
  echo "!! Test-Mail ging nicht raus, siehe Meldung oben."
fi
echo
grep -h mit-meldung /etc/cron.d/server-backup /etc/cron.d/container-update /etc/cron.d/backup-extern /etc/cron.d/platz-pruefen 2>/dev/null | sed 's/^/Cron: /' || true
