import { Router } from 'express';
import { firestoreService } from '../services/FirestoreService';
import {
    ADMIN_SESSION_COOKIE_NAME,
    ADMIN_SESSION_MAX_AGE_MS,
    requireAdmin,
    adminLimiter,
    isAdmin,
} from '../middleware/adminAuthMiddleware';
import { auth } from '../services/FirebaseAdmin';

const router = Router();

// ---------------------------------------------------------------------------
// GET /api/admin/verify — Vérifie si le token Firebase est admin (pas de requireAdmin)
// Utilisé par le login gate JS pour vérifier l'accès avant d'afficher le dashboard
// ---------------------------------------------------------------------------
router.get('/verify', adminLimiter, async (req, res) => {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ') || !auth) {
        res.status(401).json({ success: false, error: 'Token requis' });
        return;
    }
    try {
        const decoded = await auth.verifyIdToken(authHeader.slice(7));
        const admin = await isAdmin(decoded.uid);
        if (!admin) {
            res.status(403).json({ success: false, error: 'Compte non administrateur' });
            return;
        }
        res.json({ success: true, uid: decoded.uid, email: decoded.email });
    } catch {
        res.status(401).json({ success: false, error: 'Token invalide' });
    }
});

// ---------------------------------------------------------------------------
// POST /api/admin/session — Crée une session admin httpOnly pour protéger les pages HTML
// ---------------------------------------------------------------------------
router.post('/session', adminLimiter, async (req, res) => {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ') || !auth) {
        res.status(401).json({ success: false, error: 'Token requis' });
        return;
    }

    try {
        const idToken = authHeader.slice(7);
        const decoded = await auth.verifyIdToken(idToken);
        const admin = await isAdmin(decoded.uid);
        if (!admin) {
            res.status(403).json({ success: false, error: 'Compte non administrateur' });
            return;
        }

        const sessionCookie = await auth.createSessionCookie(idToken, {
            expiresIn: ADMIN_SESSION_MAX_AGE_MS,
        });

        res.cookie(ADMIN_SESSION_COOKIE_NAME, sessionCookie, {
            httpOnly: true,
            secure: true,
            sameSite: 'lax',
            maxAge: ADMIN_SESSION_MAX_AGE_MS,
            path: '/',
        });
        res.set('Cache-Control', 'no-store');
        res.json({ success: true });
    } catch {
        res.status(401).json({ success: false, error: 'Token invalide' });
    }
});

// ---------------------------------------------------------------------------
// DELETE /api/admin/session — Supprime la session admin du navigateur
// ---------------------------------------------------------------------------
router.delete('/session', adminLimiter, async (_req, res) => {
    res.clearCookie(ADMIN_SESSION_COOKIE_NAME, {
        httpOnly: true,
        secure: true,
        sameSite: 'lax',
        path: '/',
    });
    res.set('Cache-Control', 'no-store');
    res.json({ success: true });
});

// --- Toutes les routes suivantes nécessitent l'authentification admin ---
router.use(adminLimiter);
router.use(requireAdmin);

// ---------------------------------------------------------------------------
// GET /api/admin/stats — Stats globales
// ---------------------------------------------------------------------------
router.get('/stats', async (_req, res) => {
    try {
        const { users, total } = await firestoreService.getAllUsers();
        const bannedCount = users.filter(u => u.isBanned).length;

        res.json({
            success: true,
            stats: {
                totalUsers: total,
                bannedUsers: bannedCount,
                recentUsers: 0, // TODO: filtre par date si nécessaire
            },
        });
    } catch {
        res.status(500).json({ success: false, error: 'Erreur serveur' });
    }
});

// ---------------------------------------------------------------------------
// GET /api/admin/users — Liste des utilisateurs
// ---------------------------------------------------------------------------
router.get('/users', async (req, res) => {
    try {
        const { users } = await firestoreService.getAllUsers({
            search: req.query.search as string,
            limit: Number.parseInt(req.query.limit as string) || 50,
        });

        res.json({
            success: true,
            users: users.map(u => ({
                id: u.uid,
                username: u.username,
                email: u.email,
                displayName: u.displayName,
                createdAt: u.createdAt?.toDate?.()?.toISOString() || '',
                updatedAt: u.updatedAt?.toDate?.()?.toISOString() || '',
                lastLoginAt: u.lastLoginAt?.toDate?.()?.toISOString() || null,
                isBanned: u.isBanned,
            })),
        });
    } catch {
        res.status(500).json({ success: false, error: 'Erreur serveur' });
    }
});

// ---------------------------------------------------------------------------
// GET /api/admin/users/:id — Détails d'un user
// ---------------------------------------------------------------------------
router.get('/users/:id', async (req, res) => {
    const userId = req.params.id; // String (Firebase UID), plus de parseInt

    const user = await firestoreService.getUser(userId);

    if (!user) {
        res.status(404).json({ success: false, error: 'Utilisateur introuvable' });
        return;
    }

    const friends = await firestoreService.getFriends(userId);

    res.json({
        success: true,
        user: {
            id: userId,
            username: user.username,
            email: user.email,
            displayName: user.displayName,
            createdAt: user.createdAt?.toDate?.()?.toISOString() || '',
            updatedAt: user.updatedAt?.toDate?.()?.toISOString() || '',
            lastLoginAt: user.lastLoginAt?.toDate?.()?.toISOString() || null,
            isBanned: user.isBanned,
            friendCount: friends.length,
        },
    });
});

// ---------------------------------------------------------------------------
// POST /api/admin/users/:id/ban — Bannir un user
// ---------------------------------------------------------------------------
router.post('/users/:id/ban', async (req, res) => {
    const userId = req.params.id;

    try {
        await firestoreService.setUserBanned(userId, true);
        res.json({ success: true });
    } catch {
        res.status(404).json({ success: false, error: 'Utilisateur introuvable' });
    }
});

// ---------------------------------------------------------------------------
// POST /api/admin/users/:id/unban — Débannir un user
// ---------------------------------------------------------------------------
router.post('/users/:id/unban', async (req, res) => {
    const userId = req.params.id;

    try {
        await firestoreService.setUserBanned(userId, false);
        res.json({ success: true });
    } catch {
        res.status(404).json({ success: false, error: 'Utilisateur introuvable' });
    }
});

// ---------------------------------------------------------------------------
// DELETE /api/admin/users/:id — Supprimer un user et toutes ses données
// ---------------------------------------------------------------------------
router.delete('/users/:id', async (req, res) => {
    const userId = req.params.id;

    const user = await firestoreService.getUser(userId);
    if (!user) {
        res.status(404).json({ success: false, error: 'Utilisateur introuvable' });
        return;
    }

    try {
        await firestoreService.deleteUser(userId);
        res.json({ success: true });
    } catch {
        res.status(500).json({ success: false, error: 'Erreur suppression' });
    }
});

export default router;
