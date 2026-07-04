import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { TournamentService } from '../services/TournamentService';

function makeParticipants(count: number) {
  return Array.from({ length: count }, (_, i) => ({
    botId: `bot_${i}`,
    botName: `Bot ${i}`,
    mmr: 1500 + (count - i) * 50,
    skillLevel: 'intermediate',
  }));
}

describe('TournamentService', () => {
  let service: TournamentService;
  let dataDir: string;
  let originalLog: typeof console.log;

  before(() => {
    originalLog = console.log;
    console.log = () => {};
    dataDir = mkdtempSync(path.join(tmpdir(), 'dutch-tournament-test-'));
    service = new TournamentService(dataDir);
  });

  after(() => {
    console.log = originalLog;
    rmSync(dataDir, { recursive: true, force: true });
  });

  describe('constructor and basic getters', () => {
    it('constructs without error', () => {
      assert.ok(service);
    });

    it('getStats returns stats object with correct structure', async () => {
      const stats = await service.getStats();
      assert.strictEqual(typeof stats.totalTournaments, 'number');
      assert.strictEqual(typeof stats.activeTournaments, 'number');
      assert.strictEqual(typeof stats.completedTournaments, 'number');
      assert.strictEqual(typeof stats.totalMatches, 'number');
      assert.strictEqual(typeof stats.avgParticipants, 'number');
    });

    it('getStats returns 0 avgParticipants when no tournaments exist', async () => {
      const freshService = new TournamentService();
      const stats = await freshService.getStats();
      assert.strictEqual(stats.avgParticipants, 0);
    });

    it('getTournament returns undefined for unknown id', () => {
      const result = service.getTournament('nonexistent');
      assert.strictEqual(result, undefined);
    });

    it('listTournaments returns an array', async () => {
      const list = await service.listTournaments();
      assert.ok(Array.isArray(list));
    });
  });

  describe('createTournament', () => {
    it('creates a tournament with 4 participants', async () => {
      const participants = makeParticipants(4);
      const tournament = await service.createTournament('Test 4', 'daily', participants);

      assert.ok(tournament.tournamentId.includes('daily'));
      assert.strictEqual(tournament.name, 'Test 4');
      assert.strictEqual(tournament.type, 'daily');
      assert.strictEqual(tournament.status, 'pending');
      assert.strictEqual(tournament.participants.length, 4);
      assert.ok(tournament.bracket.length > 0);
      assert.ok(tournament.startTime);
      assert.strictEqual(typeof tournament.prizes.first, 'number');
      assert.strictEqual(typeof tournament.prizes.second, 'number');
      assert.strictEqual(typeof tournament.prizes.third, 'number');
    });

    it('creates a tournament with 8 participants', async () => {
      const participants = makeParticipants(8);
      const tournament = await service.createTournament('Test 8', 'weekly', participants);

      assert.strictEqual(tournament.participants.length, 8);
      // 8 participants = 3 rounds (log2(8))
      assert.strictEqual(tournament.bracket.length, 3);
    });

    it('creates a tournament with 16 participants', async () => {
      const participants = makeParticipants(16);
      const tournament = await service.createTournament('Test 16', 'special', participants);

      assert.strictEqual(tournament.participants.length, 16);
      assert.strictEqual(tournament.bracket.length, 4); // log2(16) = 4
    });

    it('throws for non-power-of-2 participants', async () => {
      const participants = makeParticipants(3);
      await assert.rejects(
        () => service.createTournament('Bad', 'daily', participants),
        { message: 'Le nombre de participants doit être une puissance de 2 (4, 8, 16, 32, etc.)' }
      );
    });

    it('throws for 5 participants', async () => {
      const participants = makeParticipants(5);
      await assert.rejects(
        () => service.createTournament('Bad5', 'daily', participants),
        /puissance de 2/
      );
    });

    it('throws for 0 participants', async () => {
      await assert.rejects(
        () => service.createTournament('Empty', 'daily', []),
        /puissance de 2/
      );
    });

    it('sorts participants by MMR (descending) for seeding', async () => {
      const participants = [
        { botId: 'low', botName: 'Low', mmr: 1000, skillLevel: 'beginner' },
        { botId: 'high', botName: 'High', mmr: 2000, skillLevel: 'expert' },
        { botId: 'mid1', botName: 'Mid1', mmr: 1500, skillLevel: 'intermediate' },
        { botId: 'mid2', botName: 'Mid2', mmr: 1200, skillLevel: 'intermediate' },
      ];
      const tournament = await service.createTournament('Seeded', 'daily', participants);
      assert.strictEqual(tournament.participants[0].botId, 'high');
      assert.strictEqual(tournament.participants[1].botId, 'mid1');
      assert.strictEqual(tournament.participants[2].botId, 'mid2');
      assert.strictEqual(tournament.participants[3].botId, 'low');
    });

    it('calculates prizes based on participant count', async () => {
      const participants = makeParticipants(8);
      const tournament = await service.createTournament('Prizes', 'daily', participants);
      // baseMMR=50, count=8 => first=50*8/4=100, second=50*8/8=50, third=50*8/16=25
      assert.strictEqual(tournament.prizes.first, 100);
      assert.strictEqual(tournament.prizes.second, 50);
      assert.strictEqual(tournament.prizes.third, 25);
    });

    it('generates bracket with first round pairing top vs bottom', async () => {
      const participants = makeParticipants(4);
      const tournament = await service.createTournament('Bracket Test', 'daily', participants);
      const firstRound = tournament.bracket[0];
      // After sorting by MMR desc: [bot_0(highest), bot_1, bot_2, bot_3(lowest)]
      // Pairings: bot_0 vs bot_3, bot_1 vs bot_2
      assert.strictEqual(firstRound.length, 4);
      assert.strictEqual(firstRound[0], tournament.participants[0].botId);
      assert.strictEqual(firstRound[1], tournament.participants[3].botId);
      assert.strictEqual(firstRound[2], tournament.participants[1].botId);
      assert.strictEqual(firstRound[3], tournament.participants[2].botId);
    });

    it('stores tournament and retrieves it by id', async () => {
      const participants = makeParticipants(4);
      const tournament = await service.createTournament('Stored', 'daily', participants);
      const retrieved = service.getTournament(tournament.tournamentId);
      assert.ok(retrieved);
      assert.strictEqual(retrieved.name, 'Stored');
    });
  });

  describe('runTournament', () => {
    it('throws for unknown tournament id', async () => {
      await assert.rejects(
        () => service.runTournament('fake_id'),
        { message: 'Tournoi introuvable' }
      );
    });

    it('runs a 4-participant tournament to completion', async () => {
      const participants = makeParticipants(4);
      const tournament = await service.createTournament('Run4', 'daily', participants);

      const completed = await service.runTournament(tournament.tournamentId);
      assert.strictEqual(completed.status, 'completed');
      assert.ok(completed.endTime);
      assert.ok(completed.winner);
      assert.ok(completed.winner.botId);
      assert.ok(completed.matches.length >= 2); // at least 2 matches in 4-participant bracket (2 semis + 1 final = 3 matches total, but bracket is 2 rounds so 2+1)
    });

    it('runs an 8-participant tournament to completion', async () => {
      const participants = makeParticipants(8);
      const tournament = await service.createTournament('Run8', 'weekly', participants);

      const completed = await service.runTournament(tournament.tournamentId);
      assert.strictEqual(completed.status, 'completed');
      assert.ok(completed.winner);
      // 8 participants: 4 matches round1 + 2 round2 + 1 final = 7 matches
      assert.strictEqual(completed.matches.length, 7);
    });

    it('all matches have winner and score', async () => {
      const participants = makeParticipants(4);
      const tournament = await service.createTournament('MatchCheck', 'daily', participants);
      const completed = await service.runTournament(tournament.tournamentId);

      for (const match of completed.matches) {
        assert.ok(match.matchId);
        assert.strictEqual(typeof match.round, 'number');
        assert.ok(match.participant1);
        assert.ok(match.participant2);
        assert.ok(match.winner);
        assert.ok(match.score);
        assert.strictEqual(typeof match.score.player1, 'number');
        assert.strictEqual(typeof match.score.player2, 'number');
        assert.ok(match.timestamp);
      }
    });

    it('winner is one of the participants', async () => {
      const participants = makeParticipants(4);
      const tournament = await service.createTournament('WinnerCheck', 'daily', participants);
      const completed = await service.runTournament(tournament.tournamentId);

      const participantIds = participants.map(p => p.botId);
      assert.ok(participantIds.includes(completed.winner!.botId));
    });

    it('advances winners through bracket rounds', async () => {
      const participants = makeParticipants(8);
      const tournament = await service.createTournament('BracketAdvance', 'daily', participants);
      const completed = await service.runTournament(tournament.tournamentId);

      // Second round should have 4 entries (winners of first round)
      assert.strictEqual(completed.bracket[1].length, 4);
      // Third round (final) should have 2 entries
      assert.strictEqual(completed.bracket[2].length, 2);
    });
  });

  describe('listTournaments with filter', () => {
    it('filters by pending status', async () => {
      const participants = makeParticipants(4);
      await service.createTournament('Pending1', 'daily', participants);
      const pending = await service.listTournaments('pending');
      assert.ok(pending.length > 0);
      for (const t of pending) {
        assert.strictEqual(t.status, 'pending');
      }
    });

    it('filters by completed status', async () => {
      const participants = makeParticipants(4);
      const tournament = await service.createTournament('ToComplete', 'daily', participants);
      await service.runTournament(tournament.tournamentId);

      const completed = await service.listTournaments('completed');
      assert.ok(completed.length > 0);
      for (const t of completed) {
        assert.strictEqual(t.status, 'completed');
      }
    });

    it('filters by in_progress status', async () => {
      const inProgress = await service.listTournaments('in_progress');
      // All our tournaments finish immediately so there should be none in progress
      for (const t of inProgress) {
        assert.strictEqual(t.status, 'in_progress');
      }
    });

    it('returns all tournaments without filter', async () => {
      const all = await service.listTournaments();
      assert.ok(all.length > 0);
    });
  });

  describe('getStats after tournaments', () => {
    it('reflects created and completed tournaments', async () => {
      const stats = await service.getStats();
      assert.ok(stats.totalTournaments > 0);
      assert.ok(stats.completedTournaments > 0);
      assert.ok(stats.totalMatches > 0);
      assert.ok(stats.avgParticipants > 0);
    });
  });

  describe('loadTournaments', () => {
    it('loads tournaments from disk without error', async () => {
      // Just verify it doesn't throw
      await service.loadTournaments();
      const list = await service.listTournaments();
      assert.ok(Array.isArray(list));
    });
  });
});
