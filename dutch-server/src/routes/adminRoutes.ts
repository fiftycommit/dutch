import { Router, Request, Response, NextFunction } from 'express';
import { database } from '../services/Database';

const router = Router();

// ---------------------------------------------------------------------------
// Admin auth middleware – vérifie le header X-Admin-Secret contre ADMIN_SECRET
// ---------------------------------------------------------------------------
const ADMIN_SECRET = process.env.ADMIN_SECRET || 'dutch-admin-dev-secret';

function requireAdmin(req: Request, res: Response, next: NextFunction): void {
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
router.get('/stats', (_req, res) => {
    const totalUsers = (database.instance.prepare(
        'SELECT COUNT(*) as count FROM users'
    ).get() as { count: number }).count;

    const bannedUsers = (database.instance.prepare(
        'SELECT COUNT(*) as count FROM users WHERE is_banned = 1'
    ).get() as { count: number }).count;

    const recentUsers = (database.instance.prepare(
        "SELECT COUNT(*) as count FROM users WHERE created_at > datetime('now', '-7 days')"
    ).get() as { count: number }).count;

    res.json({
        success: true,
        stats: {
            totalUsers,
            bannedUsers,
            recentUsers,
        },
    });
});

// ---------------------------------------------------------------------------
// GET /api/admin/users — Liste paginée avec recherche
// ---------------------------------------------------------------------------
interface UserRow {
    id: number;
    username: string;
    email: string | null;
    display_name: string;
    created_at: string;
    updated_at: string;
    last_login_at: string | null;
    is_banned: number;
}

router.get('/users', (req, res) => {
    const search = (req.query.search as string || '').trim();
    const page = Math.max(1, parseInt(req.query.page as string) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string) || 50));
    const offset = (page - 1) * limit;

    let whereClause = '';
    const params: unknown[] = [];

    if (search) {
        whereClause = 'WHERE username LIKE ? OR display_name LIKE ? OR email LIKE ?';
        const pattern = `%${search}%`;
        params.push(pattern, pattern, pattern);
    }

    const totalRow = database.instance.prepare(
        `SELECT COUNT(*) as count FROM users ${whereClause}`
    ).get(...params) as { count: number };

    const users = database.instance.prepare(
        `SELECT id, username, email, display_name, created_at, updated_at, last_login_at, is_banned
     FROM users ${whereClause}
     ORDER BY created_at DESC
     LIMIT ? OFFSET ?`
    ).all(...params, limit, offset) as UserRow[];

    res.json({
        success: true,
        users: users.map(u => ({
            id: u.id,
            username: u.username,
            email: u.email,
            displayName: u.display_name,
            createdAt: u.created_at,
            updatedAt: u.updated_at,
            lastLoginAt: u.last_login_at,
            isBanned: u.is_banned === 1,
        })),
        pagination: {
            page,
            limit,
            total: totalRow.count,
            totalPages: Math.ceil(totalRow.count / limit),
        },
    });
});

// ---------------------------------------------------------------------------
// GET /api/admin/users/:id — Détails d'un user
// ---------------------------------------------------------------------------
router.get('/users/:id', (req, res) => {
    const userId = parseInt(req.params.id);
    if (isNaN(userId)) {
        res.status(400).json({ success: false, error: 'ID invalide' });
        return;
    }

    const user = database.instance.prepare(
        'SELECT id, username, email, display_name, created_at, updated_at, last_login_at, is_banned FROM users WHERE id = ?'
    ).get(userId) as UserRow | undefined;

    if (!user) {
        res.status(404).json({ success: false, error: 'Utilisateur introuvable' });
        return;
    }

    // Count friends
    const friendCount = (database.instance.prepare(
        'SELECT COUNT(*) as count FROM friends WHERE user_id = ?'
    ).get(userId) as { count: number }).count;

    res.json({
        success: true,
        user: {
            id: user.id,
            username: user.username,
            email: user.email,
            displayName: user.display_name,
            createdAt: user.created_at,
            updatedAt: user.updated_at,
            lastLoginAt: user.last_login_at,
            isBanned: user.is_banned === 1,
            friendCount,
        },
    });
});

// ---------------------------------------------------------------------------
// POST /api/admin/users/:id/ban — Bannir un user
// ---------------------------------------------------------------------------
router.post('/users/:id/ban', (req, res) => {
    const userId = parseInt(req.params.id);
    if (isNaN(userId)) {
        res.status(400).json({ success: false, error: 'ID invalide' });
        return;
    }

    const result = database.instance.prepare(
        "UPDATE users SET is_banned = 1, updated_at = datetime('now') WHERE id = ?"
    ).run(userId);

    if (result.changes === 0) {
        res.status(404).json({ success: false, error: 'Utilisateur introuvable' });
        return;
    }

    res.json({ success: true });
});

// ---------------------------------------------------------------------------
// POST /api/admin/users/:id/unban — Débannir un user
// ---------------------------------------------------------------------------
router.post('/users/:id/unban', (req, res) => {
    const userId = parseInt(req.params.id);
    if (isNaN(userId)) {
        res.status(400).json({ success: false, error: 'ID invalide' });
        return;
    }

    const result = database.instance.prepare(
        "UPDATE users SET is_banned = 0, updated_at = datetime('now') WHERE id = ?"
    ).run(userId);

    if (result.changes === 0) {
        res.status(404).json({ success: false, error: 'Utilisateur introuvable' });
        return;
    }

    res.json({ success: true });
});

// ---------------------------------------------------------------------------
// DELETE /api/admin/users/:id — Supprimer un user et toutes ses données
// ---------------------------------------------------------------------------
router.delete('/users/:id', (req, res) => {
    const userId = parseInt(req.params.id);
    if (isNaN(userId)) {
        res.status(400).json({ success: false, error: 'ID invalide' });
        return;
    }

    const user = database.instance.prepare(
        'SELECT id FROM users WHERE id = ?'
    ).get(userId);

    if (!user) {
        res.status(404).json({ success: false, error: 'Utilisateur introuvable' });
        return;
    }

    const deleteTransaction = database.instance.transaction(() => {
        database.instance.prepare('DELETE FROM friends WHERE user_id = ? OR friend_id = ?').run(userId, userId);
        database.instance.prepare('DELETE FROM friend_requests WHERE from_user_id = ? OR to_user_id = ?').run(userId, userId);
        database.instance.prepare('DELETE FROM blocked_users WHERE user_id = ? OR blocked_id = ?').run(userId, userId);
        database.instance.prepare('DELETE FROM device_tokens WHERE user_id = ?').run(userId);
        database.instance.prepare('DELETE FROM room_invites WHERE from_user_id = ? OR to_user_id = ?').run(userId, userId);
        database.instance.prepare('DELETE FROM user_rooms WHERE user_id = ?').run(userId);
        database.instance.prepare('DELETE FROM room_bans WHERE user_id = ?').run(userId);
        database.instance.prepare('DELETE FROM password_reset_tokens WHERE user_id = ?').run(userId);
        database.instance.prepare('DELETE FROM users WHERE id = ?').run(userId);
    });

    deleteTransaction();
    res.json({ success: true });
});

export default router;
