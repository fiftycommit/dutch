/**
 * Admin Auth Gate — Firebase Google Sign-In for all dashboards.
 *
 * Usage:
 *   <div id="auth-gate"></div>
 *   <div id="app-content" style="display:none"> ... </div>
 *   <script src="/admin-auth.js"></script>
 *   <script>initAdminAuth({ onReady() { ... } });</script>
 */

/* ── Firebase Config ── */
const FIREBASE_CONFIG = {
  apiKey: 'AIzaSyAbECOaA-3eC5MQasl7K12h0drKkm4rKfc',
  authDomain: 'dutch-game.me',
  projectId: 'dutch-game-1dd01',
};

let _firebaseApp = null;
let _firebaseAuth = null;
let _idToken = '';
const SCRIPT_INTEGRITY = {
  'https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js':
    'sha384-sEVIly94UBRLKWdkYoPpSG7GD/e79YHMrxVyZaOk712Ga7+EAw6w1EFi+xBzBdd+',
  'https://www.gstatic.com/firebasejs/10.12.0/firebase-auth-compat.js':
    'sha384-EkqK+ezBWJuvO3hfrSx2iVqr3YQbhmnzn8kPhOpBZ+0GMVU5oGSgptwIu8D84HjE',
};

/** Get current ID token for API calls */
function getAdminSecret() { return _idToken; }

function sanitizeAdminPath(path, fallback = '/admin-home') {
  if (typeof path !== 'string' || !path.startsWith('/') || path.startsWith('//')) {
    return fallback;
  }
  if (path === '/admin-login') {
    return fallback;
  }
  return path;
}

function getAdminNextPath(fallback = '/admin-home') {
  const params = new URLSearchParams(window.location.search);
  return sanitizeAdminPath(params.get('next'), fallback);
}

function getAdminLoginUrl(nextPath) {
  const params = new URLSearchParams();
  const safeNextPath = sanitizeAdminPath(nextPath, '');
  if (safeNextPath) {
    params.set('next', safeNextPath);
  }
  const query = params.toString();
  return query ? `/admin-login?${query}` : '/admin-login';
}

/** Helper to call admin-protected APIs */
async function adminFetch(url, opts = {}) {
  // Refresh token if needed
  if (_firebaseAuth?.currentUser) {
    _idToken = await _firebaseAuth.currentUser.getIdToken();
  }
  const res = await fetch(url, {
    ...opts,
    credentials: 'same-origin',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${_idToken}`,
      ...(opts.headers || {}),
    },
  });
  if (res.status === 403 || res.status === 401) throw new Error('Forbidden');
  return res.json();
}

async function ensureAdminSession() {
  const res = await fetch('/api/admin/session', {
    method: 'POST',
    credentials: 'same-origin',
    headers: {
      'Authorization': `Bearer ${_idToken}`,
    },
  });

  if (!res.ok) {
    throw new Error(`Session admin refusée (${res.status})`);
  }

  return res.json();
}

/* ── Load Firebase SDK ── */
function loadScript(src) {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) { resolve(); return; }
    const s = document.createElement('script');
    s.src = src;
    const integrity = SCRIPT_INTEGRITY[src];
    if (integrity) {
      s.integrity = integrity;
      s.crossOrigin = 'anonymous';
    }
    s.onload = resolve;
    s.onerror = reject;
    document.head.appendChild(s);
  });
}

async function initFirebase() {
  await loadScript('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
  await loadScript('https://www.gstatic.com/firebasejs/10.12.0/firebase-auth-compat.js');
  _firebaseApp = firebase.initializeApp(FIREBASE_CONFIG);
  _firebaseAuth = firebase.auth();
}

function isSafariLikeBrowser() {
  const ua = navigator.userAgent || '';
  const isSafari = /Safari/i.test(ua) && !/Chrome|Chromium|CriOS|Edg|Firefox|FxiOS/i.test(ua);
  const isIOSWebKit = /iPhone|iPad|iPod/i.test(ua);
  return isSafari || isIOSWebKit;
}

function isPopupFallbackError(error) {
  const code = error?.code || '';
  return [
    'auth/popup-blocked',
    'auth/popup-closed-by-user',
    'auth/cancelled-popup-request',
    'auth/internal-error',
  ].includes(code);
}

async function signInWithGoogleForAdmin() {
  const provider = new firebase.auth.GoogleAuthProvider();

  // Safari / iOS gèrent mieux la redirection complète que le popup Firebase.
  if (isSafariLikeBrowser()) {
    await _firebaseAuth.signInWithRedirect(provider);
    return;
  }

  try {
    await _firebaseAuth.signInWithPopup(provider);
  } catch (error) {
    if (!isPopupFallbackError(error)) {
      throw error;
    }
    await _firebaseAuth.signInWithRedirect(provider);
  }
}

/* ── Main ── */
async function initAdminAuth({
  onReady,
  redirectAuthenticatedTo = '',
  redirectUnauthenticatedTo = '',
} = {}) {
  const gate = document.getElementById('auth-gate');
  const app = document.getElementById('app-content');
  const safeAuthenticatedRedirect = sanitizeAdminPath(redirectAuthenticatedTo, '');
  const safeUnauthenticatedRedirect = sanitizeAdminPath(redirectUnauthenticatedTo, '');

  showLoading(gate);

  await initFirebase();

  // Check if already signed in
  _firebaseAuth.onAuthStateChanged(async (user) => {
    if (user) {
      _idToken = await user.getIdToken();
      const ok = await checkAdminAccess(user);
      if (ok) {
        try {
          await ensureAdminSession();
        } catch (error) {
          showError(
            gate,
            `Impossible d'ouvrir la session admin: ${error?.message || 'erreur inconnue'}`,
          );
          return;
        }
        if (safeAuthenticatedRedirect && window.location.pathname !== safeAuthenticatedRedirect) {
          window.location.replace(safeAuthenticatedRedirect);
          return;
        }
        gate.style.display = 'none';
        app.style.display = '';
        if (typeof onReady === 'function') {
          onReady();
        }
      } else {
        showDenied(gate, user);
      }
    } else {
      if (safeUnauthenticatedRedirect) {
        window.location.replace(safeUnauthenticatedRedirect);
        return;
      }
      showLoginForm(gate, app, onReady);
    }
  });
}

