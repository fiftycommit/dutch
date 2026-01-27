import { rateLimit } from 'express-rate-limit';
import { RateLimiterMemory } from 'rate-limiter-flexible';
import { Socket } from 'socket.io';

export class SecurityService {
    // 1. Rate Limiting pour les requêtes HTTP (Express)
    // Limite: 100 requêtes par 15 minutes par IP
    static apiLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 100,
        standardHeaders: true,
        legacyHeaders: false,
        message: 'Trop de requêtes, veuillez réessayer plus tard.'
    });

    // 2. Rate Limiting pour les connexions Socket.IO (Anti-Flood)
    // Limite: 10 connexions par minute par IP
    private static connectionLimiter = new RateLimiterMemory({
        points: 10,
        duration: 60,
    });

    // 3. Rate Limiting pour les événements de jeu (Anti-Spam)
    // Limite: 15 actions par seconde par joueur (permet des bursts rapides mais bloque le spam soutenu)
    private static eventLimiter = new RateLimiterMemory({
        points: 15,
        duration: 1,
    });

    static async checkConnectionLimit(ip: string): Promise<void> {
        try {
            await this.connectionLimiter.consume(ip);
        } catch (e) {
            throw new Error('Too many connection attempts');
        }
    }

    static async checkEventRateLimit(socketId: string): Promise<boolean> {
        try {
            await this.eventLimiter.consume(socketId);
            return true;
        } catch (e) {
            return false; // Rate limit exceeded
        }
    }
}
