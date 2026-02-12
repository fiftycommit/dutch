import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';

class DatabaseService {
  private db: Database.Database;

  constructor() {
    const configuredDbPath = process.env.DUTCH_DB_PATH?.trim();
    const dbPath = configuredDbPath
      ? path.resolve(configuredDbPath)
      : path.join(__dirname, '../../data/dutch.db');
    const dataDir = path.dirname(dbPath);

    if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });
    this.db = new Database(dbPath);
    this.db.pragma('journal_mode = WAL');
    this.db.pragma('foreign_keys = ON');
    this.runMigrations();
  }

  private runMigrations() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        email TEXT,
        display_name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        last_login_at TEXT,
        is_banned INTEGER NOT NULL DEFAULT 0
      );

      CREATE TABLE IF NOT EXISTS friends (
        user_id INTEGER NOT NULL,
        friend_id INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (user_id, friend_id),
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (friend_id) REFERENCES users(id)
      );

      CREATE TABLE IF NOT EXISTS friend_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_user_id INTEGER NOT NULL,
        to_user_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(from_user_id, to_user_id),
        FOREIGN KEY (from_user_id) REFERENCES users(id),
        FOREIGN KEY (to_user_id) REFERENCES users(id)
      );

      CREATE TABLE IF NOT EXISTS blocked_users (
        user_id INTEGER NOT NULL,
        blocked_id INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (user_id, blocked_id),
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (blocked_id) REFERENCES users(id)
      );

      CREATE TABLE IF NOT EXISTS room_bans (
        room_code TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        banned_at TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (room_code, user_id)
      );

      CREATE TABLE IF NOT EXISTS device_tokens (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        token TEXT NOT NULL UNIQUE,
        platform TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (user_id) REFERENCES users(id)
      );

      CREATE TABLE IF NOT EXISTS room_invites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        room_code TEXT NOT NULL,
        from_user_id INTEGER NOT NULL,
        to_user_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (from_user_id) REFERENCES users(id),
        FOREIGN KEY (to_user_id) REFERENCES users(id)
      );

      CREATE TABLE IF NOT EXISTS user_rooms (
        user_id INTEGER NOT NULL,
        room_code TEXT NOT NULL,
        is_host INTEGER NOT NULL DEFAULT 0,
        joined_at TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (user_id, room_code),
        FOREIGN KEY (user_id) REFERENCES users(id)
      );

      CREATE TABLE IF NOT EXISTS password_reset_tokens (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        expires_at TEXT NOT NULL,
        used_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (user_id) REFERENCES users(id)
      );

      CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
      CREATE INDEX IF NOT EXISTS idx_friend_requests_to ON friend_requests(to_user_id, status);
      CREATE INDEX IF NOT EXISTS idx_friend_requests_from ON friend_requests(from_user_id, status);
      CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);
      CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_hash ON password_reset_tokens(token_hash);
      CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_user ON password_reset_tokens(user_id);
    `);

    this.ensureUsersEmailColumn();
    this.db.exec(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique
      ON users(email COLLATE NOCASE)
      WHERE email IS NOT NULL AND email != '';
    `);
  }

  private ensureUsersEmailColumn() {
    const columns = this.db.prepare('PRAGMA table_info(users)').all() as {
      name: string;
    }[];
    const hasEmailColumn = columns.some((column) => column.name === 'email');
    if (!hasEmailColumn) {
      this.db.exec('ALTER TABLE users ADD COLUMN email TEXT');
    }
  }

  get instance() { return this.db; }
}

export const database = new DatabaseService();
