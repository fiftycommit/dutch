# Dutch'78 — Claude Code Guidelines

## Design Context

### Users
Audience mixte : joueurs occasionnels (familles, amis) et joueurs compétitifs (tournois, classements). Les deux profils coexistent via les modes solo/multijoueur. L'interface doit être accessible au casual tout en satisfaisant les attentes du joueur sérieux.

### Brand Personality
**Élégant, tendu, immersif.**
L'app doit évoquer la concentration d'une partie de cartes physique — le bruissement des cartes, le feutre d'une table, la tension avant de déclarer Dutch. Pas un casino criard ni une app enfantine : quelque chose entre les deux, comme un jeu de cartes de qualité qu'on sort le soir entre amis.

Référence visuelle : esthétique jeu de cartes physique (chaleureux, artisanal, authentique). Anti-référence : UI casino flashy, gamification agressive, plastique numérique.

### Aesthetic Direction
- **Thème principal :** Dark green (`#0d2818` → `#1a472a`), identité visuelle centrale
- **Tons :** Chauds et profonds — verts forestiers, ombres douces, touches ambrées pour les états actifs
- **Typographie :** Sobre et lisible, pas décorative
- **Cartes :** Les SVGs sont les vrais héros visuels — mettre en valeur sans surcharger
- **Animations :** Purposeful et fluides (150–300ms) — rappeler le geste physique de manipuler des cartes
- **Contrastes :** WCAG AA minimum (déjà intégré dans le système)

### Design Principles

1. **Authenticité avant tout** — Chaque choix visuel doit rappeler le jeu physique. Préférer la chaleur et la texture au rendu digital générique.

2. **Tension équilibrée** — L'interface doit tenir le joueur en haleine sans le stresser inutilement. Les états d'urgence (timer rouge, Dutch imminent) doivent être clairs mais pas agressifs.

3. **Élégance dans la simplicité** — Pas de surcharge d'éléments. Chaque composant a sa place. L'espace vide est un outil de design, pas un manque.

4. **Accessibilité sans compromis** — WCAG AA partout, tailles de touch target ≥ 44px, contraste minimum 4.5:1. L'accessibilité est une contrainte non-négociable.

5. **Cohérence systémique** — Utiliser les tokens de `ui_constants.dart` (AppColors, AppSpacing, AppTextStyles, AppDurations) systématiquement. Ne jamais hardcoder des valeurs visuelles.

## Tech Stack
- Flutter / Dart 3.5+
- Provider (state management)
- go_router (navigation)
- Firebase (auth, Firestore, storage, FCM)
- Socket.IO (multijoueur temps réel)
- Material 3 avec thèmes custom (light / dark / green)

## Key Files
- `lib/utils/ui_constants.dart` — tokens design (couleurs, espacement, typo, animations)
- `lib/main.dart` — définitions des 3 thèmes
- `lib/models/game_settings.dart` — enum thèmes
- `lib/widgets/game/` — composants jeu
- `lib/widgets/ui/` — composants UI réutilisables
