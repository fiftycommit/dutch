# Déploiement DigitalOcean - Serveur Dutch Multiplayer

Guide de déploiement haute performance sur DigitalOcean Droplet.

## 1. Créer le Droplet

### Configuration recommandée

**Pour démarrer (suffisant pour 50-100 parties simultanées):**
- **Image:** Ubuntu 24.04 LTS
- **Plan:** Basic Droplet
  - 1 GB RAM / 1 vCPU / 25 GB SSD (~6$/mois)
  - Ou 2 GB RAM / 1 vCPU / 50 GB SSD (~12$/mois) pour plus de marge
- **Datacenter:** Choisir le plus proche de vos joueurs
  - Europe: Frankfurt (FRA1) ou Amsterdam (AMS3)
  - Amérique du Nord: New York (NYC1) ou Toronto (TOR1)
- **Options additionnelles:**
  - ✅ Monitoring (gratuit)
  - ✅ IPv6
  - ❌ Backups (4$/mois - optionnel, à activer plus tard)

### Accès SSH

Deux méthodes possibles:

**Méthode 1: Clé SSH (recommandé)**
```bash
# Générer une clé SSH si vous n'en avez pas
ssh-keygen -t ed25519 -C "votre-email@example.com"

# Copier la clé publique
cat ~/.ssh/id_ed25519.pub

# Ajouter cette clé dans DigitalOcean lors de la création du Droplet
```

**Méthode 2: Mot de passe**
- DigitalOcean vous enverra le mot de passe root par email

## 2. Configuration initiale du serveur

### Se connecter au Droplet

```bash
ssh root@VOTRE_IP_DROPLET
```

### Mettre à jour le système

```bash
apt update && apt upgrade -y
```

### Installer Node.js 20.x (LTS)

```bash
# Installer curl si nécessaire
apt install -y curl

# Ajouter le dépôt NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

# Installer Node.js et npm
apt install -y nodejs

# Vérifier l'installation
node --version  # Devrait afficher v20.x.x
npm --version
```

### Installer les outils essentiels

```bash
# Git pour cloner le repo
apt install -y git

# PM2 pour gérer le processus Node.js
npm install -g pm2

# Nginx pour reverse proxy et SSL
apt install -y nginx

# Certbot pour les certificats SSL gratuits
apt install -y certbot python3-certbot-nginx
```

### Créer un utilisateur non-root (sécurité)

```bash
# Créer l'utilisateur dutch
adduser dutch

# Ajouter aux sudoers
usermod -aG sudo dutch

# Copier la clé SSH (si vous en utilisez une)
rsync --archive --chown=dutch:dutch ~/.ssh /home/dutch
```

### Se connecter avec le nouvel utilisateur

```bash
# Déconnectez-vous puis reconnectez-vous
exit
ssh dutch@VOTRE_IP_DROPLET
```

## 3. Déployer le serveur Node.js

### Cloner le repository

**Option A: Depuis Git (recommandé pour production)**

```bash
# Créer le répertoire pour l'application
mkdir -p ~/apps
cd ~/apps

# Cloner votre repo (remplacer par votre URL)
git clone https://github.com/VOTRE_USERNAME/dutch-game.git
cd dutch-game/dutch-server
```

**Option B: Upload manuel (pour tester rapidement)**

Depuis votre machine locale:
```bash
# Créer une archive du serveur
cd /Users/maxmbey/projets/dutch
tar -czf dutch-server.tar.gz dutch-server/

# Uploader via SCP
scp dutch-server.tar.gz dutch@VOTRE_IP_DROPLET:~/

# Sur le Droplet
ssh dutch@VOTRE_IP_DROPLET
mkdir -p ~/apps
cd ~/apps
tar -xzf ~/dutch-server.tar.gz
cd dutch-server
```

### Installer les dépendances

```bash
cd ~/apps/dutch-server  # ou ~/apps/dutch-game/dutch-server
npm install --production
```

### Compiler TypeScript

```bash
npm run build
```

### Configurer les variables d'environnement

```bash
# Créer le fichier .env
nano .env
```

Contenu du fichier `.env`:
```env
PORT=3000
NODE_ENV=production
```