async function checkAdminAccess(user) {
  try {
    const res = await fetch('/api/admin/verify', {
      headers: { 'Authorization': `Bearer ${_idToken}` },
    });
    const data = await res.json();
    return data.success === true;
  } catch {
    return false;
  }
}

function showLoading(gate) {
  gate.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:center;min-height:100vh">
      <div style="color:#fbbf24;font-size:1.2em">Chargement...</div>
    </div>
  `;
}

function showLoginForm(gate, app, onReady) {
  gate.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:center;min-height:100vh">
      <div style="background:rgba(26,29,41,0.95);border-radius:16px;padding:40px;width:100%;max-width:400px;box-shadow:0 8px 32px rgba(0,0,0,.4);text-align:center">
        <h1 style="margin-bottom:8px;color:#fbbf24;font-size:1.6em">Dutch Admin</h1>
        <p style="color:#94a3b8;font-size:13px;margin-bottom:24px">Connecte-toi avec ton compte Google pour acceder au panel admin.</p>
        <div id="auth-error" style="color:#f87171;font-size:13px;margin-bottom:12px"></div>
        <button id="auth-google-btn"
          style="width:100%;padding:12px;border:none;border-radius:8px;background:#fff;color:#333;font-size:14px;font-weight:600;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:10px">
          <svg width="18" height="18" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>
          Se connecter avec Google
        </button>
      </div>
    </div>
  `;
  gate.style.display = '';
  app.style.display = 'none';

  document.getElementById('auth-google-btn').addEventListener('click', async () => {
    const error = document.getElementById('auth-error');
    error.textContent = '';
    try {
      await signInWithGoogleForAdmin();
      // onAuthStateChanged will handle the rest
    } catch (e) {
      error.textContent = e.message || 'Erreur de connexion';
    }
  });
}

function showDenied(gate, user) {
  gate.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:center;min-height:100vh">
      <div style="background:rgba(26,29,41,0.95);border-radius:16px;padding:40px;width:100%;max-width:440px;box-shadow:0 8px 32px rgba(0,0,0,.4);text-align:center">
        <h1 style="margin-bottom:8px;color:#f87171;font-size:1.5em">Acces refuse</h1>
        <p style="color:#94a3b8;font-size:13px;margin-bottom:16px">
          Le compte <strong style="color:#e2e8f0">${user.email}</strong> n'est pas administrateur.
        </p>
        <button id="auth-denied-logout-btn"
          style="padding:10px 24px;border:1px solid #2d3148;border-radius:8px;background:transparent;color:#94a3b8;cursor:pointer;font-size:13px">
          Se deconnecter
        </button>
      </div>
    </div>
  `;
  document.getElementById('auth-denied-logout-btn')?.addEventListener('click', () => {
    void adminLogout();
  });
}

function showError(gate, message) {
  gate.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:center;min-height:100vh">
      <div style="background:rgba(26,29,41,0.95);border-radius:16px;padding:40px;width:100%;max-width:460px;box-shadow:0 8px 32px rgba(0,0,0,.4);text-align:center">
        <h1 style="margin-bottom:8px;color:#f87171;font-size:1.5em">Erreur</h1>
        <p style="color:#e2e8f0;font-size:14px;line-height:1.5">${message}</p>
        <button id="auth-error-reload-btn"
          style="margin-top:16px;padding:10px 24px;border:1px solid #2d3148;border-radius:8px;background:transparent;color:#94a3b8;cursor:pointer;font-size:13px">
          Recharger
        </button>
      </div>
    </div>
  `;
  document.getElementById('auth-error-reload-btn')?.addEventListener('click', () => {
    location.reload();
  });
}

/** Logout */
async function adminLogout() {
  try {
    await fetch('/api/admin/session', {
      method: 'DELETE',
      credentials: 'same-origin',
    });
  } catch (_) {
    // Best effort : on supprime quand même la session Firebase côté client.
  }
  if (_firebaseAuth) await _firebaseAuth.signOut();
  _idToken = '';
  location.reload();
}
