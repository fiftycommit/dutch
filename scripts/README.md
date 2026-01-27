# Scripts de déploiement Dutch Game

## Création automatique du Droplet DigitalOcean

Le script `create-droplet.sh` automatise la création du Droplet pour héberger votre serveur multiplayer.

### Prérequis

1. **Token API DigitalOcean**
   - Aller sur: https://cloud.digitalocean.com/account/api/tokens
   - Cliquer sur "Generate New Token"
   - Nom: `Dutch Game CLI`
   - Permissions: **Read + Write** (cocher les deux)
   - Cliquer sur "Generate Token"
   - **Copier le token** (vous ne pourrez plus le voir après!)

### Utilisation

```bash
# 1. Aller dans le dossier scripts
cd /Users/maxmbey/projets/dutch/scripts

# 2. Définir votre token API
export DO_TOKEN='dop_v1_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'

# 3. Exécuter le script
./create-droplet.sh
```

### Ce que fait le script

1. ✅ Vérifie votre token API
2. ✅ Crée ou upload votre clé SSH
3. ✅ Crée le Droplet avec la configuration optimale:
   - **Nom**: `dutch-game-server`
   - **Taille**: 1GB RAM / 1 vCPU (6$/mois)
   - **Région**: Frankfurt (Europe)
   - **Image**: Ubuntu 24.04 LTS
   - **Options**: IPv6 + Monitoring activés
4. ✅ Attend que le Droplet soit actif
5. ✅ Affiche l'adresse IP
6. ✅ Sauvegarde les informations dans `droplet-info.txt`

### Configuration du Droplet

Le script crée un Droplet avec ces spécifications:

| Paramètre | Valeur | Description |
|-----------|--------|-------------|
| **Nom** | dutch-game-server | Nom du Droplet |
| **Taille** | s-1vcpu-1gb | 1GB RAM / 1 vCPU |
| **Région** | fra1 | Frankfurt (Europe) |
| **Image** | ubuntu-24-04-x64 | Ubuntu 24.04 LTS |
| **SSH** | Automatique | Votre clé SSH publique |
| **IPv6** | Activé | Support IPv6 |
| **Monitoring** | Activé | Surveillance gratuite |
| **Tags** | dutch-game, production | Pour l'organisation |

### Changer la région

Si vous voulez une région différente, éditez le script:

```bash
nano create-droplet.sh
```

Modifier la ligne:
```bash
DROPLET_REGION="fra1"  # Frankfurt (Europe)
```

Régions disponibles:
- **fra1** - Frankfurt, Germany (Europe)
- **ams3** - Amsterdam, Netherlands (Europe)
- **lon1** - London, UK (Europe)
- **nyc1** - New York, USA (Est)
- **nyc3** - New York, USA (Est)
- **sfo3** - San Francisco, USA (Ouest)
- **tor1** - Toronto, Canada
- **sgp1** - Singapore (Asie)
- **blr1** - Bangalore, India (Asie)

### Après la création

Le script affiche:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 Droplet créé avec succès!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  📍 Adresse IP: 157.230.123.45
  🔐 Connexion SSH: ssh root@157.230.123.45
```

### Prochaines étapes

1. **Configurer le DNS sur Namecheap**:
   ```
   Type: A Record
   Host: @
   Value: VOTRE_IP_DROPLET
   ```

2. **Se connecter au serveur**:
   ```bash
   ssh root@VOTRE_IP_DROPLET
   ```

3. **Suivre le guide de déploiement**:
   ```bash
   cat ../DEPLOY_DIGITALOCEAN.md
   ```

### Troubleshooting

**Erreur: "DO_TOKEN non défini"**
```bash
export DO_TOKEN='votre_token'
```

**Erreur: "Unauthorized"**
- Vérifiez que votre token est correct
- Vérifiez que les permissions Read + Write sont activées

**Erreur: "SSH key already exists"**
- C'est normal! Le script utilisera automatiquement la clé existante

**Le Droplet prend trop de temps**
- Vérifier manuellement sur: https://cloud.digitalocean.com/droplets
- La création prend généralement 30-60 secondes

### Supprimer le Droplet

Pour supprimer le Droplet (et arrêter les frais):

```bash
# Récupérer le Droplet ID depuis droplet-info.txt
DROPLET_ID=123456789

# Supprimer via l'API
curl -X DELETE \
    -H "Authorization: Bearer $DO_TOKEN" \
    "https://api.digitalocean.com/v2/droplets/$DROPLET_ID"
```

Ou via l'interface web: https://cloud.digitalocean.com/droplets

### Coût

- **Droplet 1GB**: 6$/mois (0,009$/heure)
- Le timer commence dès la création
- Avec 200$ de crédits = **33 mois gratuits**

### Support

En cas de problème:
- Vérifier les logs du script
- Consulter la documentation DigitalOcean: https://docs.digitalocean.com/reference/api/
- Vérifier l'état sur: https://status.digitalocean.com/
