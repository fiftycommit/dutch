# Déploiement Dutch Game

## 🚀 Déploiement manuel (production)

Le déploiement se fait via GitHub Actions, en lançant manuellement le workflow
`Deploy to Production`.

Un merge ou un push sur `main` ne doit pas déployer automatiquement en production :
la CI valide d'abord la branche, puis le déploiement est déclenché séparément.

### Workflow
`.github/workflows/deploy-server.yml` déploie :
- ✅ Frontend Flutter → `/srv/dutch/web/`
- ✅ Backend Node.js → `/srv/dutch/releases/<commit>/`, lien `/srv/dutch/current`
- ✅ Service systemd → `dutch-server.service`
- ✅ Données persistantes → `/srv/dutch/shared/data/`

### Pour déployer

1. Merger uniquement une branche validée en CI.
2. Vérifier que `/opt/dutch-node24/bin/node --version` indique Node.js 24.x.
3. Lancer manuellement le workflow GitHub Actions `Deploy to Production`.

Le workflow GitHub Actions s'occupe du reste.

Le service et les commandes npm de déploiement utilisent le runtime dédié
`/opt/dutch-node24/bin`. La CI utilise également Node 24. Installer une distribution
officielle Node 24 correspondant à l'architecture du serveur, vérifier son SHA-256
avec `SHASUMS256.txt`, puis placer le lien `/opt/dutch-node24` vers cette installation.
Ce runtime est indépendant du Node système utilisé par les autres applications.

## 🔧 Setup initial (une seule fois)

Si tu dois configurer un **nouveau serveur** de zéro :

### 1. Créer un Droplet DigitalOcean
- Ubuntu 24.04 LTS
- 1 GB RAM / 1 vCPU minimum
- Ajouter ta clé SSH

### 2. Configurer le DNS
Pointer `dutch-game.me` vers l'IP du Droplet (enregistrement A)

### 3. Ajouter le secret SSH dans GitHub
1. Va sur GitHub → Settings → Secrets → Actions
2. Ajoute `SSH_PRIVATE_KEY` avec ta clé privée SSH

### 4. Provisionner le serveur
Le provisionnement initial n'est plus automatisé par un script du repo.

À installer/configurer manuellement :
- Node.js 24.x
- systemd (`dutch-server/deploy/dutch-server.service`)
- Nginx
- Redis si tu veux activer le multijoueur partagé multi-instance
- Certbot
- Répertoires de déploiement attendus par GitHub Actions
- Utilisateur et service du bot trainer si tu veux conserver l'entraînement distant

### Secrets GitHub Actions à prévoir pour Redis

Si tu veux activer Redis en production, ajoute aussi :
- `REDIS_ENABLED` : `true`
- `REDIS_URL` : ex. `redis://127.0.0.1:6379` ou URL de ton Redis managé

Le service systemd configure Redis local via `REDIS_ENABLED=true` et
`REDIS_URL=redis://127.0.0.1:6379`. Adapter ces valeurs dans le service si nécessaire.

## 📊 URLs en production

| URL | Description |
|-----|-------------|
| https://dutch-game.me/ | Jeu Flutter (interface principale) |
| https://dutch-game.me/status | Page de monitoring du serveur |
| https://dutch-game.me/health | Health check JSON |
| https://dutch-game.me/rooms | Liste des rooms JSON |

## 🔍 Monitoring

### Vérifier l'état du serveur
```bash
ssh max@88.96.63.215 "systemctl status dutch-server"
```

### Voir les logs
```bash
ssh max@88.96.63.215 "sudo journalctl -u dutch-server -n 100 --no-pager"
```

### Redémarrer manuellement
```bash
ssh max@88.96.63.215 "sudo systemctl restart dutch-server"
```

## 🛡️ Sécurité

Voir `dutch-server/SECURITY.md` pour les détails de sécurité.

Protections en place :
- Rate limiting HTTP (500 req/15min)
- Rate limiting WebSocket (30 conn/min)
- HTTPS/SSL (Let's Encrypt)
- Firewall UFW
- PM2 auto-restart

## 💰 Coûts

- **Serveur** : 6$/mois (Droplet 1GB)
- **Domaine** : ~10-15$/an
- **SSL** : Gratuit (Let's Encrypt)
- **Crédits DigitalOcean** : 200$ = ~33 mois gratuits

## 📝 Notes

- Les déploiements quotidiens se font via **GitHub Actions**
- La config Nginx est automatiquement mise à jour si nécessaire
- L'ancien script `scripts/deploy-server.sh` a été supprimé car il ne reflétait plus l'infra réelle
