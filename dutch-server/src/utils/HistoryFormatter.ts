import { PlayingCard } from '../models/Card';

export class HistoryFormatter {
    static formatStartingPlayer(playerName: string): string {
        return `Tirage au sort : ${playerName} a commencé !`;
    }

    static formatInitialMemorization(): string {
        return 'Mémorisation initiale terminée.';
    }

    static formatDrawCard(playerName: string): string {
        return `${playerName} a pioché.`;
    }

    static formatDiscardDrawn(playerName: string, card: PlayingCard, hasPower: boolean = false): string {
        const isDame = card.value === 'Q';
        const cardName = isDame ? 'Dame' : card.value;
        if (hasPower) {
            return `${playerName} a défaussé la carte ${cardName}`;
        }
        return `${playerName} n'a pas gardé la carte ${cardName} (pas intéressé)`;
    }

    static formatReplaceDrawn(playerName: string, oldCard: PlayingCard): string {
        const isDame = oldCard.value === 'Q';
        const cardName = isDame ? 'Dame' : oldCard.value;
        const possessif = isDame ? 'sa' : 'son';
        return `${playerName} a remplacé ${possessif} ${cardName} par la carte piochée`;
    }

    static formatMatchSuccess(playerName: string, card: PlayingCard): string {
        const isDame = card.value === 'Q';
        const cardName = isDame ? 'Dame' : card.value;
        return `MATCH ! ${playerName} a posé ${cardName} !`;
    }

    static formatMatchFail(playerName: string, attemptedCard: PlayingCard, targetCard: PlayingCard): string {
        const getCardName = (c: PlayingCard) => c.value === 'Q' ? 'Dame' : c.value;
        const attemptedName = getCardName(attemptedCard);
        const targetName = getCardName(targetCard);
        return `${playerName} a raté son match (${attemptedName} ≠ ${targetName}) ! Pénalité !`;
    }

    static formatPenalty(playerName: string): string {
        return `${playerName} a pris une carte de pénalité.`;
    }

    static formatDutchCall(playerName: string): string {
        return `${playerName} a crié DUTCH !`;
    }

    static formatPowerSpy(playerName: string, targetName: string): string {
        return `${playerName} a regardé une carte de ${targetName}.`;
    }

    static formatPowerSwap(p1Name: string, p1Index: number, p2Name: string, p2Index: number): string {
        return `Échange : ${p1Name} carte #${p1Index + 1} ↔ ${p2Name} carte #${p2Index + 1}.`;
    }

    static formatPowerJoker(playerName: string, targetName: string): string {
        return `JOKER ! ${playerName} a mélangé la main de ${targetName} !`;
    }

    static formatPowerSkip(playerName: string): string {
        return `${playerName} a ignoré le pouvoir spécial.`;
    }

    static formatDeckRefill(cardCount: number): string {
        return `🔄 Pioche vide ! Défausse mélangée (${cardCount} cartes)`;
    }

    static formatEmptyDeckEnd(): string {
        return 'Plus de cartes disponibles - Fin de partie';
    }
}
