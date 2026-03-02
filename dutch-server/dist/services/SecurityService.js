"use strict";
var _a;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SecurityService = void 0;
const express_rate_limit_1 = require("express-rate-limit");
const rate_limiter_flexible_1 = require("rate-limiter-flexible");
class SecurityService {
    static getRateLimitKey(req) {
        // If proxy headers are present, use the first hop as client key.
        // This avoids collapsing all users into one bucket behind Nginx.
        const xff = req.headers['x-forwarded-for'];
        if (typeof xff === 'string' && xff.trim().length > 0) {
            return xff.split(',')[0].trim();
        }
        if (Array.isArray(xff) && xff.length > 0 && xff[0]) {
            return xff[0].split(',')[0].trim();
        }
        return req.ip || req.socket.remoteAddress || 'unknown';
    }
    static async checkConnectionLimit(ip) {
        try {
            await this.connectionLimiter.consume(ip);
        }
        catch (e) {
            throw new Error('Too many connection attempts');
        }
    }
    static async checkEventRateLimit(socketId) {
        try {
            await this.eventLimiter.consume(socketId);
            return true;
        }
        catch (e) {
            return false; // Rate limit exceeded
        }
    }
    static async checkMatchRateLimit(socketId) {
        try {
            await this.matchLimiter.consume(socketId);
            return true;
        }
        catch (e) {
            return false; // Rate limit exceeded - trop de tentatives de match
        }
    }
    static async checkJoinAttemptLimit(ip) {
        try {
            await this.joinAttemptLimiter.consume(ip);
            return true;
        }
        catch (e) {
            return false; // Rate limit exceeded - trop de tentatives de join
        }
    }
    /** Réinitialise tous les rate limiters (usage tests uniquement) */
    static resetForTesting() {
        this.eventLimiter = new rate_limiter_flexible_1.RateLimiterMemory({ points: 20, duration: 1 });
        this.matchLimiter = new rate_limiter_flexible_1.RateLimiterMemory({ points: 1, duration: 0.5 });
        this.connectionLimiter = new rate_limiter_flexible_1.RateLimiterMemory({ points: 30, duration: 60 });
        this.joinAttemptLimiter = new rate_limiter_flexible_1.RateLimiterMemory({ points: 5, duration: 60 });
    }
}
exports.SecurityService = SecurityService;
_a = SecurityService;
// 1. Rate Limiting pour les requêtes HTTP (Express)
// Limite: 500 requêtes par 15 minutes par IP (environ 33 req/min)
// Protection basique contre le brute-force HTTP
SecurityService.apiLimiter = (0, express_rate_limit_1.rateLimit)({
    windowMs: 15 * 60 * 1000,
    max: 500,
    standardHeaders: true,
    legacyHeaders: false,
    message: 'Trop de requêtes, veuillez réessayer plus tard.',
    keyGenerator: (req) => _a.getRateLimitKey(req),
});
// Rate limiting plus permissif pour les records de learning
// (les fins de parties + trainer peuvent générer des bursts légitimes).
SecurityService.botLearningLimiter = (0, express_rate_limit_1.rateLimit)({
    windowMs: 15 * 60 * 1000,
    max: 6000,
    standardHeaders: true,
    legacyHeaders: false,
    message: 'Trop de requêtes, veuillez réessayer plus tard.',
    keyGenerator: (req) => _a.getRateLimitKey(req),
});
// 2. Rate Limiting pour les connexions Socket.IO (Anti-Flood)
// Limite: 30 connexions par minute par IP (1 connexion toutes les 2 sec moyenne)
// Suffisant pour recharger la page, mais bloque les bots de connexion
SecurityService.connectionLimiter = new rate_limiter_flexible_1.RateLimiterMemory({
    points: 30,
    duration: 60,
});
// 3. Rate Limiting pour les événements de jeu (Anti-Spam)
// Limite: 20 actions par seconde par joueur (permet des bursts rapides mais bloque le spam soutenu)
SecurityService.eventLimiter = new rate_limiter_flexible_1.RateLimiterMemory({
    points: 20,
    duration: 1,
});
// 4. Rate Limiting spécifique pour les matchs de cartes (Anti-Spam Match)
// Limite: 1 match par 500ms par joueur (évite le spam de matchs qui vide la pioche)
SecurityService.matchLimiter = new rate_limiter_flexible_1.RateLimiterMemory({
    points: 1,
    duration: 0.5, // 500ms entre chaque tentative de match
});
// 5. Rate Limiting pour les tentatives de join (Anti-Brute-Force room codes)
// Limite: 5 tentatives par minute par IP
SecurityService.joinAttemptLimiter = new rate_limiter_flexible_1.RateLimiterMemory({
    points: 5,
    duration: 60,
});
