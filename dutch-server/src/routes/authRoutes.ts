import { Router } from 'express';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { firestoreService } from '../services/FirestoreService';
import { rateLimit } from 'express-rate-limit';

const router = Router();

// Rate limiting pour la sécurité
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  message: { success: false, error: 'Trop de tentatives, réessayez dans 15 minutes' },
});

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

// PUT /api/auth/profile
router.put('/profile', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { displayName } = req.body;

  if (!displayName || typeof displayName !== 'string' || displayName.trim().length === 0 || displayName.trim().length > 24) {
    res.status(400).json({ success: false, error: 'Pseudo invalide (1-24 caractères)' });
    return;
  }

  await firestoreService.updateUser(authReq.user!.uid, { displayName: displayName.trim() });

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
