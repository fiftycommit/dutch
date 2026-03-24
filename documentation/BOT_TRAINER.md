# Bot Trainer (Dart) - Entraînement 20h → 12h

Le Bot Trainer est un script Dart qui fait jouer les bots en continu sur le serveur pour améliorer les profils.
Il utilise des **fantômes de vrais joueurs** (clones) et envoie des rapports au serveur.

## URLs utiles
- `https://dutch-game.me/api/bot-learning/top-bots`
- `https://dutch-game.me/api/bot-learning/clones`
- `https://dutch-game.me/api/bot-learning/training-series`
- `https://dutch-game.me/bot-stats` (dashboard)

## Déploiement
Le trainer n'est pas installé par le workflow GitHub Actions actuel.

Sur l'infrastructure actuelle, il est déjà provisionné sur le serveur.
Pour un nouveau serveur, il faut reprovisionner manuellement :
- le SDK Flutter côté serveur
- le dossier `/var/www/dutch-trainer`
- le service systemd `dutch-bot-trainer`

## Démarrer / Arrêter à distance
```
chmod +x scripts/start-trainer-remote.sh scripts/stop-trainer-remote.sh
./scripts/start-trainer-remote.sh 164.92.234.245
./scripts/stop-trainer-remote.sh 164.92.234.245
```

## Service système (systemd)
Service : `dutch-bot-trainer`

Vérifier le statut :
```
ssh root@164.92.234.245 "systemctl status --no-pager dutch-bot-trainer"
```

Logs :
```
ssh root@164.92.234.245 "journalctl -u dutch-bot-trainer -f"
```

## Fenêtre horaire
Le trainer tourne **16h/jour**, de **20h à 12h** (heure serveur).
Il reste en veille le reste du temps.

## Variables d’environnement
Définies dans `dutch-bot-trainer.service` :
- `BOT_TRAIN_SERVER` (défaut `https://dutch-game.me`)
- `BOT_TRAIN_START_HOUR` (défaut `20`)
- `BOT_TRAIN_END_HOUR` (défaut `12`)
- `BOT_TRAIN_BATCH` (défaut `4`)
- `BOT_TRAIN_SLEEP_MS` (défaut `1500`)
- `BOT_TRAIN_MAX_TURNS` (défaut `500`)
- `BOT_TRAIN_BALANCED_ONLY` (défaut `true`)

## Graphique de suivi
Le trainer pousse des points de suivi via `POST /api/bot-learning/training-series`.
Le dashboard `bot-stats` affiche un graphique :
- Axe X : Date/Heure
- Axe Y : Taux de victoire des bots (%)

## Fantômes (clones)
Quand un joueur termine **1er ou 2e**, son fantôme est envoyé au serveur :
- `POST /api/bot-learning/clone-player` (création)
- `PUT /api/bot-learning/clone/:id` (mise à jour)

Les fantômes sont ensuite injectés dans les matchs d’entraînement.
