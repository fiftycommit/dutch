import { PlayingCard, cardMatches } from '../models/Card';

export class HistoryFormatter {
    static formatStartingPlayer(playerName: string): string {
        return `Tirage au sort : ${playerName} commence !`;
    }

    static formatInitialMemorization(): string {
        return 'Vous avez mémorisé vos cartes.';
    }

    static formatDrawCard(playerName: string): string {
        return `${playerName} pioche.`;
    }

    static formatDiscardDrawn(playerName: string, card: PlayingCard): string {
        const isDame = card.value === 'Q';
        const cardName = isDame ? 'Dame' : card.value;
        return `${playerName} ne garde pas la carte ${cardName} (pas intéressé)`;
    }

    static formatReplaceDrawn(playerName: string, oldCard: PlayingCard): string {
        const isDame = oldCard.value === 'Q';
        const cardName = isDame ? 'Dame' : oldCard.value;
        const possessif = isDame ? 'sa' : 'son';
        return `${playerName} remplace ${possessif} ${cardName} par la carte piochée`;
    }

    static formatTakeFromDiscard(playerName: string): string {
        return `${playerName} prend de la défausse.`;
    }

    static formatMatchSuccess(playerName: string, card: PlayingCard): string {
        const isDame = card.value === 'Q';
        const cardName = isDame ? 'Dame' : card.value;
        return `MATCH ! ${playerName} pose ${cardName} !`;
    }

    static formatMatchFail(playerName: string, attemptedCard: PlayingCard, targetCard: PlayingCard): string {
        const getCardName = (c: PlayingCard) => c.value === 'Q' ? 'Dame' : c.value;
        const attemptedName = getCardName(attemptedCard);
        const targetName = getCardName(targetCard);
        return `${playerName} rate son match (${attemptedName} ≠ ${targetName}) ! Pénalité !`;
    }

    static formatPenalty(playerName: string): string {
        return `${playerName} prend une carte de pénalité.`;
    }

    static formatDutchCall(playerName: string): string {
        return `${playerName} crie DUTCH !`;
    }

    static formatPowerSpy(playerName: string, targetName: string): string {
        return `${playerName} regarde une carte de ${targetName}.`;
    }

    static formatPowerSwap(p1Name: string, p1Index: number, p2Name: string, p2Index: number): string {
        return `Échange : ${p1Name} carte #${p1Index + 1} ↔ ${p2Name} carte #${p2Index + 1}.`;
    }

    static formatPowerJoker(playerName: string, targetName: string): string {
        return `JOKER ! ${playerName} mélange ${targetName} !`;
    }

    static formatPowerSkip(playerName: string): string {
        return `${playerName} ignore le pouvoir spécial.`;
    }

    static formatDeckRefill(cardCount: number): string {
        return `🔄 Pioche vide ! Défausse mélangée (${cardCount} cartes)`;
    }

    static formatEmptyDeckEnd(): string {
        return 'Plus de cartes disponibles - Fin de partie';
    }
}
