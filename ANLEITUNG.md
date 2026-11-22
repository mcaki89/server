# Umstellung auf Docker + Caddy

Stand 22.11.2026: Alles ist vorbereitet. Auf dem Server ist noch **nichts** geändert.

Es gehören drei Pull Requests zusammen:

| Repo | PR | Was |
|---|---|---|
| server | dieser | Docker, Netzwerk `proxy`, Caddy, Firewall, SSH, Updates, Backups |
| pips-journey | #14 | Container `mcf-web` (Webseite) und `pip-server` (Spiel), Anleitung `docker/ANLEITUNG-DOCKER.md` |
| shoptrail | #17 | Container `shoptrail-server` |

Die PRs zu mergen ändert am Server nichts. Live geht es erst mit den Befehlen unten.

## Überblick: die Reihenfolge

1. **Teil A – Grundlage** (dieses Repo). Kein Unterbruch, die alten Seiten laufen weiter. Kann man an einem beliebigen Tag machen.
2. **Teil B – Sicherung und Container bauen** (Schritte 1 und 2 aus `ANLEITUNG-DOCKER.md`). Kein Unterbruch.
3. **Teil C – Umschalten** (Schritt 3 aus `ANLEITUNG-DOCKER.md`, dann Caddy starten). Etwa 1–2 Minuten Unterbruch. Am besten abends, wenn wenig los ist.
4. **Teil D – Prüfen und Aufräumen.**

Wenn etwas nicht klappt: unten bei **Zurück**. Die Daten werden nie verschoben, darum ist der alte Stand in einer Minute wieder da.

---

## Teil A – Grundlage (kein Unterbruch)

**A1. Repo auf den Server kopieren.** Auf dem Mac, im Ordner, in dem das Repo `server` liegt:
```bash
scp -r server murat@mcfactory.ch:/tmp/server
```
Dann auf dem Server (`ssh murat@mcfactory.ch`):
```bash
sudo mkdir -p /opt/server && sudo cp -r /tmp/server/. /opt/server/ && rm -rf /tmp/server
```

**A2. Docker und Netzwerk `proxy`:**
```bash
sudo bash /opt/server/einrichten/01-docker.sh
```
Am Ende steht die Docker-Version und eine Zeile mit `proxy`. nginx, Spiel und ShopTrail laufen dabei normal weiter.

**A3. Firewall:**
```bash
sudo bash /opt/server/einrichten/02-firewall.sh
```
Offen sind danach nur noch SSH (22), 80 und 443. Das ist dasselbe wie bisher, nur ohne den nginx-Eintrag.

**A4. Automatische Updates und Backups:**
```bash
sudo bash /opt/server/einrichten/03-updates.sh
sudo bash /opt/server/einrichten/04-backup.sh
```
Das zweite Skript macht gleich eine erste Sicherung und zeigt, wie gross sie ist.

**A5. SSH härten.** Vorher: Das jetzige SSH-Fenster **offen lassen**.
```bash
sudo bash /opt/server/einrichten/05-ssh.sh
```
Danach auf dem Mac ein **zweites** Terminal öffnen und `ssh murat@mcfactory.ch` testen. Geht das, ist alles gut. Geht es nicht, im ersten Fenster `sudo rm /etc/ssh/sshd_config.d/10-server.conf && sudo systemctl reload ssh` und mir Bescheid geben.
Ist noch kein SSH-Schlüssel hinterlegt, bleibt die Passwort-Anmeldung an, und das Skript sagt, was zu tun ist.

## Teil B – Sicherung und Container bauen (kein Unterbruch)

Genau wie in `pips-journey/docker/ANLEITUNG-DOCKER.md`, **Schritt 1** (Sicherung nach `/root/vor-docker`) und **Schritt 2** (Dateien nach `/opt/pips-journey` und `/opt/shoptrail/server`, `.env` anlegen, `docker compose build`).

## Teil C – Umschalten (kurzer Unterbruch)

**C1.** Schritt 3 aus `ANLEITUNG-DOCKER.md`: alte Dienste aus, Container an, nginx aus:
```bash
sudo systemctl disable --now pip shoptrail shoptrail-backup.timer
cd /opt/shoptrail/server/docker && sudo docker compose up -d
cd /opt/pips-journey/docker && sudo docker compose up -d
sudo systemctl disable --now nginx
```

