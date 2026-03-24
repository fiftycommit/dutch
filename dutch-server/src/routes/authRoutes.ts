import { Router } from 'express';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { firestoreService } from '../services/FirestoreService';
import { auth } from '../services/FirebaseAdmin';
import { rateLimit } from 'express-rate-limit';

const router = Router();

// Rate limiting pour la sécurité
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  message: { success: false, error: 'Trop de tentatives, réessayez dans 15 minutes' },
});
const emailRegex = /^[^\s@]{1,64}@[^\s@]{1,253}\.[^\s@]{1,63}$/;

// ── Les routes register/login/forgot-password/reset-password sont supprimées ──
// L'authentification est désormais gérée côté client par Firebase Auth SDK.
// Le serveur ne fait que VÉRIFIER les tokens.

// GET /api/auth/me
router.get('/me', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const user = await firestoreService.getUser(authReq.user!.uid);

  if (!user) {
    res.status(404).json({ success: false, error: 'Utilisateur introuvable' });
    return;
  }

  res.json({
    success: true,
    user: {
      id: authReq.user!.uid,
      username: user.username,
      displayName: user.displayName,
    },
  });
});

// GET /api/auth/check-username?username=xxx
router.get('/check-username', async (req, res) => {
  const username = req.query.username as string;
  if (!username) {
    res.json({ available: false });
    return;
  }
  const available = await firestoreService.isUsernameAvailable(username);
  res.json({ available });
});

// GET /api/auth/resolve-login?identifier=xxx
// Résout email|username vers l'email Firebase utilisé pour sign-in.
router.get('/resolve-login', authLimiter, async (req, res) => {
  const rawIdentifier = typeof req.query.identifier === 'string'
    ? req.query.identifier.trim()
    : '';

  if (!rawIdentifier) {
    res.status(400).json({ success: false, error: 'Identifiant requis' });
    return;
  }

  if (emailRegex.test(rawIdentifier)) {
    res.json({ success: true, loginEmail: rawIdentifier.toLowerCase() });
    return;
  }

  const normalizedUsername = rawIdentifier.toLowerCase();
  const userByUsername = await firestoreService.getUserByUsername(normalizedUsername);
  if (!userByUsername) {
    res.status(404).json({ success: false, error: 'Identifiant introuvable' });
    return;
  }

  let loginEmail = userByUsername.data.email?.trim().toLowerCase() || null;

  if (!loginEmail && auth) {
    try {
      const userRecord = await auth.getUser(userByUsername.uid);
      loginEmail = userRecord.email?.trim().toLowerCase() || null;
    } catch {
      loginEmail = null;
    }
  }

  if (!loginEmail || !emailRegex.test(loginEmail)) {
    res.status(404).json({ success: false, error: 'Identifiant introuvable' });
    return;
  }

  // Backfill opportuniste pour accélérer les prochaines résolutions.
  if (userByUsername.data.email !== loginEmail) {
    void firestoreService.updateUser(userByUsername.uid, { email: loginEmail });
  }

  res.json({ success: true, loginEmail });
});

// PUT /api/auth/profile
router.put('/profile', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { displayName, username } = req.body;

  const updates: Record<string, string> = {};

  // Validation displayName
  if (displayName && typeof displayName === 'string' && displayName.trim().length > 0 && displayName.trim().length <= 24) {
    updates.displayName = displayName.trim();
  }

  // Validation username (optionnel, envoyé à l'inscription)
  if (username && typeof username === 'string') {
    const trimmed = username.trim().toLowerCase();
    if (trimmed.length < 3 || trimmed.length > 20 || !/^[a-z0-9_]+$/.test(trimmed)) {
      res.status(400).json({ success: false, error: 'Nom d\'utilisateur invalide (3-20 caractères, lettres/chiffres/_)' });
      return;
    }
    // Vérifier unicité
    const available = await firestoreService.isUsernameAvailable(trimmed, authReq.user!.uid);
    if (!available) {
      res.status(409).json({ success: false, error: 'Ce nom d\'utilisateur est déjà pris' });
      return;
    }
    updates.username = trimmed;
  }

  if (Object.keys(updates).length === 0) {
    res.status(400).json({ success: false, error: 'Aucune donnée valide à mettre à jour' });
    return;
  }

  // Créer le document s'il n'existe pas encore (première inscription)
  const existingUser = await firestoreService.getUser(authReq.user!.uid);
  if (existingUser) {
    await firestoreService.updateUser(authReq.user!.uid, updates);
  } else {
    await firestoreService.createUser(authReq.user!.uid, {
      username: updates.username || '',
      displayName: updates.displayName || '',
    });
  }

  const user = await firestoreService.getUser(authReq.user!.uid);
  res.json({
    success: true,
    user: user ? {
      id: authReq.user!.uid,
      username: user.username,
      displayName: user.displayName,
    } : undefined,
  });
});

// POST /api/auth/device-token
router.post('/device-token', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { token, platform } = req.body;

  if (!token || !platform) {
    res.status(400).json({ success: false, error: 'Token et plateforme requis' });
    return;
  }

  await firestoreService.registerDeviceToken(authReq.user!.uid, token, platform);
  res.json({ success: true });
});

// DELETE /api/auth/device-token
router.delete('/device-token', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { token } = req.body;

  if (!token) {
    res.status(400).json({ success: false, error: 'Token requis' });
    return;
  }

  await firestoreService.removeDeviceToken(authReq.user!.uid, token);
  res.json({ success: true });
});

// DELETE /api/auth/account — Suppression de compte
router.delete('/account', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;

  try {
    await firestoreService.deleteUser(authReq.user!.uid);
    // Optionnel: supprimer aussi l'utilisateur dans Firebase Auth
    // await auth.deleteUser(authReq.user!.uid);
    res.json({ success: true });
  } catch {
    res.status(500).json({ success: false, error: 'Erreur lors de la suppression' });
  }
});

export default router;
