import { NextFunction, Request, Response } from 'express';
import { admin } from '../services/FirebaseAdmin';

const APP_CHECK_HEADER = 'x-firebase-appcheck';

// Enforcement hard only when APP_CHECK_ENFORCE=true. Otherwise (default prod),
// missing or invalid tokens are logged but let through — reCAPTCHA v3 is flaky
// on mobile Safari and can throttle legitimate users for 24h after a transient
// Firebase/reCAPTCHA outage. Rate limiters + requireAuth still protect routes.
const ENFORCE =
  (process.env.APP_CHECK_ENFORCE ?? '').toLowerCase() === 'true';

export async function requireAppCheck(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  if (process.env.NODE_ENV !== 'production') {
    next();
    return;
  }

  if (admin.apps.length === 0) {
    if (ENFORCE) {
      res
        .status(503)
        .json({ success: false, error: 'Firebase App Check non configuré' });
      return;
    }
    next();
    return;
  }

  const token = req.header(APP_CHECK_HEADER)?.trim();
  if (!token) {
    if (ENFORCE) {
      res.status(401).json({
        success: false,
        error: 'App Check requis',
        code: 'APP_CHECK_REQUIRED',
      });
      return;
    }
    console.info(
      `[SECURITY][APP_CHECK] missing ip=${req.ip} path=${req.path}`,
    );
    next();
    return;
  }

  try {
    await admin.appCheck().verifyToken(token);
    next();
  } catch (error) {
    console.warn(
      `[SECURITY][APP_CHECK] token invalide ip=${req.ip} path=${req.path}`,
      error,
    );
    if (ENFORCE) {
      res.status(401).json({
        success: false,
        error: 'App Check invalide',
        code: 'APP_CHECK_INVALID',
      });
      return;
    }
    next();
  }
}
