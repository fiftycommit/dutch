// Helpers pour piloter l'app Flutter web (CanvasKit) via Playwright, en
// s'appuyant sur l'arbre de sémantique activé par --dart-define=ENABLE_SEMANTICS=true
// (voir DEV-EMULATORS.md). L'UI CanvasKit est un canvas unique : la sémantique
// expose un DOM ARIA (rôles, aria-label, <input>) que l'on localise, puis on
// clique par un vrai événement pointer au centre de l'élément (Flutter fait son
// hit-testing sur le canvas, pas sur le DOM sémantique).

/** Boîte (centre + bas) d'un bouton sémantique repéré par son texte. */
export const boxByText = (page, textRe) => page.evaluate((src) => {
  const re = new RegExp(src, 'i');
  const el = [...document.querySelectorAll('[role="button"]')].find((e) =>
    re.test((e.textContent || '').trim()) &&
    e.getBoundingClientRect().width > 0 && e.getBoundingClientRect().y >= 0);
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2, by: r.y + r.height - 12 };
}, textRe.source);

/** Boîte d'un élément dont l'aria-label contient `label`. */
export const boxByLabel = (page, label) => page.evaluate((l) => {
  const el = [...document.querySelectorAll('[aria-label]')].find((e) =>
    (e.getAttribute('aria-label') || '').includes(l));
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2, by: r.y + r.height - 12 };
}, label);

/** Boîte du n-ième <input aria-label="…"> (les champs de saisie sémantiques). */
export const inputBox = (page, label, nth = 0) => page.evaluate(({ l, n }) => {
  const e = [...document.querySelectorAll('input')].filter(
    (x) => x.getAttribute('aria-label') === l)[n];
  if (!e) return null;
  const r = e.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}, { l: label, n: nth });

/** Attend qu'un localisateur (fonction renvoyant une boîte ou null) réponde. */
export async function waitBox(page, finder, timeout = 20000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const box = await finder();
    if (box) return box;
    await page.waitForTimeout(300);
  }
  throw new Error('waitBox: timeout');
}

/** Clique au centre (ou en bas) d'une boîte via un vrai événement pointer. */
export const tap = (page, box, bottom = false) =>
  page.mouse.click(box.x, bottom ? box.by : box.y);

/**
 * Saisit du texte dans un champ sémantique : tap pour focaliser, puis insertText.
 * NB : Flutter web route les frappes via un hôte d'édition partagé — ni
 * input.value ni document.activeElement ne reflètent la saisie, donc pas de
 * relecture DOM possible. Fiable pour 1-2 champs ; au-delà, préférer pré-créer
 * les données via l'API serveur (voir login.e2e.mjs) plutôt que de tout saisir.
 */
export async function fillField(page, label, value) {
  const box = await waitBox(page, () => inputBox(page, label));
  await tap(page, box);
  await page.waitForTimeout(700);
  await page.keyboard.insertText(value);
  await page.waitForTimeout(400);
}

/** Menu principal → sélection du profil (Joueur 1) → écran multijoueur/auth. */
export async function openMultiplayerAuth(page) {
  // Le profil est une pile repliée : 1er tap ouvre, 2e sélectionne (débloque les
  // boutons de jeu). On tape le bas de la carte pour éviter le crayon d'édition.
  await tap(page, await waitBox(page, () => boxByLabel(page, 'Joueur 1')), true);
  await page.waitForTimeout(1400);
  await tap(page, await waitBox(page, () => boxByLabel(page, 'Joueur 1')), true);
  await page.waitForTimeout(1400);
  // MULTIJOUEUR une fois actif.
  await page.waitForFunction(() => {
    const m = [...document.querySelectorAll('[role="button"]')]
      .find((e) => (e.textContent || '').trim() === 'MULTIJOUEUR');
    return m && m.getAttribute('aria-disabled') !== 'true';
  }, { timeout: 15000 });
  await tap(page, await boxByText(page, /^MULTIJOUEUR$/));
  await page.waitForTimeout(4500);
}
