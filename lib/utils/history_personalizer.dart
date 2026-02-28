/// Personnalise un message d'historique en remplaçant le nom du joueur local
/// par les formes appropriées ("Vous", "votre", etc.) et en ajustant les
/// conjugaisons françaises.
///
/// Gère le cas où le joueur est l'ACTEUR (début de message) et le cas où
/// il est la CIBLE (mentionné dans le message).
class HistoryPersonalizer {
  HistoryPersonalizer._();

  /// Personnalise [message] pour le joueur local [myName].
  /// Si [myName] est null ou vide, retourne le message tel quel.
  static String personalize(String message, String? myName) {
    if (myName == null || myName.isEmpty) return message;

    // Extraire le contenu sans le timestamp "[HH:MM] "
    String prefix = '';
    String body = message;
    final tsEnd = message.indexOf('] ');
    if (tsEnd >= 0) {
      prefix = message.substring(0, tsEnd + 2);
      body = message.substring(tsEnd + 2);
    }

    body = _personalizeBody(body, myName);
    return '$prefix$body';
  }

  static String _personalizeBody(String body, String myName) {
    // ── Patterns avec préfixe ────────────────────────────────────────
    // "JOKER ! X mélange la main de Y !"
    if (body.startsWith('JOKER ! $myName ')) {
      final rest = body.substring('JOKER ! $myName '.length);
      return 'JOKER ! Vous mélangez ${rest.replaceFirst('mélange ', '')}';
    }
    if (body.contains('JOKER !') && body.contains('la main de $myName')) {
      return body.replaceAll('la main de $myName', 'votre main');
    }

    // "MATCH ! X pose ..."
    if (body.startsWith('MATCH ! $myName ')) {
      return 'MATCH ! Vous ${_conjugate(body.substring('MATCH ! $myName '.length))}';
    }

    // "Échange : X carte #N ↔ Y carte #M."
    if (body.startsWith('Échange : $myName ')) {
      return 'Échange : Vous ${body.substring('Échange : $myName '.length)}';
    }
    if (body.contains('↔ $myName ')) {
      return body.replaceAll('↔ $myName ', '↔ Vous ');
    }

    // "Tirage au sort : X commence !"
    if (body.startsWith('Tirage au sort : $myName')) {
      return 'Tirage au sort : Vous commencez !';
    }

    // "Au tour de X."
    if (body.startsWith('Au tour de $myName')) {
      return "C'est votre tour.";
    }

    // ── Acteur : message commence par le nom du joueur ────────────────
    if (body.startsWith('$myName ')) {
      final rest = body.substring(myName.length + 1);
      final conjugated = _conjugate(rest);
      // Remplacer les possessifs (son/sa/ses → votre/vos)
      final withPossessives = _replacePossessives(conjugated);
      return 'Vous $withPossessives';
    }

    // ── Cible : le nom apparaît ailleurs dans le message ──────────────
    // "X regarde une carte de Y." → "X regarde une de vos cartes."
    if (body.contains(' une carte de $myName')) {
      return body.replaceAll(' une carte de $myName', ' une de vos cartes');
    }
    // "X espionne une carte de Y." → même pattern
    // "la main de Y" → "votre main"
    if (body.contains('la main de $myName')) {
      return body.replaceAll('la main de $myName', 'votre main');
    }
    // "de Y." en fin de message
    if (body.contains(' de $myName.')) {
      return body.replaceAll(' de $myName.', ' de vous.');
    }
    if (body.contains(' de $myName ')) {
      return body.replaceAll(' de $myName ', ' de vous ');
    }

    return body;
  }

  /// Conjugue le verbe du 3e personne singulier au 2e personne pluriel (Vous).
  static String _conjugate(String rest) {
    // Ordre important : patterns les plus longs d'abord
    const replacements = <String, String>{
      'ne garde pas': 'ne gardez pas',
      'a utilisé': 'avez utilisé',
      'rate son': 'ratez votre',
      'rate sa': 'ratez votre',
      'remplace son': 'remplacez votre',
      'remplace sa': 'remplacez votre',
      'crie ': 'criez ',
      'regarde une de ses': 'regardez une de vos',
      'regarde': 'regardez',
      'active': 'activez',
      'défausse': 'défaussez',
      'espionne': 'espionnez',
      'mélange': 'mélangez',
      'ignore': 'ignorez',
      'pioche': 'piochez',
      'prend': 'prenez',
      'commence': 'commencez',
      'pose': 'posez',
    };

    for (final entry in replacements.entries) {
      if (rest.startsWith(entry.key)) {
        return entry.value + rest.substring(entry.key.length);
      }
    }
    return rest;
  }

  /// Remplace les possessifs 3e personne par 2e personne pluriel.
  static String _replacePossessives(String text) {
    return text
        .replaceAll(' ses ', ' vos ')
        .replaceAll(' son ', ' votre ')
        .replaceAll(' sa ', ' votre ');
  }
}
