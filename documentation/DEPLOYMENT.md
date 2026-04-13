# Déploiement Dutch Game

## 🚀 Déploiement automatique (production)

Le déploiement se fait automatiquement via GitHub Actions à chaque push sur `main`.

### Workflow
`.github/workflows/deploy-server.yml` déploie :
- ✅ Frontend Flutter → `/var/www/dutch/web/`
- ✅ Backend Node.js → `/root/apps/dutch-server/`
- ✅ Configuration Nginx (si nécessaire)
- ✅ Redémarrage PM2

### Pour déployer
```bash
git add .
git commit -m "Your changes"
git push origin main
```

Le workflow GitHub Actions s'occupe du reste !

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
- Node.js 20.x
- PM2
- Nginx
- Redis si tu veux activer le multijoueur partagé multi-instance
- Certbot
- Répertoires de déploiement attendus par GitHub Actions
- Utilisateur et service du bot trainer si tu veux conserver l'entraînement distant

### Secrets GitHub Actions à prévoir pour Redis

Si tu veux activer Redis en production, ajoute aussi :
- `REDIS_ENABLED` : `true`
- `REDIS_URL` : ex. `redis://127.0.0.1:6379` ou URL de ton Redis managé

Le workflow de déploiement les injecte maintenant dans PM2. Sans ces secrets, le serveur reste en mode local sans Redis.

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
ssh root@dutch-game.me "pm2 status"
```

### Voir les logs
```bash
ssh root@dutch-game.me "pm2 logs dutch-server"
```

### Redémarrer manuellement
```bash
ssh root@dutch-game.me "pm2 restart dutch-server"
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
