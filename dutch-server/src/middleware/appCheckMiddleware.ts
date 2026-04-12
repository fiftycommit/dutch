import { NextFunction, Request, Response } from 'express';
import { admin } from '../services/FirebaseAdmin';

const APP_CHECK_HEADER = 'x-firebase-appcheck';

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
    res
      .status(503)
      .json({ success: false, error: 'Firebase App Check non configuré' });
    return;
  }

  const token = req.header(APP_CHECK_HEADER)?.trim();
  if (!token) {
    res.status(401).json({
      success: false,
      error: 'App Check requis',
      code: 'APP_CHECK_REQUIRED',
    });
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
    res.status(401).json({
      success: false,
      error: 'App Check invalide',
      code: 'APP_CHECK_INVALID',
    });
  }
}