Sauvegarder avec `Ctrl+O`, puis `Enter`, puis `Ctrl+X`.

## 4. Configuration Nginx (Reverse Proxy)

Nginx va gérer:
- Le reverse proxy vers Node.js
- Les certificats SSL
- L'optimisation WebSocket

### Créer la configuration Nginx

```bash
sudo nano /etc/nginx/sites-available/dutch-server
```

Contenu (remplacer `votre-domaine.com` par votre domaine):

```nginx
# Configuration optimisée pour Socket.IO
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

upstream dutch_backend {
    # Activer keepalive pour réutiliser les connexions
    keepalive 64;
    server 127.0.0.1:3000;
}

server {
    listen 80;
    listen [::]:80;
    server_name votre-domaine.com www.votre-domaine.com;

    # Redirection vers HTTPS (sera activée après Let's Encrypt)
    # return 301 https://$server_name$request_uri;

    # Temporairement, proxy direct (avant SSL)
    location / {
        proxy_pass http://dutch_backend;
        proxy_http_version 1.1;

        # Headers standard
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Headers pour WebSocket (Socket.IO)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # Timeouts pour connexions longues
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Désactiver le buffering pour temps réel
        proxy_buffering off;
    }

    # Endpoint de santé
    location /health {
        proxy_pass http://dutch_backend/health;
        access_log off;
    }
}
```

### Activer la configuration

```bash
# Créer le lien symbolique
sudo ln -s /etc/nginx/sites-available/dutch-server /etc/nginx/sites-enabled/

# Supprimer le site par défaut
sudo rm /etc/nginx/sites-enabled/default

# Tester la configuration
sudo nginx -t

# Recharger Nginx
sudo systemctl reload nginx
```

## 5. Configuration PM2 (Process Manager)

PM2 va:
- Gérer le processus Node.js
- Redémarrer automatiquement en cas de crash
- Activer le clustering (multi-core)
- Logger les erreurs

### Créer le fichier de configuration PM2

```bash
cd ~/apps/dutch-server
nano ecosystem.config.js
```

Contenu:

```javascript
module.exports = {
  apps: [{
    name: 'dutch-server',
    script: './dist/index.js',
    instances: 'max',  // Utilise tous les cores CPU
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    max_memory_restart: '500M',  // Redémarre si > 500MB RAM
    watch: false,
    // Socket.IO clustering nécessite sticky sessions
    // Sera géré par Socket.IO lui-même
  }]
};
```

### Créer le dossier logs

```bash
mkdir -p logs
```

### Démarrer l'application

```bash
# Démarrer avec PM2
pm2 start ecosystem.config.js

# Vérifier le statut
pm2 status

# Voir les logs en temps réel
pm2 logs dutch-server

# Sauvegarder la configuration PM2
pm2 save

# Configurer PM2 pour démarrer au boot
pm2 startup
# Exécuter la commande affichée (avec sudo)
```

## 6. Configuration DNS

### Pointer votre domaine vers le Droplet

Dans votre registrar de domaine (ex: Namecheap, GoDaddy, etc.):

1. Créer un enregistrement **A** :
   - Host: `@` (ou votre sous-domaine, ex: `api`)
   - Value: `VOTRE_IP_DROPLET`
   - TTL: 300 ou Automatique

2. Si vous utilisez www, créer un enregistrement **CNAME**:
   - Host: `www`
   - Value: `votre-domaine.com`

**Temps de propagation:** 5 minutes à 48 heures (généralement ~30 min)

Vérifier avec:
```bash
dig votre-domaine.com
```

## 7. Configuration SSL avec Let's Encrypt

Une fois le DNS propagé:

```bash
# Obtenir le certificat SSL (remplacer l'email et le domaine)
sudo certbot --nginx -d votre-domaine.com -d www.votre-domaine.com --email votre@email.com --agree-tos --no-eff-email

# Le certificat sera automatiquement renouvelé tous les 90 jours
```

Certbot modifiera automatiquement votre configuration Nginx pour:
- Activer HTTPS sur le port 443
- Rediriger HTTP → HTTPS
- Configurer les certificats SSL

