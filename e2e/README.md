# Tests E2E (Playwright + sémantique Flutter)

Pilote l'app Flutter web (CanvasKit) par **sélecteurs**, contre les émulateurs
Firebase. Sans l'arbre de sémantique, l'UI est un `<canvas>` unique et Playwright
ne peut rien cibler ; on l'active en dev via `--dart-define=ENABLE_SEMANTICS=true`.

## Installation

```bash
cd e2e
npm ci
npx playwright install chromium
```

## Lancer

Démarrer d'abord la stack locale (voir `../DEV-EMULATORS.md`) : émulateurs, serveur
(`npm run dev:emulators`), et build web servi avec les dart-defines
`ENABLE_SEMANTICS=true USE_FIREBASE_EMULATOR=true DEV_SERVER_URL=http://localhost:3000`.

```bash
npm run login    # pré-crée un compte via l'API, se connecte via l'UI, vérifie login-password 200
```

Config par variables d'env : `E2E_URL` (défaut `http://localhost:8081/`),
`E2E_SERVER` (défaut `http://localhost:3000`).

## Ce qui marche, et la limite CanvasKit

`flutter-semantics.mjs` fournit les briques : localiser un bouton par son texte /
un champ par son `aria-label`, cliquer par un vrai événement pointer, naviguer
menu → multijoueur → auth.

- **Navigation et clics de boutons** : fiables (le hit-testing Flutter reçoit les
  événements pointer).
- **Saisie de texte** : Flutter web route les frappes via un hôte d'édition
  partagé — ni `input.value` ni `document.activeElement` ne reflètent la saisie,
  et remplir un formulaire de **plusieurs** champs d'affilée rate systématiquement
  un champ (course de focus propre à CanvasKit). Fiable pour 1-2 champs.

Conséquence pratique : **pré-créer les comptes/données via l'API serveur** (fiable)
et ne piloter par l'UI que la connexion (2 champs) et le jeu, plutôt que de saisir
de longs formulaires. C'est l'approche de `login.e2e.mjs`.
