"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SecurityService = void 0;
const express_rate_limit_1 = require("express-rate-limit");
const rate_limiter_flexible_1 = require("rate-limiter-flexible");
class SecurityService {
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
}
exports.SecurityService = SecurityService;
// 1. Rate Limiting pour les requêtes HTTP (Express)
// Limite: 500 requêtes par 15 minutes par IP (environ 33 req/min)
// Protection basique contre le brute-force HTTP
SecurityService.apiLimiter = (0, express_rate_limit_1.rateLimit)({
    windowMs: 15 * 60 * 1000,
    max: 500,
    standardHeaders: true,
    legacyHeaders: false,
    message: 'Trop de requêtes, veuillez réessayer plus tard.'
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
