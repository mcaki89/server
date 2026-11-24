# server – der VPS mcfactory.ch

Hier liegt alles, was den **ganzen Server** betrifft. Die einzelnen Apps (pips-journey, shoptrail, flatora) haben ihre `compose.yaml` in ihren eigenen Repos.

```
Internet ─► Caddy (dieses Repo, Ports 80/443, holt die Zertifikate selbst)
              │  Docker-Netzwerk "proxy"
              ▼
           mcf-web :8080  (Repo pips-journey)
              ├─ mcfactory.ch, www.mcfactory.ch   → Firmenseite
              ├─ pip.mcfactory.ch                 → Projektseite, /api und /ws → pip-server
              └─ shoptrail.mcfactory.ch           → Projektseite, /api … → shoptrail-server (Repo shoptrail)
           flatora-api :8000  (Repo flatora)
              └─ flatora.ch (www.flatora.ch leitet um)
```

Spiel-Ports gibt es keine: Die Online-Runden laufen per WebSocket über `wss://pip.mcfactory.ch/ws`, also über 443.

## Was wo liegt

| Datei | Wofür |
|---|---|
| `caddy/Caddyfile` | Die vier mcfactory-Adressen → `mcf-web:8080`, flatora.ch → `flatora-api:8000` |
| `caddy/compose.yaml` | Der Caddy-Container (einziger mit Ports nach aussen) |
| `einrichten/01-docker.sh` | Docker installieren, Netzwerk `proxy` anlegen |
| `einrichten/02-firewall.sh` | ufw: nur SSH, 80 und 443 offen |
| `einrichten/03-updates.sh` | Automatische Sicherheits-Updates (auch Docker), Neustart bei Bedarf um 04:00 |
| `einrichten/04-backup.sh` | Tägliche Sicherung nach `/var/backups/server` (14 Tage) |
| `einrichten/05-ssh.sh` | Anmeldung nur mit Schlüssel, fail2ban |
| `einrichten/06-container-updates.sh` | Container jeden Montag 04:30 aktualisieren, bei Problemen zurück auf die alte Version |
| `einrichten/07-backup-extern.sh` | Verschlüsselte Sicherung ausser Haus (restic, Backblaze B2 oder Hetzner), täglich 04:15 |
| `einrichten/08-meldungen.sh` | Mail, wenn Sicherung oder Container-Update fehlschlägt oder die Festplatte über 85 % voll ist |
| `ANLEITUNG.md` | **Umstellung Schritt für Schritt** zusammen mit pips-journey und shoptrail |

Alle Skripte kann man mehrmals laufen lassen, sie richten jedes Mal denselben Stand ein. Auf dem Server liegt das Repo unter `/opt/server`.

## Regel für neue Apps

- compose-Datei im Repo der App, Container im Netzwerk `proxy`, **keine** `ports:` (nur Caddy hat Ports).
- Neue Adresse im `caddy/Caddyfile` eintragen.
- Daten und Einstellungen unter `/opt/<app>`. Dann sind sie automatisch in der Sicherung ausser Haus. Für die tägliche Sicherung (`einrichten/04-backup.sh`) die `.env` und den Ordner mit den Datenbank-Kopien in `LISTE` ergänzen.
- Eine laufende Datenbank nicht direkt sichern, sondern täglich eine Kopie machen lassen (Beispiel: Container `flatora-sicherung`) und den Datenbank-Ordner in `07-backup-extern.sh` auslassen.
- Für die Container-Updates den Ordner in `PROJEKTE` von `einrichten/06-container-updates.sh` ergänzen.
