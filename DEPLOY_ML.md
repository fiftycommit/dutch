# 🚀 Déploiement des Fonctionnalités ML

## Déploiement Rapide sur dutch-game.me

Ton serveur est déjà configuré, il suffit de pousser le code !

### Option 1 : Déploiement Automatique (Recommandé)

```bash
# Depuis ton Mac
cd /Users/maxmbey/projets/dutch

# 1. Commit les changements
git add .
git commit -m "feat: Add ML features - Q-Learning, Neural Network, Player Cloning, 8 Personalities"

# 2. Push vers GitHub
git push origin main
```

✅ GitHub Actions va automatiquement :
- Compiler le TypeScript
- Déployer sur le serveur
- Redémarrer PM2
- Le dashboard sera accessible sur https://dutch-game.me/bot-stats

### Option 2 : Déploiement Manuel SSH

Si tu veux déployer manuellement :

```bash
# 1. Se connecter au serveur
ssh root@164.92.234.245
# ou
ssh root@dutch-game.me

# 2. Aller dans le dossier du serveur
cd /root/apps/dutch-server

# 3. Pull les derniers changements
git pull origin main

# 4. Installer les dépendances (si nouvelles)
npm install

# 5. Compiler TypeScript
npm run build

# 6. Créer les répertoires de données
mkdir -p data/bot-learning/{games,profiles,qlearning,neural,clones,personalities}

# 7. Redémarrer PM2
pm2 restart dutch-server

# 8. Vérifier les logs
pm2 logs dutch-server --lines 50
```

## Vérification du Déploiement

### 1. Tester les API

```bash
# Stats globales
curl https://dutch-game.me/api/bot-learning/stats

# Personnalités
curl https://dutch-game.me/api/bot-learning/personalities

# Stats ML
curl https://dutch-game.me/api/bot-learning/ml-stats
```

### 2. Accéder au Dashboard

Ouvre dans ton navigateur :
```
https://dutch-game.me/bot-stats
```

Tu devrais voir :
- ✅ 8 personnalités (Marco, Sophie, Alex, Emma, Lucas, Léa, Thomas, Maxime)
- ✅ Stats ML (Q-Learning et Neural Network)
- ✅ Top bots (vide au début)
- ✅ Auto-refresh toutes les 30 secondes

### 3. Vérifier les Logs

```bash
# Sur le serveur
pm2 logs dutch-server

# Tu devrais voir :
# ✅ 8 personnalités sauvegardées
# ✅ Q-Learning initialisé
# ✅ Neural Network créé
```

## Configuration Nginx (Déjà en Place)

Le fichier `/etc/nginx/sites-available/dutch-game.me` devrait déjà servir :
- `/` → Page d'accueil
- `/bot-stats` → Dashboard des bots
- `/api/bot-learning/*` → API ML

Si besoin de vérifier :
```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Permissions des Fichiers

Assure-toi que PM2 peut écrire dans les répertoires :

```bash
cd /root/apps/dutch-server
chmod -R 755 data/
chown -R root:root data/
```

## Monitoring

### Vérifier que PM2 tourne

```bash
pm2 status
# dutch-server devrait être "online"
```

### Voir l'utilisation mémoire

```bash
pm2 monit
```

### Redémarrer si problème

```bash
pm2 restart dutch-server
pm2 save
```

## Troubleshooting

### Erreur "ENOENT: no such file or directory"

```bash
cd /root/apps/dutch-server
mkdir -p data/bot-learning/{games,profiles,qlearning,neural,clones,personalities}
pm2 restart dutch-server
```

### Dashboard ne charge pas

```bash
# Vérifier que le fichier existe
ls -la /root/apps/dutch-server/public/bot-dashboard.html

# Vérifier les logs Nginx
sudo tail -f /var/log/nginx/error.log
```

### API retourne 404

```bash
# Vérifier que les routes sont compilées
ls -la /root/apps/dutch-server/dist/routes/botLearningRoutes.js

# Recompiler si nécessaire
cd /root/apps/dutch-server
npm run build
pm2 restart dutch-server
```

## URLs Finales

Une fois déployé, tu auras accès à :

- **Page d'accueil** : https://dutch-game.me
- **Dashboard Bots** : https://dutch-game.me/bot-stats
- **API Stats** : https://dutch-game.me/api/bot-learning/stats
- **API Personnalités** : https://dutch-game.me/api/bot-learning/personalities
- **API ML Stats** : https://dutch-game.me/api/bot-learning/ml-stats

## Prochaines Étapes

1. **Déployer** : `git push origin main`
2. **Attendre** : GitHub Actions déploie (2-3 minutes)
3. **Vérifier** : Ouvrir https://dutch-game.me/bot-stats
4. **Jouer** : Les parties enregistrées alimenteront automatiquement le ML

---

**Note** : Les modèles ML commencent vides et se remplissent au fur et à mesure que des parties sont jouées avec des bots. Plus il y a de parties, meilleurs seront les modèles !
