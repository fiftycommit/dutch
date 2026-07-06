import { Router } from 'express';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { firestoreService } from '../services/FirestoreService';
import { authAbuseService } from '../services/AuthAbuseService';
import {
  PasswordAuthError,
  passwordAuthService,
} from '../services/PasswordAuthService';
import { ValidationService } from '../services/ValidationService';
import { rateLimit } from 'express-rate-limit';

const router = Router();

// Rate limiting pour la sécurité
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  skip: () => process.env.AUTH_ABUSE_DISABLED === '1' || process.env.E2E_TEST_HOOKS === '1',
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
  const abuseDecision = authAbuseService.assess(req, 'username_check');
  if (abuseDecision.blocked) {
    authAbuseService.reject(res, abuseDecision);
    return;
  }

  const username = req.query.username as string;
  if (!username) {
    res.json({ available: false });
    return;
  }
  const available = await firestoreService.isUsernameAvailable(username);
  res.json({ available });
});

// GET /api/auth/resolve-login?identifier=xxx
// Route legacy explicitement retirée pour éviter toute ambiguïté.
router.get('/resolve-login', authLimiter, async (req, res) => {
  const abuseDecision = authAbuseService.assess(req, 'login_resolve');
  if (abuseDecision.blocked) {
    authAbuseService.reject(res, abuseDecision);
    return;
  }

  const rawIdentifier = typeof req.query.identifier === 'string'
    ? req.query.identifier.trim()
    : '';

  if (!rawIdentifier) {
    res.status(400).json({ success: false, error: 'Identifiant requis' });
    return;
  }

  res.status(410).json({
    success: false,
    error: 'Cette route est obsolète. Utilisez login-password.',
  });
});

// POST /api/auth/register-password
router.post('/register-password', authLimiter, async (req, res) => {
  const abuseDecision = authAbuseService.assess(req, 'password_register');
  if (abuseDecision.blocked) {
    authAbuseService.reject(res, abuseDecision);
    return;
  }

  try {
    const { username, displayName, email, password } = req.body ?? {};

    const result = await passwordAuthService.registerWithPassword({
      username: typeof username === 'string' ? username : '',
      displayName: typeof displayName === 'string' ? displayName : '',
      email: typeof email === 'string' ? email : '',
      password: typeof password === 'string' ? password : '',
    });

    authAbuseService.noteProfileCreated(req, result.uid);
    res.status(201).json({
      success: true,
      customToken: result.customToken,
      user: {
        id: result.uid,
        username: result.username,
        displayName: result.displayName,
      },
    });
  } catch (error) {
    if (error instanceof PasswordAuthError) {
      res.status(error.statusCode).json({
        success: false,
        error: error.message,
        code: error.code,
      });
      return;
    }

    console.error('[AUTH] register-password failed', error);
    res.status(500).json({ success: false, error: 'Impossible de créer le compte' });
  }
});

// POST /api/auth/login-password
router.post('/login-password', authLimiter, async (req, res) => {
  const abuseDecision = authAbuseService.assess(req, 'password_login');
  if (abuseDecision.blocked) {
    authAbuseService.reject(res, abuseDecision);
    return;
  }

  try {
    const { identifier, password } = req.body ?? {};

    const result = await passwordAuthService.loginWithPassword({
      identifier: typeof identifier === 'string' ? identifier : '',
      password: typeof password === 'string' ? password : '',
      appCheckToken:
        typeof req.headers['x-firebase-appcheck'] === 'string'
          ? req.headers['x-firebase-appcheck']
          : undefined,
    });

    res.json({
      success: true,
      customToken: result.customToken,
      user: {
        id: result.uid,
        email: result.email,
      },
    });
  } catch (error) {
    if (error instanceof PasswordAuthError) {
      res.status(error.statusCode).json({
        success: false,
        error: error.message,
        code: error.code,
      });
      return;
    }

    console.error('[AUTH] login-password failed', error);
    res.status(500).json({ success: false, error: 'Impossible de se connecter' });
  }
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
    if (!ValidationService.isValidUsername(trimmed)) {
      res.status(400).json({
        success: false,
        error:
          'Nom d\'utilisateur invalide (3-20 caractères, lettres/chiffres/._-)',
      });
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
  const abuseDecision = authAbuseService.assess(
    req,
    existingUser ? 'profile_update' : 'profile_create',
  );
  if (abuseDecision.blocked) {
    authAbuseService.reject(res, abuseDecision);
    return;
  }

  if (existingUser) {
    await firestoreService.updateUser(authReq.user!.uid, updates);
  } else {
    await firestoreService.createUser(authReq.user!.uid, {
      username: updates.username || '',
      displayName: updates.displayName || '',
    });
    authAbuseService.noteProfileCreated(req, authReq.user!.uid);
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
