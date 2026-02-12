import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { database } from './Database';
import { User, PublicUser } from '../models/User';
import { ValidationService } from './ValidationService';
import { EmailService } from './EmailService';

const JWT_SECRET = process.env.JWT_SECRET || 'dutch-game-dev-secret-change-in-production';
const JWT_EXPIRES_IN = '30d';
const BCRYPT_ROUNDS = 10;

export interface AuthResult {
  success: boolean;
  user?: PublicUser;
  token?: string;
  error?: string;
}

export interface JwtPayload {
  userId: number;
  username: string;
}

export class AuthService {
  static register(
    username: string,
    displayName: string,
    email: string,
    password: string
  ): AuthResult {
    if (!ValidationService.isValidUsername(username)) {
      return { success: false, error: 'Nom d\'utilisateur invalide (3-20 caractères, lettres/chiffres/._-)' };
    }
    if (!ValidationService.isValidDisplayName(displayName)) {
      return { success: false, error: 'Pseudo invalide (1-24 caractères)' };
    }
    if (!ValidationService.isValidEmail(email)) {
      return { success: false, error: 'Email invalide' };
    }
    if (!ValidationService.isValidPassword(password)) {
      return { success: false, error: 'Mot de passe invalide (6-100 caractères)' };
    }

    const normalizedEmail = email.trim().toLowerCase();

    const existing = database.instance.prepare(
      'SELECT id FROM users WHERE username = ?'
    ).get(username.toLowerCase()) as User | undefined;

    if (existing) {
      return { success: false, error: 'Ce nom d\'utilisateur est déjà pris' };
    }

    const existingEmail = database.instance.prepare(
      'SELECT id FROM users WHERE email = ? COLLATE NOCASE'
    ).get(normalizedEmail) as { id: number } | undefined;

    if (existingEmail) {
      return { success: false, error: 'Cet email est déjà utilisé' };
    }

    const passwordHash = bcrypt.hashSync(password, BCRYPT_ROUNDS);
    const result = database.instance.prepare(
      'INSERT INTO users (username, email, display_name, password_hash) VALUES (?, ?, ?, ?)'
    ).run(username.toLowerCase(), normalizedEmail, displayName.trim(), passwordHash);

    const userId = result.lastInsertRowid as number;
    const token = this.generateToken(userId, username.toLowerCase());

    return {
      success: true,
      user: { id: userId, username: username.toLowerCase(), displayName: displayName.trim() },
      token,
    };
  }

  static login(username: string, password: string): AuthResult {
    if (!username || !password) {
      return { success: false, error: 'Identifiants requis' };
    }

    const user = database.instance.prepare(
      'SELECT * FROM users WHERE username = ?'
    ).get(username.toLowerCase()) as User | undefined;

    if (!user) {
      return { success: false, error: 'Identifiants incorrects' };
    }

    if (user.is_banned) {
      return { success: false, error: 'Compte suspendu' };
    }

    if (!bcrypt.compareSync(password, user.password_hash)) {
      return { success: false, error: 'Identifiants incorrects' };
    }

    database.instance.prepare(
      'UPDATE users SET last_login_at = datetime(\'now\') WHERE id = ?'
    ).run(user.id);

    const token = this.generateToken(user.id, user.username);

    return {
      success: true,
      user: { id: user.id, username: user.username, displayName: user.display_name },
      token,
    };
  }

  static verifyToken(token: string): JwtPayload {
    return jwt.verify(token, JWT_SECRET) as JwtPayload;
  }

  static getUser(userId: number): PublicUser | null {
    const user = database.instance.prepare(
      'SELECT id, username, display_name FROM users WHERE id = ?'
    ).get(userId) as { id: number; username: string; display_name: string } | undefined;

    if (!user) return null;
    return { id: user.id, username: user.username, displayName: user.display_name };
  }

