#!/bin/bash

# Script simplifié de création du Droplet DigitalOcean
# Cette version suppose que vous avez déjà uploadé votre clé SSH manuellement

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 Création du Droplet DigitalOcean (Version simplifiée)${NC}\n"

# Vérifier le token
if [ -z "$DO_TOKEN" ]; then
    echo -e "${RED}❌ Erreur: Variable DO_TOKEN non définie${NC}"
    echo ""
    echo "Exécuter d'abord:"
    echo "  export DO_TOKEN='votre_token'"
    exit 1
fi

echo -e "${YELLOW}📋 Configuration:${NC}"
echo "  Nom: dutch-game-server"
echo "  Taille: 1GB RAM / 1 vCPU (6\$/mois)"
echo "  Région: Frankfurt (Europe)"
echo "  Image: Ubuntu 24.04 LTS"
echo ""

# Créer le Droplet sans clé SSH (utilisation du mot de passe envoyé par email)
echo -e "${YELLOW}🌊 Création du Droplet...${NC}"

CREATE_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DO_TOKEN" \
    -d '{
        "name": "dutch-game-server",
        "size": "s-1vcpu-1gb",
        "region": "fra1",
        "image": "ubuntu-24-04-x64",
        "backups": false,
        "ipv6": true,
        "monitoring": true,
        "tags": ["dutch-game", "production"]
    }' \
    "https://api.digitalocean.com/v2/droplets")

# Vérifier la création
if echo "$CREATE_RESPONSE" | grep -q '"droplet"'; then
    echo -e "${GREEN}✓ Droplet créé!${NC}\n"

    # Extraire l'ID
    DROPLET_ID=$(echo $CREATE_RESPONSE | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

    if [ -z "$DROPLET_ID" ]; then
        echo -e "${RED}❌ Erreur: Impossible d'extraire l'ID du Droplet${NC}"
        exit 1
    fi

    echo -e "${GREEN}Droplet ID: $DROPLET_ID${NC}"
    echo -e "\n${YELLOW}⏳ Attente de l'activation (30-60 secondes)...${NC}"

    # Attendre l'activation
    for i in {1..30}; do
        sleep 2
        STATUS_RESPONSE=$(curl -s -X GET \
            -H "Authorization: Bearer $DO_TOKEN" \
            "https://api.digitalocean.com/v2/droplets/$DROPLET_ID")

        STATUS=$(echo $STATUS_RESPONSE | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

        if [ "$STATUS" == "active" ]; then
            echo -e "\n${GREEN}✓ Droplet actif!${NC}\n"

            # Extraire l'IP
            DROPLET_IP=$(echo $STATUS_RESPONSE | grep -o '"ip_address":"[0-9.]*"' | head -1 | cut -d'"' -f4)

            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}🎉 Droplet créé avec succès!${NC}"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "  📍 IP: ${YELLOW}$DROPLET_IP${NC}"
            echo -e "  🔐 SSH: ${YELLOW}ssh root@$DROPLET_IP${NC}"
            echo ""
            echo -e "${YELLOW}⚠️  Mot de passe SSH:${NC}"
            echo "  DigitalOcean vous a envoyé le mot de passe root par email"
            echo "  Vérifiez votre boîte de réception"
            echo ""
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${YELLOW}📝 Prochaines étapes:${NC}"
            echo ""
            echo "1. Configurer DNS sur Namecheap:"
            echo "   Type: A Record, Host: @, Value: $DROPLET_IP"
            echo ""
            echo "2. Se connecter au serveur:"
            echo "   ssh root@$DROPLET_IP"
            echo "   (utilisez le mot de passe reçu par email)"
            echo ""
            echo "3. Suivre le guide de déploiement:"
            echo "   cat ../DEPLOY_DIGITALOCEAN.md"
            echo ""

            # Sauvegarder les infos
            cat > droplet-info.txt <<EOF
Droplet Dutch Game - Informations
==================================

Droplet ID: $DROPLET_ID
Adresse IP: $DROPLET_IP
Région: Frankfurt (fra1)
Taille: 1GB RAM / 1 vCPU
Créé le: $(date)

Connexion SSH:
  ssh root@$DROPLET_IP
  Mot de passe: Voir email de DigitalOcean

Configuration DNS (Namecheap):
  A Record: @ -> $DROPLET_IP
  A Record: www -> $DROPLET_IP

URL finale: https://dutchgame.me
EOF

            echo -e "${GREEN}💾 Infos sauvegardées dans droplet-info.txt${NC}"
            exit 0
        fi
        printf "."
    done

    echo -e "\n${YELLOW}⚠️  Le Droplet prend plus de temps...${NC}"
    echo "Vérifiez: https://cloud.digitalocean.com/droplets/$DROPLET_ID"

else
    echo -e "${RED}❌ Erreur lors de la création${NC}"
    echo ""
    echo "Réponse de l'API:"
    echo "$CREATE_RESPONSE"
    echo ""
    echo -e "${YELLOW}Vérifiez:${NC}"
    echo "1. Que votre token est correct"
    echo "2. Que le token a les permissions Read+Write"
    echo "3. Que vous avez des crédits disponibles"
    exit 1
fi
