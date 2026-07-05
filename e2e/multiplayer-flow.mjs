import { openMultiplayerAuth, fillField, boxByText, tap, waitBox } from './flutter-semantics.mjs';

export const URL = process.env.E2E_URL || 'http://localhost:8081/';
export const SERVER = process.env.E2E_SERVER || 'http://localhost:3000';
export const log = (...args) => console.log(new Date().toISOString().slice(11, 19), ...args);

export async function seed(prefix) {
  const id = Date.now().toString().slice(-7) + Math.floor(Math.random() * 900);
  const username = `${prefix}${id}`;
  const displayName = `${prefix.toUpperCase()}${id}`;
  const email = `${username}@example.com`;
  const response = await fetch(`${SERVER}/api/auth/register-password`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username,
      displayName,
      email,
      password: 'MotDePasse123',
    }),
  });
  if (response.status !== 201) throw new Error(`seed ${prefix}: HTTP ${response.status}`);
  return { email, username, displayName };
}

export function attachLoginProbe(page) {
  page._ok = false;
  page._critical = [];
  page.on('response', (response) => {
    if (response.url().includes('/api/auth/login-password') && response.status() === 200) {
      page._ok = true;
    }
  });
  page.on('console', (message) => {
    if (['error'].includes(message.type())) page._critical.push(message.text());
  });
  page.on('pageerror', (error) => page._critical.push(error.message));
}