  static isUsernameAvailable(username: string, exceptUserId?: number): boolean {
    if (!ValidationService.isValidUsername(username)) return false;

    const query = exceptUserId
      ? 'SELECT id FROM users WHERE username = ? AND id != ?'
      : 'SELECT id FROM users WHERE username = ?';
    const params = exceptUserId
      ? [username.toLowerCase(), exceptUserId]
      : [username.toLowerCase()];

    const existing = database.instance.prepare(query).get(...params);
    return !existing;
  }

  static updateProfile(userId: number, displayName: string): AuthResult {
    if (!ValidationService.isValidDisplayName(displayName)) {
      return { success: false, error: 'Pseudo invalide (1-24 caractères)' };
    }

    database.instance.prepare(
      'UPDATE users SET display_name = ?, updated_at = datetime(\'now\') WHERE id = ?'
    ).run(displayName.trim(), userId);

    const user = this.getUser(userId);
    if (!user) return { success: false, error: 'Utilisateur introuvable' };

    return { success: true, user };
  }

  static changePassword(
    userId: number,
    currentPassword: string,
    newPassword: string
  ): AuthResult {
    if (!currentPassword || currentPassword.trim().length === 0) {
      return { success: false, error: 'Mot de passe actuel requis' };
    }
    if (!ValidationService.isValidPassword(newPassword)) {
      return {
        success: false,
        error: 'Nouveau mot de passe invalide (6-100 caractères)',
      };
    }

    const user = database.instance.prepare(
      'SELECT id, password_hash FROM users WHERE id = ?'
    ).get(userId) as { id: number; password_hash: string } | undefined;

    if (!user) {
      return { success: false, error: 'Utilisateur introuvable' };
    }

    if (!bcrypt.compareSync(currentPassword, user.password_hash)) {
      return { success: false, error: 'Mot de passe actuel incorrect' };
    }

    if (bcrypt.compareSync(newPassword, user.password_hash)) {
      return {
        success: false,
        error: 'Le nouveau mot de passe doit être différent de l ancien',
      };
    }

    const newPasswordHash = bcrypt.hashSync(newPassword, BCRYPT_ROUNDS);
    database.instance
      .prepare(
        'UPDATE users SET password_hash = ?, updated_at = datetime(\'now\') WHERE id = ?'
      )
      .run(newPasswordHash, userId);

    database.instance
      .prepare('DELETE FROM password_reset_tokens WHERE user_id = ?')
      .run(userId);

    return { success: true };
  }

  static async requestPasswordReset(email: string): Promise<AuthResult> {
    if (!ValidationService.isValidEmail(email)) {
      return { success: false, error: 'Email invalide' };
    }

    const normalizedEmail = email.trim().toLowerCase();
    const user = database.instance.prepare(
      'SELECT id, email FROM users WHERE email = ? COLLATE NOCASE'
    ).get(normalizedEmail) as { id: number; email: string } | undefined;

    // Réponse volontairement générique pour éviter l'énumération des comptes.
    if (!user) {
      return { success: true };
    }

    const rawToken = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');

    const createResetToken = database.instance.transaction(() => {
      database.instance.prepare(
        'DELETE FROM password_reset_tokens WHERE user_id = ?'
      ).run(user.id);

      database.instance.prepare(`
        INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
        VALUES (?, ?, datetime('now', '+1 hour'))
      `).run(user.id, tokenHash);
    });

    createResetToken();

    const emailResult = await EmailService.sendPasswordResetEmail(
      user.email,
      rawToken
    );

    if (!emailResult.success) {
      return { success: false, error: emailResult.error };
    }
    return { success: true };
  }

