import { promises as fs } from 'node:fs';
import path from 'node:path';

interface TournamentParticipant {
  botId: string;
  botName: string;
  mmr: number;
  skillLevel: string;
  personality?: string;
}

interface TournamentMatch {
  matchId: string;
  round: number;
  participant1: TournamentParticipant;
  participant2: TournamentParticipant;
  winner?: string;
  score?: { player1: number; player2: number };
  timestamp: string;
}

interface Tournament {
  tournamentId: string;
  name: string;
  type: 'daily' | 'weekly' | 'special';
  status: 'pending' | 'in_progress' | 'completed';
  participants: TournamentParticipant[];
  matches: TournamentMatch[];
  bracket: string[][];
  winner?: TournamentParticipant;
  startTime: string;
  endTime?: string;
  prizes: {
    first: number;
    second: number;
    third: number;
  };
}

export class TournamentService {
  private dataDir: string;
  private activeTournaments: Map<string, Tournament>;

  constructor(dataDir?: string) {
    this.dataDir = dataDir ?? path.join(__dirname, '../../data/bot-learning/tournaments');
    this.activeTournaments = new Map();
    this.ensureDataDirectory();
  }

  private ensureDataDirectory() {
    try {
      const fsSync = require('node:fs');
      if (!fsSync.existsSync(this.dataDir)) {
        fsSync.mkdirSync(this.dataDir, { recursive: true });
      }
    } catch (error) {
      console.error('❌ Erreur création répertoire tournaments:', error instanceof Error ? error.message : String(error));
    }
  }

  /**
   * Crée un nouveau tournoi
   */
  async createTournament(
    name: string,
    type: 'daily' | 'weekly' | 'special',
    participants: TournamentParticipant[]
  ): Promise<Tournament> {
    const tournamentId = `tournament_${type}_${Date.now()}`;

    // Vérifier que le nombre de participants est une puissance de 2
    const participantCount = participants.length;
    if (!this.isPowerOfTwo(participantCount)) {
      throw new Error('Le nombre de participants doit être une puissance de 2 (4, 8, 16, 32, etc.)');
    }

    // Trier par MMR pour un bracket équilibré
    const sortedParticipants = [...participants].sort((a, b) => b.mmr - a.mmr);

    const tournament: Tournament = {
      tournamentId,
      name,
      type,
      status: 'pending',
      participants: sortedParticipants,
      matches: [],
      bracket: this.generateBracket(sortedParticipants),
      startTime: new Date().toISOString(),
      prizes: this.calculatePrizes(participantCount),
    };

    this.activeTournaments.set(tournamentId, tournament);
    await this.saveTournament(tournament);

    console.log(`🏆 Tournoi créé: ${name} avec ${participantCount} participants`);
    return tournament;
  }

  /**
   * Génère le bracket du tournoi (Swiss system pour équilibrer)
   */
  private generateBracket(participants: TournamentParticipant[]): string[][] {
    const bracket: string[][] = [];
    const rounds = Math.log2(participants.length);

    // Premier tour : meilleur vs moins bon pour équilibrer
    const firstRound: string[] = [];
    for (let i = 0; i < participants.length / 2; i++) {
      firstRound.push(participants[i].botId, participants[participants.length - 1 - i].botId);
    }
    bracket.push(firstRound);

    // Rounds suivants (vides pour l'instant)
    for (let i = 1; i < rounds; i++) {
      bracket.push([]);
    }

    return bracket;
  }

  /**
   * Lance le tournoi et simule les matchs
   */
  async runTournament(tournamentId: string): Promise<Tournament> {
    const tournament = this.activeTournaments.get(tournamentId);
    if (!tournament) {
      throw new Error('Tournoi introuvable');
    }

    tournament.status = 'in_progress';
    console.log(`🎮 Démarrage du tournoi: ${tournament.name}`);

    // Simuler chaque round
    for (let round = 0; round < tournament.bracket.length; round++) {
      await this.playRound(tournament, round);
    }

    tournament.status = 'completed';
    tournament.endTime = new Date().toISOString();

    // Déterminer le gagnant
    const finalMatch = tournament.matches[tournament.matches.length - 1];
    tournament.winner = tournament.participants.find(p => p.botId === finalMatch.winner);

    await this.saveTournament(tournament);
    console.log(`🏆 Tournoi terminé! Gagnant: ${tournament.winner?.botName}`);

    return tournament;
  }

