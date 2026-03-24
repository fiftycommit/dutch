import { Router, Request, Response, NextFunction } from 'express';
import { firestoreService } from '../services/FirestoreService';

const router = Router();

// ---------------------------------------------------------------------------
// Admin auth middleware – vérifie le header X-Admin-Secret contre ADMIN_SECRET
// ---------------------------------------------------------------------------
const ADMIN_SECRET = process.env.ADMIN_SECRET;
if (!ADMIN_SECRET) {
    console.warn('⚠️ ADMIN_SECRET non défini — panel admin désactivé');
}

function requireAdmin(req: Request, res: Response, next: NextFunction): void {
    if (!ADMIN_SECRET) {
        res.status(503).json({ success: false, error: 'Admin désactivé' });
        return;
    }
    const secret = req.headers['x-admin-secret'] as string | undefined;
    if (!secret || secret !== ADMIN_SECRET) {
        res.status(403).json({ success: false, error: 'Accès refusé' });
        return;
    }
    next();
}

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
