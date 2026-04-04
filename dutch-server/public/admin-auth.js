/**
 * Admin Auth Gate — shared login + password change for all dashboards.
 *
 * Usage in any dashboard HTML:
 *   <div id="auth-gate"></div>
 *   <div id="app-content" style="display:none"> ... dashboard content ... </div>
 *   <script src="/admin-auth.js"></script>
 *   <script>
 *     initAdminAuth({ onReady() { // called once authenticated } });
 *   </script>
 */

/* ── State ── */
let _adminSecret = sessionStorage.getItem('adminSecret') || '';

/** Get the current admin secret (for use in fetch headers) */
function getAdminSecret() { return _adminSecret; }

/** Helper to call admin-protected APIs */
async function adminFetch(url, opts = {}) {
  const res = await fetch(url, {
    ...opts,
    headers: {
      'Content-Type': 'application/json',
      'X-Admin-Secret': _adminSecret,
      ...(opts.headers || {}),
    },
  });
  if (res.status === 403) throw new Error('Forbidden');
  return res.json();
}

/* ── UI ��─ */
function initAdminAuth({ onReady }) {
  const gate = document.getElementById('auth-gate');
  const app = document.getElementById('app-content');

  // If we already have a secret in session, try it
  if (_adminSecret) {
    verifyAndProceed(onReady, gate, app);
    return;
  }

  showLoginForm(gate, app, onReady);
}

async function verifyAndProceed(onReady, gate, app) {
  try {
    const res = await fetch('/api/admin/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: _adminSecret }),
    });
    const data = await res.json();
    if (!data.success) {
      sessionStorage.removeItem('adminSecret');
      _adminSecret = '';
      showLoginForm(gate, app, onReady);
      return;
    }
    if (data.mustChangePassword) {
      showChangePasswordForm(gate, app, onReady);
      return;
    }
    gate.style.display = 'none';
    app.style.display = '';
    onReady();
  } catch {
    sessionStorage.removeItem('adminSecret');
    _adminSecret = '';
    showLoginForm(gate, app, onReady);
  }
}

function showLoginForm(gate, app, onReady) {
  gate.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:center;min-height:100vh">
      <div style="background:rgba(26,29,41,0.95);border-radius:16px;padding:40px;width:100%;max-width:400px;box-shadow:0 8px 32px rgba(0,0,0,.4)">
        <h1 style="text-align:center;margin-bottom:24px;color:#fbbf24;font-size:1.6em">🔒 Connexion Admin</h1>
        <input type="password" id="auth-password" placeholder="Mot de passe" autofocus
          style="width:100%;padding:12px 16px;border:1px solid #2d3148;background:#12141e;color:#e2e8f0;border-radius:8px;font-size:14px;margin-bottom:16px;outline:none">
        <div id="auth-error" style="color:#f87171;font-size:13px;margin-bottom:12px"></div>
        <button id="auth-submit"
          style="width:100%;padding:12px;border:none;border-radius:8px;background:#fbbf24;color:#000;font-size:14px;font-weight:600;cursor:pointer">
          Connexion
        </button>
      </div>
    </div>
  `;
  gate.style.display = '';
  app.style.display = 'none';

  const input = document.getElementById('auth-password');
  const btn = document.getElementById('auth-submit');
  const error = document.getElementById('auth-error');

  input.addEventListener('keydown', e => { if (e.key === 'Enter') doLogin(); });
  btn.addEventListener('click', doLogin);

  async function doLogin() {
    const password = input.value.trim();
    if (!password) return;
    error.textContent = '';
    btn.disabled = true;
    btn.textContent = '...';

    try {
      const res = await fetch('/api/admin/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      });
      const data = await res.json();

      if (!data.success) {
        error.textContent = data.error || 'Mot de passe invalide';
        btn.disabled = false;
        btn.textContent = 'Connexion';
        return;
      }

      _adminSecret = password;
      sessionStorage.setItem('adminSecret', password);

      if (data.mustChangePassword) {
        showChangePasswordForm(gate, app, onReady);
      } else {
        gate.style.display = 'none';
        app.style.display = '';
        onReady();
      }
    } catch {
      error.textContent = 'Erreur de connexion';
      btn.disabled = false;
      btn.textContent = 'Connexion';
    }
  }
}

function showChangePasswordForm(gate, app, onReady) {
  gate.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:center;min-height:100vh">
      <div style="background:rgba(26,29,41,0.95);border-radius:16px;padding:40px;width:100%;max-width:440px;box-shadow:0 8px 32px rgba(0,0,0,.4)">
        <h1 style="text-align:center;margin-bottom:8px;color:#fbbf24;font-size:1.5em">🔑 Changement de mot de passe</h1>
        <p style="text-align:center;color:#94a3b8;font-size:13px;margin-bottom:24px">
          Première connexion — vous devez définir un nouveau mot de passe.
        </p>
        <input type="password" id="cp-new" placeholder="Nouveau mot de passe (min. 8 caractères)"
          style="width:100%;padding:12px 16px;border:1px solid #2d3148;background:#12141e;color:#e2e8f0;border-radius:8px;font-size:14px;margin-bottom:12px;outline:none">
        <input type="password" id="cp-confirm" placeholder="Confirmer le mot de passe"
          style="width:100%;padding:12px 16px;border:1px solid #2d3148;background:#12141e;color:#e2e8f0;border-radius:8px;font-size:14px;margin-bottom:16px;outline:none">
        <div id="cp-error" style="color:#f87171;font-size:13px;margin-bottom:12px"></div>
        <button id="cp-submit"
          style="width:100%;padding:12px;border:none;border-radius:8px;background:#fbbf24;color:#000;font-size:14px;font-weight:600;cursor:pointer">
          Changer le mot de passe
        </button>
      </div>
    </div>
  `;
  gate.style.display = '';
  app.style.display = 'none';

  const newInput = document.getElementById('cp-new');
  const confirmInput = document.getElementById('cp-confirm');
  const btn = document.getElementById('cp-submit');
  const error = document.getElementById('cp-error');

  newInput.focus();
  confirmInput.addEventListener('keydown', e => { if (e.key === 'Enter') doChange(); });
  btn.addEventListener('click', doChange);

  async function doChange() {
    const newPw = newInput.value;
    const confirm = confirmInput.value;
    error.textContent = '';

    if (newPw.length < 8) {
      error.textContent = 'Le mot de passe doit faire au moins 8 caractères';
      return;
    }
    if (newPw !== confirm) {
      error.textContent = 'Les mots de passe ne correspondent pas';
      return;
    }

    btn.disabled = true;
    btn.textContent = '...';

    try {
      const res = await fetch('/api/admin/change-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ currentPassword: _adminSecret, newPassword: newPw }),
      });
      const data = await res.json();

      if (!data.success) {
        error.textContent = data.error || 'Erreur lors du changement';
        btn.disabled = false;
        btn.textContent = 'Changer le mot de passe';
        return;
      }

      // Update stored secret to the new password
      _adminSecret = newPw;
      sessionStorage.setItem('adminSecret', newPw);

      gate.style.display = 'none';
      app.style.display = '';
      onReady();
    } catch {
      error.textContent = 'Erreur de connexion';
      btn.disabled = false;
      btn.textContent = 'Changer le mot de passe';
    }
  }
}

/** Logout — clear session and reload */
function adminLogout() {
  _adminSecret = '';
  sessionStorage.removeItem('adminSecret');
  location.reload();
}
