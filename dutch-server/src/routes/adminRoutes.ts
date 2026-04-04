import { Router } from 'express';
import { firestoreService } from '../services/FirestoreService';
import { requireAdmin, adminLimiter } from '../middleware/adminAuthMiddleware';
import { adminAuthService } from '../services/AdminAuthService';

const router = Router();

// ---------------------------------------------------------------------------
// POST /api/admin/login — Vérifier le mot de passe admin (rate-limited, pas de requireAdmin)
// ---------------------------------------------------------------------------
router.post('/login', adminLimiter, (req, res) => {
    const { password } = req.body;
    if (!password || !adminAuthService.verify(password)) {
        const ip = req.headers['x-forwarded-for'] || req.ip || req.socket.remoteAddress;
        console.warn(`[SECURITY] Admin login failed — IP: ${ip}, time: ${new Date().toISOString()}`);
        res.status(403).json({ success: false, error: 'Mot de passe invalide' });
        return;
    }
    res.json({
        success: true,
        mustChangePassword: adminAuthService.getMustChangePassword(),
    });
});

// ---------------------------------------------------------------------------
// POST /api/admin/change-password — Changer le mot de passe admin (rate-limited)
// ---------------------------------------------------------------------------
router.post('/change-password', adminLimiter, (req, res) => {
    const { currentPassword, newPassword } = req.body;
    if (!currentPassword || !newPassword) {
        res.status(400).json({ success: false, error: 'Champs requis: currentPassword, newPassword' });
        return;
    }
    try {
        adminAuthService.changePassword(currentPassword, newPassword);
        res.json({ success: true });
    } catch (error: any) {
        res.status(400).json({ success: false, error: error.message });
    }
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
