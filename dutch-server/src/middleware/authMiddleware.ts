import { Request, Response, NextFunction } from 'express';
import { auth } from '../services/FirebaseAdmin';

// ─── Firebase Auth Middleware (Express REST) ────────────────────────────────
// Remplace l'ancien authMiddleware.ts basé sur JWT.

export interface FirebaseAuthPayload {
  uid: string;
  email: string | null;
}

export interface AuthenticatedRequest extends Request {
  user?: FirebaseAuthPayload;
}

export async function requireAuth(req: Request, res: Response, next: NextFunction): Promise<void> {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ success: false, error: 'Token requis' });
    return;
  }

  if (!auth) {
    res.status(503).json({ success: false, error: 'Firebase Auth non configuré' });
    return;
  }

  try {
    const decoded = await auth.verifyIdToken(header.slice(7));
    (req as AuthenticatedRequest).user = {
      uid: decoded.uid,
      email: decoded.email || null,
    };
    next();
  } catch {
    res.status(401).json({ success: false, error: 'Token invalide ou expiré' });
  }
}
