# Sécurité du serveur Dutch Game

## Protections en place

### 1. Rate Limiting
- **HTTP API** : 500 req/15min par IP
- **WebSocket** : 30 connexions/min par IP
- **Actions de jeu** : 20 actions/sec par joueur

### 2. Infrastructure
- **HTTPS/SSL** : Let's Encrypt
- **Firewall** : UFW (ports 80, 443, 22 uniquement)
- **Nginx** : Reverse proxy
- **PM2** : Auto-restart en cas de crash

### 3. Endpoints publics (sans risque)
- `/status` - Informations serveur (lecture seule)
- `/health` - Health check (lecture seule)
- `/rooms` - Liste des rooms (lecture seule)
- `/rooms/public` - Rooms publiques (lecture seule)

## Risques identifiés et mitigations

### Risque 1 : Spam de création de rooms
**Niveau** : Faible
**Mitigation** : Rate limiting (30 connexions/min)
**Impact** : Un attaquant pourrait créer ~30 rooms/min max

### Risque 2 : Information disclosure
**Niveau** : Très faible
**Info exposée** : Nombre de rooms actives, liste des rooms publiques
**Impact** : Aucun impact sécurité, juste de l'information publique

### Risque 3 : DDoS
**Niveau** : Moyen
**Mitigation** : Rate limiting, Nginx, DigitalOcean DDoS protection
**Impact** : Serveur peut ralentir mais pas crasher

## Recommandations futures

### Si le jeu devient populaire (>1000 joueurs)

1. **Ajouter Cloudflare** (gratuit)
   - Protection DDoS avancée
   - Cache CDN
   - Rate limiting supplémentaire

2. **Monitoring avancé**
   - Alertes si CPU/RAM > 80%
   - Logs d'attaques
   - Dashboard PM2 Plus

3. **Authentification pour /status**
   - Ajouter un token Bearer si besoin
   - Actuellement pas nécessaire (info publique)

4. **Backup automatique**
   - Snapshots DigitalOcean hebdomadaires
   - Backup des rooms actives

## Conclusion

**Le serveur est sécurisé pour un jeu multijoueur public.**

Les endpoints exposés ne permettent que la lecture d'informations publiques.
Les actions sensibles (créer/rejoindre rooms, jouer) sont rate-limitées.
Aucune donnée personnelle n'est stockée (pas de comptes utilisateurs).
