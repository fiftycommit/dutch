import { ipKeyGenerator, rateLimit } from 'express-rate-limit';
import { RateLimiterMemory } from 'rate-limiter-flexible';
import type { Request } from 'express';
import type { Socket } from 'socket.io';

export class SecurityService {
    private static readonly ipv6Subnet = 56;

    private static getNormalizedIp(rawIp?: string): string {
        return ipKeyGenerator(rawIp || 'unknown', this.ipv6Subnet);
    }

    private static getRateLimitKey(req: Request): string {
        return this.getNormalizedIp(req.ip || req.socket.remoteAddress || 'unknown');
    }

    static getSocketClientIp(socket: Socket): string {
        const xff = socket.handshake.headers['x-forwarded-for'];
        if (typeof xff === 'string' && xff.trim().length > 0) {
            return xff.split(',')[0].trim();
        }
        if (Array.isArray(xff) && xff.length > 0 && xff[0]) {
            return xff[0].split(',')[0].trim();
        }

        const xRealIp = socket.handshake.headers['x-real-ip'];
        if (typeof xRealIp === 'string' && xRealIp.trim().length > 0) {
            return xRealIp.trim();
        }

        return socket.handshake.address || 'unknown';
    }

    private static getSocketIdentityKey(socket: Socket): string {
        const uid = typeof socket.data?.user?.uid === 'string'
            ? socket.data.user.uid.trim()
            : '';
        const ipKey = this.getNormalizedIp(this.getSocketClientIp(socket));

        if (uid) {
            return `uid:${uid}:${ipKey}`;
        }

        return `ip:${ipKey}`;
    }

    // 1. Rate Limiting pour les requêtes HTTP (Express)
    // Limite: 500 requêtes par 15 minutes par IP (environ 33 req/min)
    // Protection basique contre le brute-force HTTP
    public static readonly apiLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 500,
        standardHeaders: true,
        legacyHeaders: false,
        message: 'Trop de requêtes, veuillez réessayer plus tard.',
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    // Rate limiting plus permissif pour les records de learning
    // (les fins de parties + trainer peuvent générer des bursts légitimes).
    public static readonly botLearningLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 6000,
        standardHeaders: true,
        legacyHeaders: false,
        message: 'Trop de requêtes, veuillez réessayer plus tard.',
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    public static readonly publicEndpointLimiter = rateLimit({
        windowMs: 5 * 60 * 1000,
        max: 120,
        standardHeaders: true,
        legacyHeaders: false,
        message: { success: false, error: 'Trop de requêtes publiques, réessayez plus tard.' },
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    public static readonly userDataLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 180,
        standardHeaders: true,
        legacyHeaders: false,
        message: { success: false, error: 'Trop de requêtes, ralentissez un peu.' },
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    public static readonly socialLookupLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 40,
        standardHeaders: true,
        legacyHeaders: false,
        message: { success: false, error: 'Trop de recherches utilisateur, réessayez plus tard.' },
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    public static readonly socialActionLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 80,
        standardHeaders: true,
        legacyHeaders: false,
        message: { success: false, error: 'Trop d\'actions sociales, reessayez plus tard.' },
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    public static readonly learningReadLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 240,
        standardHeaders: true,
        legacyHeaders: false,
        message: { success: false, error: 'Trop de lectures learning, réessayez plus tard.' },
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    public static readonly learningWriteLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 90,
        standardHeaders: true,
        legacyHeaders: false,
        message: { success: false, error: 'Trop d\'ecritures learning, reessayez plus tard.' },
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    public static readonly sbmmReadLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 180,
        standardHeaders: true,
        legacyHeaders: false,
        message: { success: false, error: 'Trop de requêtes matchmaking, réessayez plus tard.' },
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    public static readonly sbmmWriteLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 90,
        standardHeaders: true,
        legacyHeaders: false,
        message: { success: false, error: 'Trop de mises à jour matchmaking, réessayez plus tard.' },
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    public static readonly chatNotifyLimiter = rateLimit({
        windowMs: 5 * 60 * 1000,
        max: 90,
        standardHeaders: true,
        legacyHeaders: false,
        message: { success: false, error: 'Trop de notifications envoyées, réessayez plus tard.' },
        keyGenerator: (req) => this.getRateLimitKey(req),
    });

    // 2. Rate Limiting pour les connexions Socket.IO (Anti-Flood)
    // Limite: 30 connexions par minute par IP (1 connexion toutes les 2 sec moyenne)
    // Suffisant pour recharger la page, mais bloque les bots de connexion
    private static connectionLimiter = new RateLimiterMemory({
        points: 30,
        duration: 60,
    });

    // 3. Rate Limiting pour les événements de jeu (Anti-Spam)
    // Limite: 20 actions par seconde par joueur (permet des bursts rapides mais bloque le spam soutenu)
    private static eventLimiter = new RateLimiterMemory({
        points: 20,
        duration: 1,
    });

    // 4. Rate Limiting spécifique pour les matchs de cartes (Anti-Spam Match)
    // Limite: 1 match par 500ms par joueur (évite le spam de matchs qui vide la pioche)
    private static matchLimiter = new RateLimiterMemory({
        points: 1,
        duration: 0.5, // 500ms entre chaque tentative de match
    });

    // 5. Rate Limiting pour les tentatives de join (Anti-Brute-Force room codes)
    // Limite: 5 tentatives par minute par IP
    private static joinAttemptLimiter = new RateLimiterMemory({
        points: 5,
        duration: 60,
    });

    // 6. Rate limiting pour les requêtes socket publiques (liste des salons)
    private static publicRoomsLimiter = new RateLimiterMemory({
        points: 15,
        duration: 10,
    });

    static async checkConnectionLimit(socket: Socket): Promise<void> {
        try {
            await this.connectionLimiter.consume(this.getSocketIdentityKey(socket));
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

    static async checkMatchRateLimit(socketId: string): Promise<boolean> {
        try {
            await this.matchLimiter.consume(socketId);
            return true;
        } catch (e) {
            return false; // Rate limit exceeded - trop de tentatives de match
        }
    }

    static async checkJoinAttemptLimit(socket: Socket): Promise<boolean> {
        try {
            const key = this.getNormalizedIp(this.getSocketClientIp(socket));
            await this.joinAttemptLimiter.consume(key);
            return true;
        } catch (e) {
            return false; // Rate limit exceeded - trop de tentatives de join
        }
    }

    static async checkPublicRoomQueryLimit(socket: Socket): Promise<boolean> {
        try {
            await this.publicRoomsLimiter.consume(this.getSocketIdentityKey(socket));
            return true;
        } catch (e) {
            return false; // Rate limit exceeded - énumération de salons publics
        }
    }

    /** Réinitialise tous les rate limiters (usage tests uniquement) */
    static resetForTesting(): void {
        this.eventLimiter = new RateLimiterMemory({ points: 20, duration: 1 });
        this.matchLimiter = new RateLimiterMemory({ points: 1, duration: 0.5 });
        this.connectionLimiter = new RateLimiterMemory({ points: 30, duration: 60 });
        this.joinAttemptLimiter = new RateLimiterMemory({ points: 5, duration: 60 });
        this.publicRoomsLimiter = new RateLimiterMemory({ points: 15, duration: 10 });
    }
}