### Tester le renouvellement automatique

```bash
sudo certbot renew --dry-run
```

## 8. Optimisation des performances

### Augmenter les limites système

```bash
sudo nano /etc/security/limits.conf
```

Ajouter à la fin:
```
*    soft nofile 65536
*    hard nofile 65536
root soft nofile 65536
root hard nofile 65536
```

```bash
sudo nano /etc/sysctl.conf
```

Ajouter:
```
# Optimisations réseau pour Socket.IO
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
```

Appliquer:
```bash
sudo sysctl -p
```

### Configuration Nginx avancée

```bash
sudo nano /etc/nginx/nginx.conf
```

Modifier:
```nginx
user www-data;
worker_processes auto;  # Utilise tous les cores
pid /run/nginx.pid;

events {
    worker_connections 4096;  # Augmenté pour Socket.IO
    use epoll;
    multi_accept on;
}

http {
    # ... (garder les autres paramètres)

    # Optimisations
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 100;

    # Compression (désactivée pour WebSocket par défaut)
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css application/json application/javascript;

    # ... (reste de la config)
}
```

Recharger:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

## 9. Mise à jour du client Flutter

### Modifier l'URL du serveur

```bash
nano lib/services/multiplayer_service.dart
```

Changer:
```dart
static const String _serverUrl = 'https://votre-domaine.com';
```

### Recompiler l'application

```bash
cd /Users/maxmbey/projets/dutch

# iOS
flutter build ios --release

# Android
flutter build apk --release
```

## 10. Monitoring et maintenance

### Logs serveur

```bash
# Logs PM2
pm2 logs dutch-server

# Logs Nginx
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Logs système
sudo journalctl -u nginx -f
```

### Monitoring avec PM2

```bash
# Dashboard interactif
pm2 monit

# Statistiques
pm2 show dutch-server
```

### Commandes utiles

```bash
# Redémarrer l'app
pm2 restart dutch-server

# Recharger sans downtime
pm2 reload dutch-server

# Arrêter l'app
pm2 stop dutch-server

# Voir les métriques
pm2 describe dutch-server
```

### Mettre à jour le serveur

```bash
cd ~/apps/dutch-server

# Si depuis Git
git pull origin main
npm install --production
npm run build
pm2 reload dutch-server

# Si upload manuel
# Upload le nouveau tar.gz, puis:
tar -xzf ~/dutch-server.tar.gz
cd dutch-server
npm install --production
npm run build
pm2 reload dutch-server
```

## 11. Sécurité

### Firewall (UFW)

```bash
# Activer UFW
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable

# Vérifier le statut
sudo ufw status
```

### Fail2Ban (protection brute force)

```bash
# Installer Fail2Ban
sudo apt install -y fail2ban

# Créer la configuration
sudo nano /etc/fail2ban/jail.local
```

Contenu:
```ini
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true

[nginx-http-auth]
enabled = true
```

```bash
# Démarrer Fail2Ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### Mises à jour automatiques de sécurité

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

## 12. Backup (optionnel)

### Activer les Snapshots DigitalOcean

Dans le panneau DigitalOcean:
1. Aller dans votre Droplet
2. Snapshots → Enable Automatic Backups (4$/mois)
3. Fréquence: Hebdomadaire

### Backup manuel des données

```bash
# Créer un script de backup
nano ~/backup.sh
```

Contenu:
```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=~/backups
mkdir -p $BACKUP_DIR

# Backup de l'application
tar -czf $BACKUP_DIR/dutch-server-$DATE.tar.gz ~/apps/dutch-server

# Garder seulement les 7 derniers backups
ls -t $BACKUP_DIR/dutch-server-*.tar.gz | tail -n +8 | xargs -r rm

echo "Backup créé: dutch-server-$DATE.tar.gz"
```

```bash
# Rendre le script exécutable
chmod +x ~/backup.sh

# Ajouter au cron (backup quotidien à 3h du matin)
crontab -e
```

Ajouter:
```
0 3 * * * /home/dutch/backup.sh >> /home/dutch/backup.log 2>&1
```

## 13. Tester le déploiement

### Test de connexion

```bash
# Test HTTP
curl http://votre-domaine.com/health

