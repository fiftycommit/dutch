#!/bin/bash

# Script de déploiement automatique du serveur Dutch Game
# Usage: ./deploy-server.sh <ip_droplet> [email]

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Variables
SERVER_IP="$1"
ADMIN_EMAIL="${2:-admin@dutch-game.me}"
DOMAIN="dutch-game.me"

if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}❌ Usage: ./deploy-server.sh <ip_droplet> [email]${NC}"
    echo ""
    echo "Exemple:"
    echo "  ./deploy-server.sh 164.92.234.245"
    echo "  ./deploy-server.sh 164.92.234.245 votre@email.com"
    exit 1
fi

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🚀 Déploiement automatique Dutch Game Server${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  📍 Serveur: ${YELLOW}$SERVER_IP${NC}"
echo -e "  🌐 Domaine: ${YELLOW}$DOMAIN${NC}"
echo -e "  📧 Email: ${YELLOW}$ADMIN_EMAIL${NC}"
echo ""

# Créer le script d'installation côté serveur
cat > /tmp/setup-server.sh <<'REMOTE_SCRIPT'
#!/bin/bash
set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📦 Vérification des dépendances${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

SHOULD_UPDATE=false

# Vérifier Node.js
if ! command -v node >/dev/null 2>&1; then
    echo -e "\n${YELLOW}📥 Installation de Node.js...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
    SHOULD_UPDATE=true
else
    echo -e "✅ Node.js déjà installé ($(node -v))"
fi

# Vérifier Git
if ! command -v git >/dev/null 2>&1; then
    echo -e "\n${YELLOW}📥 Installation de Git...${NC}"
    apt install -y git
else
    echo -e "✅ Git déjà installé"
fi

# Vérifier PM2
if ! command -v pm2 >/dev/null 2>&1; then
    echo -e "\n${YELLOW}📥 Installation de PM2...${NC}"
    npm install -g pm2
else
    echo -e "✅ PM2 déjà installé"
fi

# Vérifier Nginx
if ! command -v nginx >/dev/null 2>&1; then
    echo -e "\n${YELLOW}📥 Installation de Nginx...${NC}"
    apt install -y nginx
else
    echo -e "✅ Nginx déjà installé"
fi

# Vérifier Certbot
if ! command -v certbot >/dev/null 2>&1; then
    echo -e "\n${YELLOW}📥 Installation de Certbot...${NC}"
    apt install -y certbot python3-certbot-nginx
else
    echo -e "✅ Certbot déjà installé"
fi

# Créer l'utilisateur dutch si inexistant
if ! id -u dutch > /dev/null 2>&1; then
    echo -e "\n${YELLOW}👤 Création de l'utilisateur dutch...${NC}"
    useradd -m -s /bin/bash dutch
    usermod -aG sudo dutch
    echo "dutch ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/dutch
else
    echo -e "✅ Utilisateur dutch existant"
fi

# Créer le répertoire de l'application
mkdir -p /var/www/dutch-server
chown -R root:root /var/www/dutch-server

echo -e "\n${GREEN}✓ Vérification des dépendances terminée!${NC}"
REMOTE_SCRIPT

# Uploader et exécuter le script d'installation
echo -e "${YELLOW}📤 Upload du script de vérification...${NC}"
scp -o StrictHostKeyChecking=no /tmp/setup-server.sh root@$SERVER_IP:/tmp/

echo -e "${YELLOW}⚙️  Vérification de l'environnement...${NC}"
ssh -o StrictHostKeyChecking=no root@$SERVER_IP 'bash /tmp/setup-server.sh'

# Créer l'archive du serveur
echo -e "\n${YELLOW}📦 Création de l'archive du serveur...${NC}"
cd /Users/maxmbey/projets/dutch
COPYFILE_DISABLE=1 tar --exclude='.DS_Store' -czf /tmp/dutch-server.tar.gz dutch-server/

# Uploader le code (en tant que root, puis on change les permissions)
echo -e "${YELLOW}📤 Upload du code serveur...${NC}"
scp /tmp/dutch-server.tar.gz root@$SERVER_IP:/var/www/

# Décompresser et installer sur le serveur
echo -e "${YELLOW}📦 Installation du code serveur...${NC}"
ssh root@$SERVER_IP << 'INSTALL_CODE'
set -e
cd /var/www
rm -rf dutch-server
tar -xzf dutch-server.tar.gz
cd dutch-server

# Installer TOUTES les dépendances (y compris typescript)
echo "📦 Installation des paquets NPM..."
npm install

# Compiler TypeScript
echo "🔨 Compilation..."
npm run build

# Nettoyer les dépendances de développement pour la prod
echo "🧹 Nettoyage..."
npm prune --production

# Installer les dépendances de production manquantes
echo "📦 Installation des dépendances de production..."
npm install express-rate-limit rate-limiter-flexible

# Créer le fichier .env
cat > .env << ENV
PORT=3000
NODE_ENV=production
ENV

# Créer le dossier logs
mkdir -p logs

echo "✓ Code installé et compilé"
INSTALL_CODE

# Configurer Nginx
echo -e "\n${YELLOW}🔧 Configuration de Nginx...${NC}"

cat > /tmp/nginx-dutch << NGINX_CONFIG
# Configuration optimisée pour Socket.IO + Flutter Web SPA
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}

upstream dutch_backend {
    keepalive 64;
    server 127.0.0.1:3000;
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    # Racine pour le frontend Flutter (SPA)
    root /var/www/dutch/web;
    index index.html;

    # API et WebSocket -> Backend Node.js
    location /socket.io/ {
        proxy_pass http://dutch_backend;
        proxy_http_version 1.1;

        # Headers standard
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Headers pour WebSocket
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Désactiver le buffering
        proxy_buffering off;
    }

    location /health {
        proxy_pass http://dutch_backend/health;
        access_log off;
    }

    # Routes API -> Backend (si tu en as)
    location /api/ {
        proxy_pass http://dutch_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Tout le reste -> Flutter SPA (URL routing)
    location / {
        # Essaie de servir le fichier, sinon renvoie index.html
        # C'est ça qui fait marcher le routing URL!
        try_files \$uri \$uri/ /index.html;
    }

    # Cache pour les assets statiques
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
NGINX_CONFIG

scp /tmp/nginx-dutch root@$SERVER_IP:/etc/nginx/sites-available/dutch-server
ssh root@$SERVER_IP << 'NGINX_SETUP'
ln -sf /etc/nginx/sites-available/dutch-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
echo "✓ Nginx configuré"
NGINX_SETUP

# Démarrer l'application avec PM2
echo -e "\n${YELLOW}🚀 Démarrage de l'application...${NC}"
ssh root@$SERVER_IP << 'START_APP'
cd /var/www/dutch-server

# Créer ecosystem.config.js
cat > ecosystem.config.js << 'PM2_CONFIG'
module.exports = {
  apps: [{
    name: 'dutch-server',
    script: './dist/index.js',
    instances: 1,
    exec_mode: 'fork',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    max_memory_restart: '500M',
  }]
};
PM2_CONFIG

# Arrêter puis redémarrer avec PM2 pour prendre en compte les changements de config
pm2 delete dutch-server 2>/dev/null || true
pm2 start ecosystem.config.js
pm2 save
echo "✓ Application démarrée"
START_APP

# Vérifier que le serveur répond
echo -e "\n${YELLOW}🔍 Vérification du serveur...${NC}"
sleep 3
if curl -s http://$SERVER_IP/health | grep -q "ok"; then
    echo -e "${GREEN}✓ Serveur répond correctement!${NC}"
else
    echo -e "${RED}⚠️  Le serveur ne répond pas encore (peut prendre quelques secondes)${NC}"
fi

# Vérifier le DNS
echo -e "\n${YELLOW}🌐 Vérification du DNS...${NC}"
DNS_IP=$(dig +short $DOMAIN @8.8.8.8 | tail -1)
if [ "$DNS_IP" == "$SERVER_IP" ]; then
    echo -e "${GREEN}✓ DNS configuré correctement!${NC}"

    # Installer le certificat SSL
    echo -e "\n${YELLOW}🔒 Installation du certificat SSL...${NC}"
    echo "Cela peut prendre 1-2 minutes..."

    ssh root@$SERVER_IP << SSL_INSTALL
certbot --nginx -d $DOMAIN -d www.$DOMAIN \
    --non-interactive \
    --agree-tos \
    --email $ADMIN_EMAIL \
    --redirect
echo "✓ SSL installé"
SSL_INSTALL

    echo -e "${GREEN}✓ Certificat SSL installé!${NC}"
    FINAL_URL="https://$DOMAIN"
else
    echo -e "${YELLOW}⚠️  DNS pas encore propagé (IP actuelle: $DNS_IP, attendu: $SERVER_IP)${NC}"
    echo -e "${YELLOW}➜ Le SSL sera installé plus tard avec:${NC}"
    echo -e "  ssh root@$SERVER_IP"
    echo -e "  sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --email $ADMIN_EMAIL"
    FINAL_URL="http://$SERVER_IP"
fi

# Configurer le firewall
echo -e "\n${YELLOW}🔥 Configuration du firewall...${NC}"
ssh root@$SERVER_IP << 'FIREWALL'
ufw --force enable
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw status
echo "✓ Firewall configuré"
FIREWALL

# Nettoyer
rm -f /tmp/setup-server.sh /tmp/dutch-server.tar.gz /tmp/nginx-dutch

# Résumé final
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 Déploiement terminé avec succès!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  🌐 URL du serveur: ${YELLOW}$FINAL_URL${NC}"
echo -e "  🔍 Health check: ${YELLOW}$FINAL_URL/health${NC}"
echo -e "  📊 Logs: ${YELLOW}ssh dutch@$SERVER_IP 'pm2 logs'${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📝 Prochaines étapes:${NC}"
echo ""
echo "1. Tester le serveur:"
echo "   curl $FINAL_URL/health"
echo ""
echo "2. Mettre à jour le client Flutter:"
echo "   Modifier lib/services/multiplayer_service.dart"
echo "   static const String _serverUrl = '$FINAL_URL';"
echo ""
echo "3. Voir les logs du serveur:"
echo "   ssh dutch@$SERVER_IP"
echo "   pm2 logs dutch-server"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
