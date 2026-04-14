"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.startServer = startServer;
const express_1 = __importDefault(require("express"));
const node_http_1 = require("node:http");
const socket_io_1 = require("socket.io");
const cors_1 = __importDefault(require("cors"));
const node_path_1 = __importDefault(require("node:path"));
const RoomManager_1 = require("./services/RoomManager");
const connectionHandler_1 = require("./handlers/connectionHandler");
const roomHandler_1 = require("./handlers/roomHandler");
const gameHandler_1 = require("./handlers/gameHandler");
const SecurityService_1 = require("./services/SecurityService");
const publicRoomHandlers_1 = require("./handlers/publicRoomHandlers");
const publicRoomService_1 = require("./services/publicRoomService");
const botLearningRoutes_1 = __importDefault(require("./routes/botLearningRoutes"));
const playerLearningRoutes_1 = __importDefault(require("./routes/playerLearningRoutes"));
const sbmmRoutes_1 = __importDefault(require("./routes/sbmmRoutes"));
const authRoutes_1 = __importDefault(require("./routes/authRoutes"));
const friendsRoutes_1 = __importStar(require("./routes/friendsRoutes"));
const roomRoutes_1 = __importDefault(require("./routes/roomRoutes"));
const adminRoutes_1 = __importDefault(require("./routes/adminRoutes"));
const chatKeyRoutes_1 = __importStar(require("./routes/chatKeyRoutes"));
const socketAuthMiddleware_1 = require("./middleware/socketAuthMiddleware");
const adminAuthMiddleware_1 = require("./middleware/adminAuthMiddleware");
const appCheckMiddleware_1 = require("./middleware/appCheckMiddleware");
const FriendsService_1 = require("./services/FriendsService");
const RoomRegistryService_1 = require("./services/RoomRegistryService");
const RedisService_1 = require("./services/RedisService");
const contentSecurityPolicy_1 = require("./security/contentSecurityPolicy");
const startedAt = new Date().toISOString();
async function startServer() {
    const app = (0, express_1.default)();
    const httpServer = (0, node_http_1.createServer)(app);
    const publicDir = node_path_1.default.join(__dirname, '../public');
    const allowedOrigins = process.env.ALLOWED_ORIGINS
        ? process.env.ALLOWED_ORIGINS.split(',')
        : ['https://dutch-game.me', 'http://localhost:3000', 'http://localhost:8080'];
    app.disable('x-powered-by');
    app.set('trust proxy', 1);
    app.use((0, cors_1.default)({ origin: allowedOrigins }));
    app.use(express_1.default.json());
    app.use(SecurityService_1.SecurityService.apiLimiter); // API Rate Limiting
    const io = new socket_io_1.Server(httpServer, {
        cors: {
            origin: allowedOrigins,
            methods: ['GET', 'POST'],
        },
        pingTimeout: 60000,
        pingInterval: 25000,
    });
    const redisRuntime = await RedisService_1.RedisService.initialize();
    const redisAdapter = RedisService_1.RedisService.getAdapterFactory();
    if (redisAdapter) {
        io.adapter(redisAdapter);
    }
    // Injecter les références de présence pour le service d'amis
    FriendsService_1.FriendsService.setOnlineUsersRef(socketAuthMiddleware_1.onlineUsers);
    FriendsService_1.FriendsService.setUserFocusedRef(socketAuthMiddleware_1.userFocused);
    FriendsService_1.FriendsService.setIo(io);
    // Socket Auth Middleware (Firebase token verification)
    io.use(socketAuthMiddleware_1.socketAuthMiddleware);
    // Socket Connection Rate Limiting
    io.use(async (socket, next) => {
        try {
            await SecurityService_1.SecurityService.checkConnectionLimit(socket);
            next();
        }
        catch {
            next(new Error('Rate limit exceeded'));
        }
    });
    const roomManager = new RoomManager_1.RoomManager(io, {
        sharedRoomStore: redisRuntime.roomStore,
    });
    await roomManager.hydrateFromSharedStore();
    RoomRegistryService_1.roomRegistryService.startPeriodicSync(roomManager);
    io.on('connection', (socket) => {
        const user = socket.data.user;
        const userInfo = user ? ` (user: ${user.username})` : ' (guest)';
        console.log(`Client connected: ${socket.id}${userInfo}`);
        if (user?.uid) {
            socket.join(FriendsService_1.FriendsService.getUserRoom(user.uid));
        }
        (0, connectionHandler_1.setupConnectionHandler)(socket, roomManager);
        (0, roomHandler_1.setupRoomHandler)(socket, roomManager, io);
        (0, gameHandler_1.setupGameHandler)(socket, roomManager);
        (0, publicRoomHandlers_1.setupPublicRoomHandlers)(socket, new Map());
        socket.on('disconnect', () => {
            (0, socketAuthMiddleware_1.handleSocketDisconnect)(socket);
        });
    });
    app.get('/health', (req, res) => {
        res.json({ status: 'ok', rooms: roomManager.getRoomCount() });
    });
    // SEO - Dynamic sitemap with real lastmod
    app.get('/sitemap.xml', (req, res) => {
        res.set('Content-Type', 'application/xml');
        const lastMod = new Date().toISOString().split('T')[0];
        res.send(`<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://dutch-game.me/</loc>
    <lastmod>${lastMod}</lastmod>
    <changefreq>daily</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>https://dutch-game.me/rules</loc>
    <lastmod>${lastMod}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://dutch-game.me/about</loc>
    <lastmod>${lastMod}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.9</priority>
  </url>
  <url>
    <loc>https://dutch-game.me/strategies</loc>
    <lastmod>${lastMod}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://dutch-game.me/faq</loc>
    <lastmod>${lastMod}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://dutch-game.me/login</loc>
    <lastmod>${lastMod}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.6</priority>
  </url>
  <url>
    <loc>https://dutch-game.me/setup</loc>
    <lastmod>${lastMod}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
</urlset>`);
    });
    app.get('/version', (req, res) => {
        res.json({ status: 'ok' });
    });
    const withContentSecurityPolicy = (policy) => (req, res, next) => {
        res.setHeader('Content-Security-Policy', policy);
        next();
    };
    app.get('/rooms/debug', adminAuthMiddleware_1.adminLimiter, adminAuthMiddleware_1.requireAdmin, (req, res) => {
        res.json(roomManager.listRoomsDebug());
    });
    app.get('/rooms/public', appCheckMiddleware_1.requireAppCheck, SecurityService_1.SecurityService.publicEndpointLimiter, (req, res) => {
        const publicRooms = publicRoomService_1.publicRoomService.getAvailableRooms();
        res.json({ success: true, rooms: publicRooms });
    });
    app.get('/rooms/stats', adminAuthMiddleware_1.adminLimiter, adminAuthMiddleware_1.requireAdmin, (req, res) => {
        const stats = publicRoomService_1.publicRoomService.getStats();
        res.json({ success: true, stats });
    });
    // Routes pour l'apprentissage des bots
    app.use('/api/bot-learning', botLearningRoutes_1.default);
    // Routes pour l'apprentissage des joueurs (profil SBMM)
    app.use('/api/player-learning', playerLearningRoutes_1.default);
    // Routes SBMM (nouveau système de matchmaking)
    app.use('/api/sbmm', sbmmRoutes_1.default);
    // Routes Auth (inscription, connexion, profil)
    app.use('/api/auth', authRoutes_1.default);
    // Routes Friends (amis, demandes, blocage)
    (0, friendsRoutes_1.setFriendsIo)(io, roomManager);
    app.use('/api/friends', friendsRoutes_1.default);
    // Routes Rooms (salons sauvegardés)
    app.use('/api/rooms', roomRoutes_1.default);
    // Routes Admin (gestion des utilisateurs)
    app.use('/api/admin', adminRoutes_1.default);
    // Routes Chat keys (chiffrement E2E)
    (0, chatKeyRoutes_1.setChatIo)(io);
    app.use('/api/chats', chatKeyRoutes_1.default);
    // Fichier JS partagé pour l'auth admin (accessible publiquement)
    app.get('/admin-auth.js', (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'admin-auth.js'));
    });
    app.use('/admin-assets', express_1.default.static(node_path_1.default.join(publicDir, 'admin-assets'), {
        index: false,
        fallthrough: true,
        setHeaders(res) {
            res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
        },
    }));
    // Login admin public ; les autres pages admin sont protégées par une session httpOnly.
    app.get('/admin-login', withContentSecurityPolicy(contentSecurityPolicy_1.strictAdminContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'admin-login.html'));
    });
    app.get(['/status', '/admin-home'], adminAuthMiddleware_1.adminLimiter, adminAuthMiddleware_1.requireAdminPage, withContentSecurityPolicy(contentSecurityPolicy_1.strictAdminContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'admin-home.html'));
    });
    app.get('/admin', adminAuthMiddleware_1.adminLimiter, adminAuthMiddleware_1.requireAdminPage, withContentSecurityPolicy(contentSecurityPolicy_1.strictAdminContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'admin.html'));
    });
    app.get('/bot-stats', adminAuthMiddleware_1.adminLimiter, adminAuthMiddleware_1.requireAdminPage, withContentSecurityPolicy(contentSecurityPolicy_1.analyticsAdminContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'bot-stats.html'));
    });
    app.get('/bot-dashboard', adminAuthMiddleware_1.adminLimiter, adminAuthMiddleware_1.requireAdminPage, withContentSecurityPolicy(contentSecurityPolicy_1.analyticsAdminContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'bot-dashboard.html'));
    });
    app.get('/shuffle-analysis', adminAuthMiddleware_1.adminLimiter, adminAuthMiddleware_1.requireAdminPage, withContentSecurityPolicy(contentSecurityPolicy_1.analyticsAdminContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'shuffle-analysis.html'));
    });
    app.get('/player-profile', adminAuthMiddleware_1.adminLimiter, adminAuthMiddleware_1.requireAdminPage, withContentSecurityPolicy(contentSecurityPolicy_1.analyticsAdminContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'player-profile.html'));
    });
    app.get('/rules', withContentSecurityPolicy(contentSecurityPolicy_1.publicHtmlContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'rules.html'));
    });
    app.get('/about', withContentSecurityPolicy(contentSecurityPolicy_1.publicHtmlContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'about.html'));
    });
    app.get('/strategies', withContentSecurityPolicy(contentSecurityPolicy_1.publicHtmlContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'strategies.html'));
    });
    app.get('/faq', withContentSecurityPolicy(contentSecurityPolicy_1.publicHtmlContentSecurityPolicy), (req, res) => {
        res.sendFile(node_path_1.default.join(publicDir, 'faq.html'));
    });
    const PORT = process.env.PORT || 3000;
    httpServer.listen(PORT, () => {
        console.log(`🚀 Dutch Server running on port ${PORT}`);
        console.log(`📡 Socket.IO ready for connections`);
        if (redisRuntime.enabled) {
            console.log('🧠 Redis shared state enabled');
        }
    });
    return { app, io, httpServer, roomManager };
}
//# sourceMappingURL=server.js.map