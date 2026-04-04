# Plan de sécurisation — Dutch Server

## 1. Supprimer le guest mode Socket.IO
**Fichier:** `dutch-server/src/middleware/socketAuthMiddleware.ts`
- Rejeter toute connexion sans token Firebase valide
- Retourner une erreur explicite `Authentication required`

## 2. Rate limiting spécifique pour les routes admin
**Fichier:** `dutch-server/src/services/SecurityService.ts`
- Ajouter un `adminLimiter` : 10 requêtes / 15 min par IP (brute-force protection sur le secret)

**Fichier:** `dutch-server/src/routes/adminRoutes.ts`
- Appliquer `adminLimiter` avant le middleware `requireAdmin`

**Fichier:** `dutch-server/src/server.ts`
- Appliquer `adminLimiter` sur `/rooms/debug` aussi

## 3. Protéger les endpoints d'info derrière l'auth admin
**Fichier:** `dutch-server/src/server.ts`
- `/status` → derrière `requireAdmin` (header X-Admin-Secret)
- `/bot-stats` → derrière `requireAdmin`
- `/player-profile` → derrière `requireAdmin`
- `/shuffle-analysis` → derrière `requireAdmin`
- `/rooms/stats` → derrière `requireAdmin`
- `/admin` (dashboard HTML) → derrière `requireAdmin`
- Garder `/health` et `/version` publics (nécessaires pour monitoring/uptime)
- Garder `/rooms/public` public (nécessaire pour le client)

## 4. Ajouter du logging sur les échecs d'auth
**Fichier:** `dutch-server/src/middleware/socketAuthMiddleware.ts`
- Logger IP + timestamp sur token invalide

**Fichier:** `dutch-server/src/routes/adminRoutes.ts`
- Logger IP + timestamp sur secret admin invalide

## 5. Headers de sécurité Nginx
**Fichier:** `dutch-server/nginx/dutch-server.conf`
- Ajouter `X-Content-Type-Options: nosniff`
- Ajouter `X-Frame-Options: DENY`
- Ajouter `X-XSS-Protection: 1; mode=block`
- Ajouter `Referrer-Policy: strict-origin-when-cross-origin`
- Ajouter `Permissions-Policy` restrictif
- Masquer la version Nginx (`server_tokens off`)

## 6. Extraire le middleware admin en réutilisable
**Fichier:** `dutch-server/src/middleware/adminAuthMiddleware.ts` (nouveau)
- Extraire la logique `requireAdmin` pour pouvoir l'utiliser dans `server.ts` et `adminRoutes.ts`
- Inclure le rate limiter admin
- Inclure le logging des échecs
