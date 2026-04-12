import { Request, Response, NextFunction } from 'express';
import { rateLimit } from 'express-rate-limit';
import { auth, firestore } from '../services/FirebaseAdmin';

// ─── Rate Limiter Admin (brute-force protection) ────────────────────────────
export const adminLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: 'Trop de tentatives, réessayez plus tard.' },
});

// ─── Admin check ────────────────────────────────────────────────────────────
// L'email admin est défini via la variable d'env ADMIN_EMAIL (secret GitHub).
// Seul cet email peut accéder aux dashboards admin.

export async function isAdmin(uid: string): Promise<boolean> {
  const adminEmail = process.env.ADMIN_EMAIL;
  if (!adminEmail || !auth) return false;

  try {
    const user = await auth.getUser(uid);
    return user.email?.toLowerCase() === adminEmail.toLowerCase();
  } catch {
    return false;
  }
}

// ─── Admin Auth Middleware ───────────────────────────────────────────────────
// Accepts:
// 1. Authorization: Bearer <firebase-id-token> (dashboard / browser)
// 2. X-Admin-Secret header (curl / scripts fallback)
export async function requireAdmin(req: Request, res: Response, next: NextFunction): Promise<void> {
  const ip = req.headers['x-forwarded-for'] || req.ip || req.socket.remoteAddress;

  // 1. Try Firebase token
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ') && auth) {
    try {
      const decoded = await auth.verifyIdToken(authHeader.slice(7));
      if (await isAdmin(decoded.uid)) {
        (req as any).adminUid = decoded.uid;
        next();
        return;
      }
      console.warn(`[SECURITY] Non-admin Firebase user — uid: ${decoded.uid}, email: ${decoded.email}, IP: ${ip}, path: ${req.path}`);
      res.status(403).json({ success: false, error: 'Accès refusé — compte non administrateur' });
      return;
    } catch {
      // Token invalid, fall through to X-Admin-Secret
    }
  }

  // 2. Fallback: X-Admin-Secret (for curl/scripts)
  const secret = req.headers['x-admin-secret'] as string | undefined;
  const envSecret = process.env.ADMIN_SECRET;
  if (secret && envSecret && secret === envSecret) {
    next();
    return;
  }

  console.warn(`[SECURITY] Admin auth failed — IP: ${ip}, path: ${req.path}, time: ${new Date().toISOString()}`);
  res.status(403).json({ success: false, error: 'Accès refusé' });
}