  static resetPasswordWithToken(token: string, newPassword: string): AuthResult {
    if (!token || token.trim().length === 0) {
      return { success: false, error: 'Token requis' };
    }
    if (!ValidationService.isValidPassword(newPassword)) {
      return {
        success: false,
        error: 'Nouveau mot de passe invalide (6-100 caractères)',
      };
    }

    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const tokenRow = database.instance
      .prepare(`
        SELECT id, user_id
        FROM password_reset_tokens
        WHERE token_hash = ?
          AND used_at IS NULL
          AND expires_at > datetime('now')
      `)
      .get(tokenHash) as { id: number; user_id: number } | undefined;

    if (!tokenRow) {
      return {
        success: false,
        error: 'Lien invalide ou expiré. Demande une nouvelle réinitialisation.',
      };
    }

    const newPasswordHash = bcrypt.hashSync(newPassword, BCRYPT_ROUNDS);

    const applyReset = database.instance.transaction(() => {
      database.instance
        .prepare(
          'UPDATE users SET password_hash = ?, updated_at = datetime(\'now\') WHERE id = ?'
        )
        .run(newPasswordHash, tokenRow.user_id);

      database.instance
        .prepare(
          'UPDATE password_reset_tokens SET used_at = datetime(\'now\') WHERE id = ?'
        )
        .run(tokenRow.id);

      database.instance
        .prepare(
          'DELETE FROM password_reset_tokens WHERE user_id = ? AND id != ?'
        )
        .run(tokenRow.user_id, tokenRow.id);
    });

    applyReset();
    return { success: true };
  }

  static deleteAccount(userId: number, password: string): AuthResult {
    if (!password || password.trim().length === 0) {
      return { success: false, error: 'Mot de passe requis' };
    }

    const user = database.instance.prepare(
      'SELECT id, password_hash FROM users WHERE id = ?'
    ).get(userId) as { id: number; password_hash: string } | undefined;

    if (!user) {
      return { success: false, error: 'Utilisateur introuvable' };
    }

    if (!bcrypt.compareSync(password, user.password_hash)) {
      return { success: false, error: 'Mot de passe incorrect' };
    }

    const deleteAccountTransaction = database.instance.transaction(() => {
      database.instance.prepare(
        'DELETE FROM friends WHERE user_id = ? OR friend_id = ?'
      ).run(userId, userId);

      database.instance.prepare(
        'DELETE FROM friend_requests WHERE from_user_id = ? OR to_user_id = ?'
      ).run(userId, userId);

      database.instance.prepare(
        'DELETE FROM blocked_users WHERE user_id = ? OR blocked_id = ?'
      ).run(userId, userId);

      database.instance.prepare(
        'DELETE FROM device_tokens WHERE user_id = ?'
      ).run(userId);

      database.instance.prepare(
        'DELETE FROM room_invites WHERE from_user_id = ? OR to_user_id = ?'
      ).run(userId, userId);

      database.instance.prepare(
        'DELETE FROM user_rooms WHERE user_id = ?'
      ).run(userId);

      database.instance.prepare(
        'DELETE FROM room_bans WHERE user_id = ?'
      ).run(userId);

      database.instance.prepare(
        'DELETE FROM password_reset_tokens WHERE user_id = ?'
      ).run(userId);

      database.instance.prepare(
        'DELETE FROM users WHERE id = ?'
      ).run(userId);
    });

    deleteAccountTransaction();
    return { success: true };
  }

  static registerDeviceToken(userId: number, token: string, platform: string): void {
    database.instance.prepare(`
      INSERT INTO device_tokens (user_id, token, platform)
      VALUES (?, ?, ?)
      ON CONFLICT(token) DO UPDATE SET
        user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = datetime('now')
    `).run(userId, token, platform);
  }

  static removeDeviceToken(token: string): void {
    database.instance.prepare('DELETE FROM device_tokens WHERE token = ?').run(token);
  }

  static getDeviceTokens(userId: number): string[] {
    const rows = database.instance.prepare(
      'SELECT token FROM device_tokens WHERE user_id = ?'
    ).all(userId) as { token: string }[];
    return rows.map(r => r.token);
  }

  private static generateToken(userId: number, username: string): string {
    return jwt.sign({ userId, username } as JwtPayload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
  }
}
