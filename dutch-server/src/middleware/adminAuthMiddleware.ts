import { Request, Response, NextFunction } from 'express';
import { rateLimit } from 'express-rate-limit';
import { adminAuthService } from '../services/AdminAuthService';

// ─── Rate Limiter Admin (brute-force protection) ────────────────────────────
// 10 requêtes / 15 min par IP — bloque le brute-force sur le secret admin
export const adminLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
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

// ─── Admin Auth Middleware ───────────────────────────────────────────────────
// Vérifie le header X-Admin-Secret contre le mot de passe stocké (ou ADMIN_SECRET env si pas encore changé)
export function requireAdmin(req: Request, res: Response, next: NextFunction): void {
  const secret = req.headers['x-admin-secret'] as string | undefined;
  if (!secret || !adminAuthService.verify(secret)) {
    const ip = req.headers['x-forwarded-for'] || req.ip || req.socket.remoteAddress;
    console.warn(`[SECURITY] Admin auth failed — IP: ${ip}, path: ${req.path}, time: ${new Date().toISOString()}`);
    res.status(403).json({ success: false, error: 'Accès refusé' });
    return;
  }
  next();
}
