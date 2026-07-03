# Dev local avec les émulateurs Firebase

But : faire tourner tout le stack (serveur + app web + Auth/Firestore/Storage) en
local, sans aucune vraie credential Firebase, avec des comptes et des données
jetables. La prod n'est pas concernée : elle continue de pointer sur le vrai
Firebase (les variables ci-dessous ne sont posées qu'en local).

## Pré-requis

- `firebase-tools` (`firebase --version`)
- Java (les émulateurs Firestore/Storage en ont besoin)
- Flutter + les deps serveur (`cd dutch-server && npm ci`)

## Lancement (3 terminaux)

### 1. Les émulateurs

```bash
firebase emulators:start --only auth,firestore,storage --project dutch-game-1dd01
```

Ports (définis dans `firebase.json`) : Auth `9099`, Firestore `8089`,
Storage `9199`, UI émulateurs `http://127.0.0.1:4500`.

### 2. Le serveur (branché sur les émulateurs)

```bash
cd dutch-server
npm run dev:emulators
```

Ce script pose les variables d'env standard que le SDK Admin comprend
(`FIREBASE_AUTH_EMULATOR_HOST`, `FIRESTORE_EMULATOR_HOST`,
`FIREBASE_STORAGE_EMULATOR_HOST`), plus `NODE_ENV=development` et
`AUTH_ABUSE_DISABLED=1`. Au démarrage le serveur logge
`🧪 Firebase Admin initialisé (ÉMULATEURS locaux)`. Il écoute sur le port `3000`.

### 3. L'app web (branchée sur les émulateurs + le serveur local)

```bash
flutter run -d chrome \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  --dart-define=DEV_SERVER_URL=http://localhost:3000
```

ou en build servi :

```bash
flutter build web --no-web-resources-cdn \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  --dart-define=DEV_SERVER_URL=http://localhost:3000
cd build/web && python3 -m http.server 8081
```

Options utiles : `--dart-define=FIREBASE_EMULATOR_HOST=<hôte>` si l'app ne tourne
pas sur la même machine que les émulateurs (défaut `localhost`).

## Ce qui bascule en mode émulateur

| Côté | Détection | Effet |
|---|---|---|
| Serveur (`FirebaseAdmin.ts`) | `FIREBASE_AUTH_EMULATOR_HOST` / `FIRESTORE_EMULATOR_HOST` | Init Admin avec `projectId` seul, sans clé de service |
| Serveur (`PasswordAuthService.ts`) | `FIREBASE_AUTH_EMULATOR_HOST` | Identity Toolkit routé vers l'émulateur Auth, clé API factice |
| Serveur (`AuthAbuseService.ts`) | `AUTH_ABUSE_DISABLED=1` | Anti-abus désactivé (sinon 2 clients en rafale se font bloquer) |
| Serveur (App Check) | `NODE_ENV !== production` | Middleware App Check déjà en fail-open (comportement existant) |
| App web (`main.dart`) | `--dart-define=USE_FIREBASE_EMULATOR=true` | `useAuthEmulator` / `useFirestoreEmulator` / `useStorageEmulator` |
| App web (`serverUrl`) | `--dart-define=DEV_SERVER_URL=…` | URL API/socket → serveur local (défaut : prod) |

## Vérifier que ça marche

Comptes créés à la volée, aucune credential réelle. Flux complet vérifié
(inscription → connexion → socket authentifié → `room:create` → `room:join`) :

```bash
# émulateurs + serveur démarrés (terminaux 1 et 2), puis :
curl -s -X POST http://127.0.0.1:3000/api/auth/register-password \
  -H 'Content-Type: application/json' \
  -d '{"username":"testeur","displayName":"Testeur","email":"t@example.com","password":"MotDePasse123"}'
# → {"success":true,"customToken":"...","user":{...}}  (HTTP 201)
```

Réinitialiser les données : arrêter les émulateurs (elles ne sont pas
persistées). Pour repartir de zéro sans redémarrer, l'UI émulateurs
(`http://127.0.0.1:4500`) permet de purger Auth/Firestore.

## Piloter l'app par Playwright (arbre de sémantique)

L'app rend via CanvasKit dans un `<canvas>` unique : sans aide, Playwright ne peut
sélectionner ni bouton ni champ. Le flag `--dart-define=ENABLE_SEMANTICS=true`
force l'arbre de sémantique (accessibilité) de Flutter, qui génère un DOM ARIA
synthétique (rôles, `aria-label`, `<input>`) ciblable par sélecteurs.

```bash
flutter build web --no-web-resources-cdn \
  --dart-define=ENABLE_SEMANTICS=true \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  --dart-define=DEV_SERVER_URL=http://localhost:3000 \
  -o /tmp/dutch-web && (cd /tmp/dutch-web && python3 -m http.server 8081)
```

Les tests vivent dans `e2e/` (voir `e2e/README.md`). Preuve fournie :
`npm --prefix e2e run login` pré-crée un compte via l'API puis se connecte via
l'UI (menu → multijoueur → formulaire) uniquement par sélecteurs sémantiques, et
vérifie `login-password 200`.

En prod, `ENABLE_SEMANTICS` n'est pas posé : la sémantique reste à la demande
(lecteur d'écran), comportement Flutter par défaut.

**Limite CanvasKit à connaître** : navigation et clics de boutons sont fiables ;
la saisie de texte passe par un hôte d'édition partagé de Flutter (non relisible
depuis le DOM) et rater un champ sur un long formulaire est systématique. D'où le
choix de **pré-créer les données via l'API** et de ne piloter par l'UI que la
connexion (2 champs) et le jeu.

## Prod : rien ne change

Le serveur déployé ne pose aucune de ces variables (`FIREBASE_*_EMULATOR_HOST`,
`AUTH_ABUSE_DISABLED`) et continue d'exiger la vraie clé de service ; le build web
prod ne passe pas `USE_FIREBASE_EMULATOR`, `DEV_SERVER_URL` ni `ENABLE_SEMANTICS`.
Le mode émulateur (et le pilotage E2E) est purement additif.
