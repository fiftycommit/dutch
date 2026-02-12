import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

let tempDirPath = '';
let testDbPath = '';
let AuthService: typeof import('../services/AuthService').AuthService;
let database: typeof import('../services/Database').database;

function resetAuthTables() {
  database.instance.exec(`
    DELETE FROM password_reset_tokens;
    DELETE FROM device_tokens;
    DELETE FROM room_invites;
    DELETE FROM room_bans;
    DELETE FROM user_rooms;
    DELETE FROM friend_requests;
    DELETE FROM blocked_users;
    DELETE FROM friends;
    DELETE FROM users;
  `);
}

before(async () => {
  tempDirPath = await fs.mkdtemp(path.join(os.tmpdir(), 'dutch-auth-register-'));
  testDbPath = path.join(tempDirPath, 'auth-test.db');
  process.env.DUTCH_DB_PATH = testDbPath;
  process.env.JWT_SECRET = 'dutch-test-secret';

  const databaseModule = await import('../services/Database');
  const authModule = await import('../services/AuthService');
  database = databaseModule.database;
  AuthService = authModule.AuthService;
});

beforeEach(() => {
  resetAuthTables();
});

after(async () => {
  if (database?.instance) {
    database.instance.close();
  }
  delete process.env.DUTCH_DB_PATH;
  await fs.rm(tempDirPath, { recursive: true, force: true });
});

test('register creates a user and normalizes email', () => {
  const result = AuthService.register(
    'new_user',
    'New User',
    'NEW.USER@Example.com',
    'password123'
  );

  assert.equal(result.success, true);
  assert.ok(result.user);
  assert.ok(result.token);
  assert.equal(result.user?.username, 'new_user');
  assert.equal(result.user?.displayName, 'New User');

  const row = database.instance
    .prepare('SELECT email, display_name FROM users WHERE id = ?')
    .get(result.user!.id) as
    | { email: string; display_name: string }
    | undefined;

  assert.ok(row);
  assert.equal(row?.email, 'new.user@example.com');
  assert.equal(row?.display_name, 'New User');
});

test('register rejects duplicate username', () => {
  const first = AuthService.register(
    'taken_user',
    'Taken User',
    'first@example.com',
    'password123'
  );
  assert.equal(first.success, true);

  const second = AuthService.register(
    'taken_user',
    'Another Name',
    'second@example.com',
    'password123'
  );

  assert.equal(second.success, false);
  assert.match(second.error ?? '', /deja|déjà/i);
});

test('register rejects duplicate email (case insensitive)', () => {
  const first = AuthService.register(
    'first_user',
    'First User',
    'same@example.com',
    'password123'
  );
  assert.equal(first.success, true);

  const second = AuthService.register(
    'second_user',
    'Second User',
    'SAME@EXAMPLE.COM',
    'password123'
  );

  assert.equal(second.success, false);
  assert.match(second.error ?? '', /email/i);
  assert.match(second.error ?? '', /deja|déjà/i);
});

test('register rejects invalid email format', () => {
  const result = AuthService.register(
    'valid_user',
    'Valid User',
    'not-an-email',
    'password123'
  );

  assert.equal(result.success, false);
  assert.match(result.error ?? '', /email invalide/i);
});

test('register rejects short password', () => {
  const result = AuthService.register(
    'another_user',
    'Another User',
    'another@example.com',
    '12345'
  );

  assert.equal(result.success, false);
  assert.match(result.error ?? '', /mot de passe invalide/i);
});