**C2.** Jetzt sind 80 und 443 frei. Caddy starten:
```bash
cd /opt/server/caddy && sudo docker compose up -d
sudo docker logs -f caddy
```
Im Protokoll muss für alle vier Adressen `certificate obtained successfully` kommen (meist nach wenigen Sekunden). Dann mit `Ctrl+C` das Protokoll schliessen, Caddy läuft weiter.

## Teil D – Prüfen und Aufräumen

**D1. Prüfen** (Schritt 4 aus `ANLEITUNG-DOCKER.md`):
```bash
sudo docker ps --format '{{.Names}}  {{.Status}}  {{.Ports}}'
curl -s https://pip.mcfactory.ch/api/health
curl -s https://shoptrail.mcfactory.ch/api/health
curl -sI https://mcfactory.ch | head -1
curl -sI http://www.mcfactory.ch | head -1      # 308 = Umleitung auf https, richtig so
```
Bei `docker ps` darf **nur `caddy`** Ports (80, 443) zeigen. `mcf-web`, `pip-server` und `shoptrail-server` stehen auf "healthy" und ohne Ports.
Dann im Spiel einmal 1 gegen 1 starten (das prüft den WebSocket) und in ShopTrail einmal synchronisieren.

**D2. Aufräumen** (Schritt 5 aus `ANLEITUNG-DOCKER.md`): `pip-admin`, die ShopTrail-Sicherung um 03:30 und `certbot.timer` aus. Die Zertifikate macht jetzt Caddy.

**D3. Nach etwa einer Woche ohne Probleme** kann der alte nginx ganz weg:
```bash
sudo apt-get purge -y nginx nginx-common certbot python3-certbot-nginx && sudo apt-get autoremove -y
```
Erst dann, denn bis dahin braucht ihn der Weg zurück.

## Zurück, falls etwas nicht klappt

```bash
cd /opt/server/caddy && sudo docker compose down
cd /opt/pips-journey/docker && sudo docker compose down
cd /opt/shoptrail/server/docker && sudo docker compose down
sudo systemctl enable --now nginx pip shoptrail shoptrail-backup.timer
```
Docker, Firewall, SSH, Updates und Backups (Teil A) dürfen bleiben, sie stören den alten Stand nicht.

---

## Im Alltag

- **Läuft alles?** `sudo docker ps` · Protokoll von Caddy: `sudo docker logs caddy --tail 50`
- **Caddyfile geändert?** Neue Datei nach `/opt/server/caddy/` kopieren, dann
  `cd /opt/server/caddy && sudo docker compose exec -w /etc/caddy caddy caddy reload` (ohne Unterbruch).
- **Caddy aktualisieren** (etwa einmal im Monat): `cd /opt/server/caddy && sudo docker compose pull && sudo docker compose up -d`
- **System-Updates** kommen von selbst jede Nacht. Braucht ein Update einen Neustart, startet der Server um 04:00 neu und alle Container laufen danach von selbst wieder.
- **Sicherungen:** täglich um 03:45 nach `/var/backups/server/server-DATUM.tgz`, 14 Tage lang. Von Hand: `sudo server-backup`.
  Drin sind: alle Einstellungen (`/etc`, auch die ShopTrail-Zugänge), Caddy samt Zertifikaten, die `.env`-Dateien, die Spiel-Daten und die ShopTrail-Datenbank-Kopien. Die Spiel-Sicherung `/var/backups/pip` läuft wie bisher daneben.
- **Sicherung auf den Mac holen** (empfohlen etwa einmal pro Woche, denn wenn der VPS ganz ausfällt, sind auch die Sicherungen dort weg):
  auf dem Server `sudo cp /var/backups/server/server-$(date +%F).tgz ~/ && sudo chown $USER ~/server-*.tgz`,
  auf dem Mac `scp murat@mcfactory.ch:'server-*.tgz' ~/Backups/`, danach auf dem Server `rm ~/server-*.tgz`.
- **Gesperrte IPs (SSH):** `sudo fail2ban-client status sshd`