export async function login(page, email, who) {
  for (let attempt = 1; attempt <= 6 && !page._ok; attempt++) {
    await page.goto(URL, { waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await openMultiplayerAuth(page);
    await fillField(page, "E-mail ou nom d'utilisateur", email);
    await fillField(page, 'Mot de passe', 'MotDePasse123');
    await tap(page, await boxByText(page, /^SE CONNECTER$/));
    for (let i = 0; i < 8 && !page._ok; i++) await page.waitForTimeout(1000);
  }
  if (!page._ok) throw new Error(`${who} login KO`);
  await page.waitForTimeout(2500);
  log(`${who} connecte`);
}

export async function createPrivateRoom(page) {
  await tap(page, await waitBox(page, () => boxByText(page, /Créer un salon/)));
  await page.waitForTimeout(2000);
  await tap(page, await waitBox(page, () => boxByText(page, /Salon Privé/)));
  await page.waitForTimeout(2000);
  await tap(page, await waitBox(page, () => boxByText(page, /CRÉER LE SALON/)));
  await page.waitForTimeout(4000);
  const code = await page.evaluate(() => {
    for (const element of document.querySelectorAll('flt-semantics')) {
      const text = (element.textContent || '').trim();
      if (/^[A-Z0-9]{8}$/.test(text)) return text;
    }
    return null;
  });
  if (!code) throw new Error('room code introuvable');
  log('code', code);
  return code;
}

export async function joinPrivateRoom(page, code) {
  await tap(page, await waitBox(page, () => boxByText(page, /Rejoindre un salon/)));
  await page.waitForTimeout(2500);
  const privateButton = await boxByText(page, /Salon Privé|privé/i);
  if (privateButton) {
    await tap(page, privateButton);
    await page.waitForTimeout(2500);
  }
  const input = await page.evaluate(() => {
    const element = document.querySelector('input');
    if (!element) return null;
    const rect = element.getBoundingClientRect();
    return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
  });
  if (!input) throw new Error('champ code salon introuvable');
  await page.mouse.click(input.x, input.y);
  await page.waitForTimeout(500);
  await page.keyboard.insertText(code);
  await page.waitForTimeout(500);
  await tap(page, await boxByText(page, /REJOINDRE/i));
  await page.waitForTimeout(3500);
}

export const nudge = async (page) => {
  await page.mouse.move(700, 400);
  await page.mouse.move(701, 401);
};

export const hasHostControls = (page) => page.evaluate(() =>
  [...document.querySelectorAll('[role="button"]')].some((element) =>
    /Paramètres/i.test((element.textContent || '').trim())));

export const isSelfHost = (page) => page.evaluate(() =>
  [...document.querySelectorAll('flt-semantics')]
    .filter((element) => {
      const text = (element.textContent || '').trim();
      return text.includes('Vous') && text.length < 40;
    })
    .some((element) => (element.textContent || '').includes('Hote')));

export async function waitForHostUi(page, expected, timeoutMs = 30000) {
  const started = Date.now();
  let controls = false;
  let badge = false;
  while (Date.now() - started < timeoutMs) {
    await page.waitForTimeout(800);
    await nudge(page);
    controls = await hasHostControls(page);
    badge = await isSelfHost(page);
    if (expected ? controls && badge : !controls && !badge) return { controls, badge };
  }
  return { controls, badge };
}

export const hasButton = (page, regex, enabledOnly = false) => page.evaluate(({ source, enabled }) => {
  const rx = new RegExp(source, 'i');
  const elements = [...document.querySelectorAll('[role="button"]')].filter((element) =>
    rx.test((element.textContent || '').trim()) &&
    element.getBoundingClientRect().width > 0 &&
    element.getBoundingClientRect().y >= 0);
  if (!elements.length) return false;
  if (!enabled) return true;
  return elements.some((element) => element.getAttribute('aria-disabled') !== 'true');
}, { source: regex.source, enabled: enabledOnly });

export async function tapButton(page, regex) {
  const box = await boxByText(page, regex);
  if (!box) return false;
  await tap(page, box);
  return true;
}

export async function setReadyAndStart(hostPage, playerPages) {
  for (const page of [...playerPages, hostPage]) {
    const ready = await boxByText(page, /Passer pret/i);
    if (ready) {
      await tap(page, ready);
      await page.waitForTimeout(1200);
    }
  }
  await hostPage.waitForTimeout(1500);
  await tap(hostPage, await boxByText(hostPage, /Lancer/i));
  await hostPage.waitForTimeout(1800);
  const confirm = await boxByText(hostPage, /^Lancer$/i);
  if (confirm) await tap(hostPage, confirm);
  await hostPage.waitForTimeout(9000);
}

export async function memorize(page) {
  for (let i = 0; i < 25; i++) {
    if (await boxByText(page, /^Carte à mémoriser 1$/)) break;
    await page.waitForTimeout(600);
  }
  const first = await boxByText(page, /^Carte à mémoriser 1$/);
  if (!first) throw new Error('carte memorisation 1 introuvable');
  if (first) await tap(page, first);
  await page.waitForTimeout(400);
  const second = await boxByText(page, /^Carte à mémoriser 2$/);
  if (!second) throw new Error('carte memorisation 2 introuvable');
  if (second) await tap(page, second);
  await page.waitForTimeout(400);
  const choose = await boxByText(page, /CHOISIS 2 CARTES/i);
  if (choose) await tap(page, choose);
}

export const hasGameTable = (page) => page.evaluate(() =>
  [...document.querySelectorAll('flt-semantics')].some((element) =>
    /Pioche|Défausse|Carte \d+ de/i.test(element.textContent || '')));

export const hasBlockingError = (page) => page.evaluate(() =>
  [...document.querySelectorAll('flt-semantics')].some((element) =>
    /Connexion perdue|Erreur|La partie va commencer|partie introuvable|salon introuvable/i
      .test(element.textContent || '')));

export const semanticTexts = (page) => page.evaluate(() =>
  [...new Set([...document.querySelectorAll('flt-semantics')]
    .map((element) => (element.textContent || '').trim())
    .filter((text) => text && text.length < 40))].slice(0, 50));

export async function playOneVisibleTurn(candidates, timeoutMs = 90000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    for (const { page, name } of candidates) {
      if (await hasButton(page, /PIOCHER/, true)) {
        await tapButton(page, /PIOCHER/);
        await page.waitForTimeout(1600);
        if (await tapButton(page, /JETER/)) {
          await page.waitForTimeout(2500);
          log(`${name} joue pioche+jette`);
          return name;
        }
      }
    }
    await candidates[0].page.waitForTimeout(800);
  }
  return null;
}
