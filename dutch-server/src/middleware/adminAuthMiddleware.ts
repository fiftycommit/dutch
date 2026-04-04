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
  keyGenerator: (req) => {
    const xff = req.headers['x-forwarded-for'];
    if (typeof xff === 'string' && xff.trim().length > 0) {
      return xff.split(',')[0].trim();
    }
    if (Array.isArray(xff) && xff.length > 0 && xff[0]) {
      return xff[0].split(',')[0].trim();
    }
    return req.ip || req.socket.remoteAddress || 'unknown';
  },
});

// ─── Admin UID helpers ──────────────────────────────────────────────────────
const ADMIN_DOC = 'admin_config/settings';

async function getAdminUids(): Promise<string[]> {
  if (!firestore) return [];
  try {
    const doc = await firestore.doc(ADMIN_DOC).get();
    if (!doc.exists) return [];
    return doc.data()?.adminUids || [];
  } catch {
    return [];
  }
}

async function addAdminUid(uid: string): Promise<void> {
  if (!firestore) return;
  const doc = firestore.doc(ADMIN_DOC);
  const snap = await doc.get();
  if (!snap.exists) {
    await doc.set({ adminUids: [uid], createdAt: new Date() });
  } else {
    const uids: string[] = snap.data()?.adminUids || [];
    if (!uids.includes(uid)) {
      uids.push(uid);
      await doc.update({ adminUids: uids });
    }
  }
}

export async function isAdmin(uid: string): Promise<boolean> {
  const uids = await getAdminUids();
  // First user becomes admin automatically
  if (uids.length === 0) {
    await addAdminUid(uid);
    console.log(`[AdminAuth] First admin registered: ${uid}`);
    return true;
  }
  return uids.includes(uid);
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
      console.warn(`[SECURITY] Non-admin Firebase user — uid: ${decoded.uid}, IP: ${ip}, path: ${req.path}`);
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
