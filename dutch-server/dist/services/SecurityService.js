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
// Limite: 100 requêtes par 15 minutes par IP
SecurityService.apiLimiter = (0, express_rate_limit_1.rateLimit)({
    windowMs: 15 * 60 * 1000,
    max: 100,
    standardHeaders: true,
    legacyHeaders: false,
    message: 'Trop de requêtes, veuillez réessayer plus tard.'
});
// 2. Rate Limiting pour les connexions Socket.IO (Anti-Flood)
// Limite: 10 connexions par minute par IP
SecurityService.connectionLimiter = new rate_limiter_flexible_1.RateLimiterMemory({
    points: 10,
    duration: 60,
});
// 3. Rate Limiting pour les événements de jeu (Anti-Spam)
// Limite: 15 actions par seconde par joueur (permet des bursts rapides mais bloque le spam soutenu)
SecurityService.eventLimiter = new rate_limiter_flexible_1.RateLimiterMemory({
    points: 15,
    duration: 1,
});
