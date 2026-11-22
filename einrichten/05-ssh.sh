#!/usr/bin/env bash
# Schritt 5: SSH härten und fail2ban gegen Passwort-Raten.
# Die Passwort-Anmeldung wird nur abgeschaltet, wenn schon ein SSH-Schlüssel hinterlegt ist.
# WICHTIG: Das aktuelle SSH-Fenster offen lassen und in einem ZWEITEN Fenster testen, ob die Anmeldung noch geht.
# Aufruf:  sudo bash /opt/server/einrichten/05-ssh.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo starten."; exit 1; }
export DEBIAN_FRONTEND=noninteractive

hat_schluessel=no
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
  [ -s "$f" ] && hat_schluessel=yes
done

if [ "$hat_schluessel" = yes ]; then
  cat > /etc/ssh/sshd_config.d/10-server.conf <<'CONF'
# Repo "server": Anmeldung nur mit Schlüssel
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
CONF
  # Die alte Datei aus der Pip-Einrichtung hat dieselben Werte, darum weg damit (sonst zwei Stellen)
  rm -f /etc/ssh/sshd_config.d/10-pip.conf
  if sshd -t; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd
    echo "SSH: Anmeldung nur noch mit Schlüssel."
  else
    echo "!! SSH-Einstellung fehlerhaft, nichts neu geladen."; rm -f /etc/ssh/sshd_config.d/10-server.conf; exit 1
  fi
else
  echo "!! Noch kein SSH-Schlüssel hinterlegt. Passwort-Anmeldung bleibt an, sonst sperrst du dich aus."
  echo "   Auf dem Mac:  ssh-copy-id murat@mcfactory.ch   und dann dieses Skript nochmal starten."
fi

echo "== fail2ban (sperrt eine IP nach 5 Fehlversuchen für 1 Stunde)"
command -v fail2ban-client >/dev/null || apt-get install -y -q fail2ban
cat > /etc/fail2ban/jail.d/server.local <<'CONF'
[sshd]
enabled = true
maxretry = 5
findtime = 10m
bantime = 1h
CONF
rm -f /etc/fail2ban/jail.d/pip.local
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban
sleep 1
fail2ban-client status sshd | head -5 || true
