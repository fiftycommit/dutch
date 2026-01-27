"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createCard = createCard;
exports.createFullDeck = createFullDeck;
exports.cardMatches = cardMatches;
function createCard(suit, value) {
    const points = calculatePoints(suit, value);
    const isSpecial = isSpecialCard(value);
    const id = `${value}_${suit}`;
    return {
        suit,
        value,
        points,
        isSpecial,
        id,
    };
}
function calculatePoints(suit, value) {
    // Roi rouge = 0
    if (value === 'R' && (suit === 'hearts' || suit === 'diamonds'))
        return 0;
    // Joker = 0
    if (value === 'JOKER')
        return 0;
    // Roi noir = 13
    if (value === 'R' && (suit === 'clubs' || suit === 'spades'))
        return 13;
    // Dame = 12
    if (value === 'D')
        return 12;
    // Valet = 11
    if (value === 'V')
        return 11;
    // As = 1
    if (value === 'A')
        return 1;
    // Cartes numériques
    const numValue = parseInt(value, 10);
    return isNaN(numValue) ? 0 : numValue;
}
function isSpecialCard(value) {
    return ['7', '10', 'V', 'JOKER'].includes(value);
}
function createFullDeck() {
    const deck = [];
    const suits = ['hearts', 'diamonds', 'clubs', 'spades'];
    const values = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'V', 'D', 'R'];
    for (const suit of suits) {
        for (const value of values) {
            deck.push(createCard(suit, value));
        }
    }
    // Ajouter 2 jokers
    deck.push(createCard('joker', 'JOKER'));
    deck.push(createCard('joker', 'JOKER'));
    return deck;
}
function cardMatches(card1, card2) {
    const getMatchValue = (card) => {
        if (card.value === 'R')
            return 'R';
        if (card.value === 'JOKER')
            return 'JOKER';
        return card.value;
    };
    return getMatchValue(card1) === getMatchValue(card2);
}
