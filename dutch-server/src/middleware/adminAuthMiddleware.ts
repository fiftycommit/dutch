import { Request, Response, NextFunction } from 'express';
import { rateLimit } from 'express-rate-limit';
import { auth } from '../services/FirebaseAdmin';

export const ADMIN_SESSION_COOKIE_NAME = 'dutch_admin_session';
export const ADMIN_SESSION_MAX_AGE_MS = 12 * 60 * 60 * 1000;

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

function getRequestIp(req: Request): string {
  const forwardedFor = req.headers['x-forwarded-for'];
  if (typeof forwardedFor === 'string' && forwardedFor.trim()) {
    return forwardedFor.split(',')[0].trim();
  }
  return req.ip || req.socket.remoteAddress || 'unknown';
}

function getCookieValue(req: Request, cookieName: string): string | null {
  const cookieHeader = req.headers.cookie;
  if (!cookieHeader) return null;

  for (const rawCookie of cookieHeader.split(';')) {
    const separatorIndex = rawCookie.indexOf('=');
    if (separatorIndex <= 0) continue;

    const key = rawCookie.slice(0, separatorIndex).trim();
    if (key !== cookieName) continue;

    const value = rawCookie.slice(separatorIndex + 1).trim();
    if (!value) return null;

    try {
      return decodeURIComponent(value);
    } catch {
      return value;
    }
  }

  return null;
}

export interface AdminAccessResult {
  ok: boolean;
  adminUid?: string;
  mode?: 'firebase-token' | 'session-cookie' | 'admin-secret';
}

async function verifyFirebaseAdminToken(idToken: string): Promise<AdminAccessResult> {
  if (!auth) {
    return { ok: false };
  }

  try {
    const decoded = await auth.verifyIdToken(idToken);
    if (!await isAdmin(decoded.uid)) {
      return { ok: false };
    }

    return {
      ok: true,
      adminUid: decoded.uid,
      mode: 'firebase-token',
    };
  } catch {
    return { ok: false };
  }
}

async function verifyAdminSessionCookie(sessionCookie: string): Promise<AdminAccessResult> {
  if (!auth) {
    return { ok: false };
  }

  try {
    const decoded = await auth.verifySessionCookie(sessionCookie, true);
    if (!await isAdmin(decoded.uid)) {
      return { ok: false };
    }

    return {
      ok: true,
      adminUid: decoded.uid,
      mode: 'session-cookie',
    };
  } catch {
    return { ok: false };
  }
}

export async function resolveAdminAccess(req: Request): Promise<AdminAccessResult> {
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    const bearerAccess = await verifyFirebaseAdminToken(authHeader.slice(7));
    if (bearerAccess.ok) {
      return bearerAccess;
    }
  }

  const sessionCookie = getCookieValue(req, ADMIN_SESSION_COOKIE_NAME);
  if (sessionCookie) {
    const sessionAccess = await verifyAdminSessionCookie(sessionCookie);
    if (sessionAccess.ok) {
      return sessionAccess;
    }
  }

  const secret = req.headers['x-admin-secret'] as string | undefined;
  const envSecret = process.env.ADMIN_SECRET;
  if (secret && envSecret && secret === envSecret) {
    return {
      ok: true,
      mode: 'admin-secret',
    };
  }

  return { ok: false };
}

// ─── Admin Auth Middleware ───────────────────────────────────────────────────
// Accepts:
// 1. Authorization: Bearer <firebase-id-token> (dashboard / browser)
// 2. X-Admin-Secret header (curl / scripts fallback)
export async function requireAdmin(req: Request, res: Response, next: NextFunction): Promise<void> {
  const ip = getRequestIp(req);
  const access = await resolveAdminAccess(req);

  if (access.ok) {
    if (access.adminUid) {
      (req as any).adminUid = access.adminUid;
    }
    next();
    return;
  }

  console.warn(`[SECURITY] Admin auth failed — IP: ${ip}, path: ${req.path}, time: ${new Date().toISOString()}`);
  res.status(403).json({ success: false, error: 'Accès refusé' });
}

export async function requireAdminPage(req: Request, res: Response, next: NextFunction): Promise<void> {
  const access = await resolveAdminAccess(req);
  if (access.ok) {
    if (access.adminUid) {
      (req as any).adminUid = access.adminUid;
    }
    next();
    return;
  }

  const nextPath = encodeURIComponent(req.originalUrl || '/admin-home');
  res.redirect(302, `/admin-login?next=${nextPath}`);
}