  /**
   * Joue un round complet
   */
  private async playRound(tournament: Tournament, roundIndex: number) {
    const roundParticipants = tournament.bracket[roundIndex];
    const matches: TournamentMatch[] = [];

    console.log(`📍 Round ${roundIndex + 1}/${tournament.bracket.length}`);

    // Créer les matchs du round
    for (let i = 0; i < roundParticipants.length; i += 2) {
      const p1Id = roundParticipants[i];
      const p2Id = roundParticipants[i + 1];

      const p1 = tournament.participants.find(p => p.botId === p1Id)!;
      const p2 = tournament.participants.find(p => p.botId === p2Id)!;

      const match = await this.simulateMatch(tournament, roundIndex, p1, p2);
      matches.push(match);
      tournament.matches.push(match);

      // Ajouter le gagnant au prochain round
      if (roundIndex < tournament.bracket.length - 1) {
        tournament.bracket[roundIndex + 1].push(match.winner!);
      }
    }

    console.log(`✅ Round ${roundIndex + 1} terminé: ${matches.length} matchs`);
  }

  /**
   * Simule un match entre deux bots
   */
  private async simulateMatch(
    tournament: Tournament,
    round: number,
    p1: TournamentParticipant,
    p2: TournamentParticipant
  ): Promise<TournamentMatch> {
    // Simulation basée sur MMR avec un facteur aléatoire
    const mmrDiff = p1.mmr - p2.mmr;
    const p1WinChance = 0.5 + (mmrDiff / 1000); // +/- 500 MMR = +/- 25% de chance
    const p1Wins = Math.random() < Math.max(0.1, Math.min(0.9, p1WinChance));

    const winner = p1Wins ? p1.botId : p2.botId;
    const score = {
      player1: p1Wins ? Math.floor(Math.random() * 10 + 5) : Math.floor(Math.random() * 20 + 10),
      player2: p1Wins ? Math.floor(Math.random() * 20 + 10) : Math.floor(Math.random() * 10 + 5),
    };

    const match: TournamentMatch = {
      matchId: `match_${tournament.tournamentId}_r${round}_${Date.now()}`,
      round,
      participant1: p1,
      participant2: p2,
      winner,
      score,
      timestamp: new Date().toISOString(),
    };

    console.log(`  ${p1.botName} vs ${p2.botName} → Gagnant: ${p1Wins ? p1.botName : p2.botName}`);

    return match;
  }

  /**
   * Calcule les prix selon le nombre de participants
   */
  private calculatePrizes(participantCount: number): { first: number; second: number; third: number } {
    const baseMMR = 50;
    return {
      first: baseMMR * participantCount / 4,
      second: baseMMR * participantCount / 8,
      third: baseMMR * participantCount / 16,
    };
  }

  /**
   * Vérifie si un nombre est une puissance de 2
   */
  private isPowerOfTwo(n: number): boolean {
    return n > 0 && (n & (n - 1)) === 0;
  }

  /**
   * Récupère un tournoi
   */
  getTournament(tournamentId: string): Tournament | undefined {
    return this.activeTournaments.get(tournamentId);
  }

  /**
   * Liste tous les tournois
   */
  async listTournaments(status?: 'pending' | 'in_progress' | 'completed'): Promise<Tournament[]> {
    const tournaments = Array.from(this.activeTournaments.values());
    if (status) {
      return tournaments.filter(t => t.status === status);
    }
    return tournaments;
  }

  /**
   * Récupère les statistiques des tournois
   */
  async getStats() {
    const tournaments = Array.from(this.activeTournaments.values());
    const completed = tournaments.filter(t => t.status === 'completed');

    return {
      totalTournaments: tournaments.length,
      activeTournaments: tournaments.filter(t => t.status === 'in_progress').length,
      completedTournaments: completed.length,
      totalMatches: tournaments.reduce((sum, t) => sum + t.matches.length, 0),
      avgParticipants: tournaments.length > 0
        ? tournaments.reduce((sum, t) => sum + t.participants.length, 0) / tournaments.length
        : 0,
    };
  }

  /**
   * Sauvegarde un tournoi
   */
  private async saveTournament(tournament: Tournament) {
    try {
      const filePath = path.join(this.dataDir, `${tournament.tournamentId}.json`);
      await fs.writeFile(filePath, JSON.stringify(tournament, null, 2));
    } catch (error) {
      console.error(`❌ Erreur sauvegarde tournoi ${tournament.tournamentId}:`, error instanceof Error ? error.message : String(error));
    }
  }

  /**
   * Charge tous les tournois depuis le disque
   */
  async loadTournaments() {
    try {
      const files = await fs.readdir(this.dataDir);
      const tournamentFiles = files.filter(f => f.endsWith('.json'));

      for (const file of tournamentFiles) {
        const filePath = path.join(this.dataDir, file);
        const data = await fs.readFile(filePath, 'utf-8');
        const tournament: Tournament = JSON.parse(data);
        this.activeTournaments.set(tournament.tournamentId, tournament);
      }

      console.log(`✅ ${this.activeTournaments.size} tournois chargés`);
    } catch {
      console.log('ℹ️ Aucun tournoi existant');
    }
  }
}
