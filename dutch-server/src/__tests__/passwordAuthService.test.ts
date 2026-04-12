import { describe, it } from 'node:test';
import assert from 'node:assert';
import { PasswordAuthError, PasswordAuthService } from '../services/PasswordAuthService';

describe('PasswordAuthService', () => {
  it('crée un compte côté serveur puis émet un custom token', async () => {
    const calls: string[] = [];

    const service = new PasswordAuthService({
      apiKey: 'public-key',
      adminAuth: {
        async createUser(data) {
          calls.push(`createUser:${data.email}`);
          return { uid: 'uid-123' };
        },
        async deleteUser() {
          calls.push('deleteUser');
        },
        async createCustomToken(uid) {
          calls.push(`createCustomToken:${uid}`);
          return 'custom-token-123';
        },
      },
      firestore: {
        async isUsernameAvailable(username) {
          calls.push(`isUsernameAvailable:${username}`);
          return true;
        },
        async getUserByUsername() {
          return null;
        },
        async getUser() {
          return null;
        },
        async createUser(uid, data) {
          calls.push(`createFirestoreUser:${uid}:${data.username}`);
          return {
            username: data.username as string,
            displayName: data.displayName as string,
            email: data.email as string,
            isBanned: false,
            createdAt: {} as never,
            updatedAt: {} as never,
            lastLoginAt: {} as never,
            stats: {
              gamesPlayed: 0,
              gamesWon: 0,
              totalScore: 0,
            },
          };
        },
      },
    });

    const result = await service.registerWithPassword({
      username: 'Test.User',
      displayName: 'Max',
      email: 'Max@Example.com',
      password: 'secret123',
    });

    assert.deepStrictEqual(result, {
      customToken: 'custom-token-123',
      uid: 'uid-123',
      email: 'max@example.com',
      username: 'test.user',
      displayName: 'Max',
    });
    assert.deepStrictEqual(calls, [
      'isUsernameAvailable:test.user',
      'createUser:max@example.com',
      'createFirestoreUser:uid-123:test.user',
      'createCustomToken:uid-123',
    ]);
  });

  it('connecte un utilisateur via pseudo sans exposer son email au client', async () => {
    const requestedBodies: string[] = [];
    const requestedHeaders: Array<Record<string, string>> = [];

    const service = new PasswordAuthService({
      apiKey: 'public-key',
      adminAuth: {
        async createUser() {
          throw new Error('not used');
        },
        async deleteUser() {
          throw new Error('not used');
        },
        async createCustomToken(uid) {
          return `token-for-${uid}`;
        },
      },
      firestore: {
        async isUsernameAvailable() {
          return true;
        },
        async getUserByUsername(username) {
          assert.strictEqual(username, 'test1');
          return {
            uid: 'uid-999',
            data: {
              username: 'test1',
              displayName: 'Test 1',
              email: 'hidden@example.com',
              isBanned: false,
              createdAt: {} as never,
              updatedAt: {} as never,
              lastLoginAt: {} as never,
              stats: {
                gamesPlayed: 0,
                gamesWon: 0,
                totalScore: 0,
              },
            },
          };
        },
        async getUser(uid) {
          assert.strictEqual(uid, 'uid-999');
          return {
            username: 'test1',
            displayName: 'Test 1',
            email: 'hidden@example.com',
            isBanned: false,
            createdAt: {} as never,
            updatedAt: {} as never,
            lastLoginAt: {} as never,
            stats: {
              gamesPlayed: 0,
              gamesWon: 0,
              totalScore: 0,
            },
          };
        },
        async createUser() {
          throw new Error('not used');
        },
      },
      fetchImpl: async (_input, init) => {
        requestedBodies.push(String(init?.body ?? ''));
        requestedHeaders.push(init?.headers as Record<string, string>);
        return {
          ok: true,
          async json() {
            return {
              localId: 'uid-999',
              email: 'hidden@example.com',
            };
          },
        } as Response;
      },
    });

    const result = await service.loginWithPassword({
      identifier: 'Test1',
      password: 'secret123',
      appCheckToken: 'app-check-token-123',
    });

    assert.deepStrictEqual(result, {
      customToken: 'token-for-uid-999',
      uid: 'uid-999',
      email: 'hidden@example.com',
    });
    assert.match(requestedBodies[0], /"email":"hidden@example\.com"/);
    assert.doesNotMatch(requestedBodies[0], /"identifier":"Test1"/);
    assert.strictEqual(
      requestedHeaders[0]['X-Firebase-AppCheck'],
      'app-check-token-123',
    );
  });

  it('rejette un pseudo inexistant avec une erreur générique', async () => {
    const service = new PasswordAuthService({
      apiKey: 'public-key',
      adminAuth: {
        async createUser() {
          throw new Error('not used');
        },
        async deleteUser() {
          throw new Error('not used');
        },
        async createCustomToken() {
          throw new Error('not used');
        },
      },
      firestore: {
        async isUsernameAvailable() {
          return true;
        },
        async getUserByUsername() {
          return null;
        },
        async getUser() {
          return null;
        },
        async createUser() {
          throw new Error('not used');
        },
      },
    });

    await assert.rejects(
      () =>
        service.loginWithPassword({
          identifier: 'ghost_user',
          password: 'secret123',
        }),
      (error: unknown) => {
        assert.ok(error instanceof PasswordAuthError);
        assert.strictEqual(error.code, 'invalid-credentials');
        assert.strictEqual(error.statusCode, 401);
        return true;
      },
    );
  });
});
