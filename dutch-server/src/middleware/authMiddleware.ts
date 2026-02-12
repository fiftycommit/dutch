import { Request, Response, NextFunction } from 'express';
import { AuthService, JwtPayload } from '../services/AuthService';

export interface AuthenticatedRequest extends Request {
  user?: JwtPayload;
}

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ success: false, error: 'Token requis' });
    return;
  }
  try {
    const payload = AuthService.verifyToken(header.slice(7));
    const user = AuthService.getUser(payload.userId);
    if (!user) {
      res.status(401).json({ success: false, error: 'Compte introuvable' });
      return;
    }
    (req as AuthenticatedRequest).user = payload;
    next();
  } catch {
    res.status(401).json({ success: false, error: 'Token invalide ou expiré' });
  }
}