# Test HTTPS
curl https://votre-domaine.com/health

# Résultat attendu
{"status":"ok","rooms":0}
```

### Test Socket.IO

Depuis votre app Flutter, créer une room et vérifier dans les logs:

```bash
pm2 logs dutch-server --lines 50
```

Vous devriez voir:
```
Client connected: <socket_id>
Room created: ABC123 by <socket_id>
```

## 14. Scaling (quand nécessaire)

### Quand scaler ?

Monitorer avec `pm2 monit`:
- CPU > 80% constant → Augmenter les vCPUs
- RAM > 80% constant → Augmenter la RAM
- Latence réseau élevée → Redéployer dans une région plus proche

### Resize du Droplet

Dans DigitalOcean:
1. Droplet → Resize
2. Choisir un plan supérieur
3. Le Droplet sera redémarré (downtime ~5 min)

Plans recommandés:
- **6$/mois**: 1 GB RAM / 1 vCPU (50-100 parties)
- **12$/mois**: 2 GB RAM / 1 vCPU (100-200 parties)
- **18$/mois**: 2 GB RAM / 2 vCPUs (200-500 parties)
- **24$/mois**: 4 GB RAM / 2 vCPUs (500-1000 parties)

### Load Balancing (pour très gros trafic)

Si vous dépassez 1000 parties simultanées:
1. Créer plusieurs Droplets
2. Utiliser DigitalOcean Load Balancer
3. Configuration sticky sessions pour Socket.IO

## 15. Coûts estimés

### Configuration de démarrage

| Service | Prix/mois | Description |
|---------|-----------|-------------|
| Droplet Basic (1GB) | 6$ | Serveur principal |
| Domaine | 10-15$/an | Votre domaine (.com) |
| SSL | Gratuit | Let's Encrypt |
| Monitoring | Gratuit | DigitalOcean Monitoring |

**Total: ~7$/mois + domaine (1-2$/mois)**

Avec vos 200$ de crédits = **~28 mois d'hébergement** !

### Avec backups (recommandé en production)

| Service | Prix/mois |
|---------|-----------|
| Droplet + Backups | 10$ |
| Domaine | 1-2$ |

**Total: ~11-12$/mois**

## Troubleshooting

### Le serveur ne démarre pas

```bash
# Vérifier les logs
pm2 logs dutch-server --lines 100

# Vérifier la compilation TypeScript
cd ~/apps/dutch-server
npm run build

# Vérifier les permissions
ls -la dist/
```

### Nginx ne proxy pas correctement

```bash
# Vérifier la config
sudo nginx -t

# Vérifier les logs
sudo tail -f /var/log/nginx/error.log

# Tester la connexion locale
curl http://localhost:3000/health
```

### Socket.IO ne se connecte pas

1. Vérifier le firewall:
```bash
sudo ufw status
```

2. Vérifier la config Nginx WebSocket:
```bash
sudo nano /etc/nginx/sites-available/dutch-server
# Vérifier les headers Upgrade et Connection
```

3. Tester directement le serveur (bypass Nginx):
```bash
# Temporairement, autoriser le port 3000
sudo ufw allow 3000
# Tester depuis l'app en changeant l'URL vers http://VOTRE_IP:3000
```

### Certificat SSL ne fonctionne pas

```bash
# Vérifier le statut Certbot
sudo certbot certificates

# Renouveler manuellement
sudo certbot renew --force-renewal

# Vérifier la config Nginx
sudo nano /etc/nginx/sites-available/dutch-server
```

## Ressources

- [DigitalOcean Documentation](https://docs.digitalocean.com/)
- [PM2 Documentation](https://pm2.keymetrics.io/docs/)
- [Nginx WebSocket Proxy](https://nginx.org/en/docs/http/websocket.html)
- [Socket.IO Deployment](https://socket.io/docs/v4/deployment/)
- [Let's Encrypt](https://letsencrypt.org/)

## Support

En cas de problème:
1. Vérifier les logs (PM2, Nginx, système)
2. Tester le endpoint `/health`
3. Vérifier la configuration DNS
4. Consulter la documentation DigitalOcean
