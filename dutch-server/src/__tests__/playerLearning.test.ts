import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import { PlayerLearningService } from '../services/PlayerLearningService';

describe('PlayerLearningService', () => {
  let service: PlayerLearningService;
  const testClientId = 'test-client-' + Date.now();
  const testSlotId = 0;

  before(() => {
    service = new PlayerLearningService();
  });

  it('constructs without error', () => {
    assert.ok(service);
  });

  describe('getProfile', () => {
    it('returns null for non-existent player', async () => {
      const profile = await service.getProfile('nonexistent-client', 0);
      assert.strictEqual(profile, null);
    });

    it('returns null for non-existent slot', async () => {
      const profile = await service.getProfile(testClientId, 99);
      assert.strictEqual(profile, null);
    });
  });

  describe('getHistory', () => {
    it('returns empty array for non-existent player', async () => {
      const history = await service.getHistory('nonexistent-client', 0);
      assert.ok(Array.isArray(history));
      assert.strictEqual(history.length, 0);
    });

    it('returns empty array for non-existent slot', async () => {
      const history = await service.getHistory(testClientId, 99);
      assert.ok(Array.isArray(history));
      assert.strictEqual(history.length, 0);
    });
  });

  describe('upload', () => {
    it('uploads a profile and retrieves it', async () => {
      await service.upload({
        clientId: testClientId,
        slotId: testSlotId,
        profile: {
          profileId: 'profile-1',
          createdAt: '2024-01-01T00:00:00.000Z',
          lastUpdatedAt: '2024-01-02T00:00:00.000Z',
          gamesAnalyzed: 5,
          learnedParameters: { aggression: 0.6, caution: 0.4 },
        },
      });

      const profile = await service.getProfile(testClientId, testSlotId);
      assert.ok(profile);
      assert.strictEqual(profile.clientId, testClientId);
      assert.strictEqual(profile.slotId, testSlotId);
      assert.strictEqual(profile.profileId, 'profile-1');
      assert.strictEqual(profile.gamesAnalyzed, 5);
      assert.strictEqual(profile.learnedParameters.aggression, 0.6);
      assert.strictEqual(profile.learnedParameters.caution, 0.4);
      assert.strictEqual(profile.createdAt, '2024-01-01T00:00:00.000Z');
      assert.strictEqual(profile.lastUpdatedAt, '2024-01-02T00:00:00.000Z');
      assert.ok(profile.updatedAt); // server-side timestamp
    });

    it('uploads with history and retrieves it', async () => {
      const historyClientId = 'test-history-' + Date.now();
      const history = [
        {
          gameId: 'game-1',
          startTime: '2024-01-01T10:00:00.000Z',
          endTime: '2024-01-01T10:30:00.000Z',
          usedSBMM: true,
          numberOfPlayers: 4,
          finalRank: 1,
          finalScore: 15,
          calledDutch: true,
          wonDutch: true,
        },
        {
          gameId: 'game-2',
          startTime: '2024-01-02T10:00:00.000Z',
          endTime: '2024-01-02T10:25:00.000Z',
          usedSBMM: false,
          numberOfPlayers: 3,
          finalRank: 2,
          finalScore: 30,
          calledDutch: false,
          wonDutch: false,
        },
      ];

      await service.upload({
        clientId: historyClientId,
        slotId: 1,
        profile: {
          profileId: 'profile-hist',
          createdAt: '2024-01-01T00:00:00.000Z',
          lastUpdatedAt: '2024-01-02T00:00:00.000Z',
          gamesAnalyzed: 2,
          learnedParameters: {},
        },
        history,
      });

      const retrieved = await service.getHistory(historyClientId, 1);
      assert.ok(Array.isArray(retrieved));
      assert.strictEqual(retrieved.length, 2);
      assert.strictEqual(retrieved[0].gameId, 'game-1');
      assert.strictEqual(retrieved[0].calledDutch, true);
      assert.strictEqual(retrieved[0].wonDutch, true);
      assert.strictEqual(retrieved[1].gameId, 'game-2');
      assert.strictEqual(retrieved[1].finalRank, 2);
    });

    it('overwrites profile on re-upload', async () => {
      const overwriteClientId = 'test-overwrite-' + Date.now();

      await service.upload({
        clientId: overwriteClientId,
        slotId: 0,
        profile: {
          profileId: 'profile-v1',
          createdAt: '2024-01-01T00:00:00.000Z',
          lastUpdatedAt: '2024-01-01T00:00:00.000Z',
          gamesAnalyzed: 1,
          learnedParameters: { version: 1 },
        },
      });

      await service.upload({
        clientId: overwriteClientId,
        slotId: 0,
        profile: {
          profileId: 'profile-v2',
          createdAt: '2024-01-01T00:00:00.000Z',
          lastUpdatedAt: '2024-01-02T00:00:00.000Z',
          gamesAnalyzed: 5,
          learnedParameters: { version: 2 },
        },
      });

      const profile = await service.getProfile(overwriteClientId, 0);
      assert.ok(profile);
      assert.strictEqual(profile.profileId, 'profile-v2');
      assert.strictEqual(profile.gamesAnalyzed, 5);
      assert.strictEqual(profile.learnedParameters.version, 2);
    });

    it('upload without history does not create history file', async () => {
      const noHistClientId = 'test-nohist-' + Date.now();

      await service.upload({
        clientId: noHistClientId,
        slotId: 0,
        profile: {
          profileId: 'profile-nohist',
          createdAt: '2024-01-01T00:00:00.000Z',
          lastUpdatedAt: '2024-01-01T00:00:00.000Z',
          gamesAnalyzed: 0,
          learnedParameters: {},
        },
      });

      // Profile should exist
      const profile = await service.getProfile(noHistClientId, 0);
      assert.ok(profile);

      // History should return empty (no file created)
      const history = await service.getHistory(noHistClientId, 0);
      assert.ok(Array.isArray(history));
      assert.strictEqual(history.length, 0);
    });

    it('trims history to 25 entries', async () => {
      const trimClientId = 'test-trim-' + Date.now();
      const longHistory = Array.from({ length: 30 }, (_, i) => ({
        gameId: `game-${i}`,
        startTime: '2024-01-01T10:00:00.000Z',
        endTime: '2024-01-01T10:30:00.000Z',
        usedSBMM: false,
        numberOfPlayers: 2,
        finalRank: 1,
        finalScore: 10,
        calledDutch: false,
        wonDutch: false,
      }));

      await service.upload({
        clientId: trimClientId,
        slotId: 0,
        profile: {
          profileId: 'profile-trim',
          createdAt: '2024-01-01T00:00:00.000Z',
          lastUpdatedAt: '2024-01-01T00:00:00.000Z',
          gamesAnalyzed: 30,
          learnedParameters: {},
        },
        history: longHistory,
      });

      const history = await service.getHistory(trimClientId, 0);
      assert.ok(history.length <= 25, `Expected <= 25 history entries, got ${history.length}`);
    });

    it('handles different slot ids independently', async () => {
      const slotClientId = 'test-slots-' + Date.now();

      await service.upload({
        clientId: slotClientId,
        slotId: 0,
        profile: {
          profileId: 'slot-0-profile',
          createdAt: '2024-01-01T00:00:00.000Z',
          lastUpdatedAt: '2024-01-01T00:00:00.000Z',
          gamesAnalyzed: 1,
          learnedParameters: { slot: 0 },
        },
      });

      await service.upload({
        clientId: slotClientId,
        slotId: 1,
        profile: {
          profileId: 'slot-1-profile',
          createdAt: '2024-01-01T00:00:00.000Z',
          lastUpdatedAt: '2024-01-01T00:00:00.000Z',
          gamesAnalyzed: 2,
          learnedParameters: { slot: 1 },
        },
      });

      const profile0 = await service.getProfile(slotClientId, 0);
      const profile1 = await service.getProfile(slotClientId, 1);

      assert.ok(profile0);
      assert.ok(profile1);
      assert.strictEqual(profile0.profileId, 'slot-0-profile');
      assert.strictEqual(profile1.profileId, 'slot-1-profile');
      assert.strictEqual(profile0.learnedParameters.slot, 0);
      assert.strictEqual(profile1.learnedParameters.slot, 1);
    });

    it('upload with empty history array does not fail', async () => {
      const emptyHistClientId = 'test-emptyhist-' + Date.now();

      await service.upload({
        clientId: emptyHistClientId,
        slotId: 0,
        profile: {
          profileId: 'profile-emptyhist',
          createdAt: '2024-01-01T00:00:00.000Z',
          lastUpdatedAt: '2024-01-01T00:00:00.000Z',
          gamesAnalyzed: 0,
          learnedParameters: {},
        },
        history: [],
      });

      const history = await service.getHistory(emptyHistClientId, 0);
      assert.ok(Array.isArray(history));
      assert.strictEqual(history.length, 0);
    });

    it('upload with history containing optional profileBefore/profileAfter', async () => {
      const optionalClientId = 'test-optional-' + Date.now();

      await service.upload({
        clientId: optionalClientId,
        slotId: 0,
        profile: {
          profileId: 'profile-optional',
          createdAt: '2024-01-01T00:00:00.000Z',
          lastUpdatedAt: '2024-01-01T00:00:00.000Z',
          gamesAnalyzed: 1,
          learnedParameters: {},
        },
        history: [
          {
            gameId: 'game-opt',
            startTime: '2024-01-01T10:00:00.000Z',
            endTime: '2024-01-01T10:30:00.000Z',
            usedSBMM: true,
            numberOfPlayers: 2,
            finalRank: 1,
            finalScore: 10,
            calledDutch: false,
            wonDutch: false,
            profileBefore: { aggression: 0.3 },
            profileAfter: { aggression: 0.5 },
          },
        ],
      });

      const history = await service.getHistory(optionalClientId, 0);
      assert.strictEqual(history.length, 1);
      assert.deepStrictEqual(history[0].profileBefore, { aggression: 0.3 });
      assert.deepStrictEqual(history[0].profileAfter, { aggression: 0.5 });
    });
  });
});
