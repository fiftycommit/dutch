import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

interface AdminAuthState {
  passwordHash: string; // format: "salt:hash" (hex)
  mustChangePassword: boolean;
}

const AUTH_FILE = path.join(process.cwd(), 'data', 'admin-auth.json');

class AdminAuthService {
  private state: AdminAuthState | null = null;

  /** Hash a password with a random salt using scrypt */
  private hashPassword(password: string): string {
    const salt = randomBytes(16).toString('hex');
    const hash = scryptSync(password, salt, 64).toString('hex');
    return `${salt}:${hash}`;
  }

  /** Verify a password against a stored hash */
  private verifyPassword(password: string, stored: string): boolean {
    const [salt, hash] = stored.split(':');
    const hashBuffer = Buffer.from(hash, 'hex');
    const candidate = scryptSync(password, salt, 64);
    return timingSafeEqual(hashBuffer, candidate);
  }

  /** Load state from disk */
  private load(): AdminAuthState | null {
    try {
      if (fs.existsSync(AUTH_FILE)) {
        const raw = fs.readFileSync(AUTH_FILE, 'utf-8');
        this.state = JSON.parse(raw);
        return this.state;
      }
    } catch {
      console.warn('[AdminAuth] Failed to read auth file, using defaults');
    }
    return null;
  }

  /** Save state to disk */
  private save(): void {
    if (!this.state) return;
    const dir = path.dirname(AUTH_FILE);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(AUTH_FILE, JSON.stringify(this.state, null, 2), 'utf-8');
  }

  /** Get current state (load from disk if needed) */
  private getState(): AdminAuthState | null {
    if (!this.state) {
      this.load();
    }
    return this.state;
  }

  /**
   * Verify an admin password.
   * - If a custom password has been set (file exists), check against it.
   * - Otherwise, check against the ADMIN_SECRET env var (initial password).
   */
  verify(password: string): boolean {
    const state = this.getState();
    if (state) {
      return this.verifyPassword(password, state.passwordHash);
    }
    // Fallback: env var is the initial password (not yet changed)
    const envSecret = process.env.ADMIN_SECRET;
    return !!envSecret && password === envSecret;
  }

  /** Whether the admin must change password on next login */
  getMustChangePassword(): boolean {
    const state = this.getState();
    // If no file exists, password has never been changed
    if (!state) return true;
    return state.mustChangePassword;
  }

  /**
   * Change the admin password.
   * Returns true on success, throws on invalid current password.
   */
  changePassword(currentPassword: string, newPassword: string): void {
    if (!this.verify(currentPassword)) {
      throw new Error('Mot de passe actuel invalide');
    }
    if (newPassword.length < 8) {
      throw new Error('Le nouveau mot de passe doit faire au moins 8 caractères');
    }
    if (newPassword === currentPassword) {
      throw new Error('Le nouveau mot de passe doit être différent');
    }

    this.state = {
      passwordHash: this.hashPassword(newPassword),
      mustChangePassword: false,
    };
    this.save();
    console.log('[AdminAuth] Password changed successfully');
  }
}

export const adminAuthService = new AdminAuthService();
