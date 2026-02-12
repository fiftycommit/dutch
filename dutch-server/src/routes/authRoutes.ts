import { Router } from 'express';
import { AuthService } from '../services/AuthService';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { rateLimit } from 'express-rate-limit';

const router = Router();

// Rate limiting strict pour l'auth
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: { success: false, error: 'Trop de tentatives, réessayez dans 15 minutes' },
});

const registerLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  message: { success: false, error: 'Trop d\'inscriptions, réessayez dans 15 minutes' },
});

const forgotPasswordLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  message: {
    success: false,
    error: 'Trop de demandes, réessayez dans 15 minutes',
  },
});

const resetPasswordLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: {
    success: false,
    error: 'Trop de tentatives, réessayez dans 15 minutes',
  },
});

// POST /api/auth/register
router.post('/register', registerLimiter, (req, res) => {
  const { username, displayName, email, password } = req.body;
  const result = AuthService.register(username, displayName, email, password);

  if (!result.success) {
    const isConflict =
      result.error?.includes('déjà') || result.error?.includes('deja');
    const status = isConflict ? 409 : 400;
    res.status(status).json(result);
    return;
  }

  res.status(201).json(result);
});

// POST /api/auth/login
router.post('/login', authLimiter, (req, res) => {
  const { username, password } = req.body;
  const result = AuthService.login(username, password);

  if (!result.success) {
    res.status(401).json(result);
    return;
  }

  res.json(result);
});

// POST /api/auth/forgot-password
router.post(
  '/forgot-password',
  forgotPasswordLimiter,
  async (req, res) => {
    const { email } = req.body ?? {};
    const result = await AuthService.requestPasswordReset(email);

    if (!result.success) {
      const status = result.error?.includes('Email invalide') ? 400 : 500;
      res.status(status).json(result);
      return;
    }

    res.json({
      success: true,
      message:
        'Si un compte existe avec cet email, un lien de reinitialisation a ete envoye.',
    });
  }
);

// POST /api/auth/reset-password
router.post('/reset-password', resetPasswordLimiter, (req, res) => {
  const { token, newPassword } = req.body ?? {};
  const result = AuthService.resetPasswordWithToken(token, newPassword);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json({ success: true });
});

// GET /api/auth/me
router.get('/me', requireAuth, (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const user = AuthService.getUser(authReq.user!.userId);

  if (!user) {
    res.status(404).json({ success: false, error: 'Utilisateur introuvable' });
    return;
  }

  res.json({ success: true, user });
});

// GET /api/auth/check-username?username=xxx
router.get('/check-username', (req, res) => {
  const username = req.query.username as string;
  const available = AuthService.isUsernameAvailable(username);
  res.json({ available });
});

// PUT /api/auth/profile
router.put('/profile', requireAuth, (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { displayName } = req.body;
  const result = AuthService.updateProfile(authReq.user!.userId, displayName);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// PUT /api/auth/password
router.put('/password', requireAuth, (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { currentPassword, newPassword } = req.body ?? {};
  const result = AuthService.changePassword(
    authReq.user!.userId,
    currentPassword,
    newPassword
  );

  if (!result.success) {
    if (result.error?.includes('incorrect')) {
      res.status(401).json(result);
      return;
    }
    res.status(400).json(result);
    return;
  }

  res.json({ success: true });
});

// DELETE /api/auth/account
router.delete('/account', requireAuth, (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { password } = req.body ?? {};
  const result = AuthService.deleteAccount(authReq.user!.userId, password);

  if (!result.success) {
    if (result.error?.includes('incorrect')) {
      res.status(401).json(result);
      return;
    }
    res.status(400).json(result);
    return;
  }

  res.json({ success: true });
});

// POST /api/auth/device-token
router.post('/device-token', requireAuth, (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { token, platform } = req.body;

  if (!token || !platform) {
    res.status(400).json({ success: false, error: 'Token et plateforme requis' });
    return;
  }

  AuthService.registerDeviceToken(authReq.user!.userId, token, platform);
  res.json({ success: true });
});

// DELETE /api/auth/device-token
router.delete('/device-token', requireAuth, (req, res) => {
  const { token } = req.body;

  if (!token) {
    res.status(400).json({ success: false, error: 'Token requis' });
    return;
  }

  AuthService.removeDeviceToken(token);
  res.json({ success: true });
});

export default router;
