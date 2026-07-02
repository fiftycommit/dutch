/// Compteur de rebuilds par zone, activé uniquement en test.
///
/// En production `enabled` reste `false` : chaque appel à [bump] ne fait qu'un
/// test de booléen (coût négligeable). Sert à mesurer, sur le VRAI écran monté,
/// que le découpage en `Selector` réduit réellement les rebuilds par zone.
class RebuildProbe {
  RebuildProbe._();

  static bool enabled = false;
  static final Map<String, int> counts = {};

  static void bump(String zone) {
    if (!enabled) return;
    counts[zone] = (counts[zone] ?? 0) + 1;
  }

  static int countFor(String zone) => counts[zone] ?? 0;

  static void reset() => counts.clear();
}
