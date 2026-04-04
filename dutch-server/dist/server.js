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
const FriendsService_1 = require("./services/FriendsService");
const RoomRegistryService_1 = require("./services/RoomRegistryService");
const startedAt = new Date().toISOString();
function startServer() {
    const app = (0, express_1.default)();
    const httpServer = (0, node_http_1.createServer)(app);
    const allowedOrigins = process.env.ALLOWED_ORIGINS
        ? process.env.ALLOWED_ORIGINS.split(',')
        : ['https://dutch-game.me', 'http://localhost:3000', 'http://localhost:8080'];
    app.disable('x-powered-by');
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
    // Injecter les références de présence pour le service d'amis
    FriendsService_1.FriendsService.setOnlineUsersRef(socketAuthMiddleware_1.onlineUsers);
    FriendsService_1.FriendsService.setUserFocusedRef(socketAuthMiddleware_1.userFocused);
    // Socket Auth Middleware (Firebase token verification)
    io.use(socketAuthMiddleware_1.socketAuthMiddleware);
    // Socket Connection Rate Limiting
    io.use(async (socket, next) => {
        try {
            const ip = socket.handshake.address;
            await SecurityService_1.SecurityService.checkConnectionLimit(ip);
            next();
        }
        catch {
            next(new Error('Rate limit exceeded'));
        }
    });
    const roomManager = new RoomManager_1.RoomManager(io);
    RoomRegistryService_1.roomRegistryService.startPeriodicSync(roomManager);
    io.on('connection', (socket) => {
        const user = socket.data.user;
        const userInfo = user ? ` (user: ${user.username})` : ' (guest)';
        console.log(`Client connected: ${socket.id}${userInfo}`);
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
</urlset>`);
    });
    app.get('/version', (req, res) => {
        res.json({ status: 'ok' });
    });
    app.get('/rooms/debug', adminAuthMiddleware_1.adminLimiter, adminAuthMiddleware_1.requireAdmin, (req, res) => {
        res.json(roomManager.listRoomsDebug());
    });
    app.get('/rooms/public', (req, res) => {
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
        res.sendFile(node_path_1.default.join(__dirname, '../public/admin-auth.js'));
    });
    // Pages admin — HTML servi sans auth pour permettre le login, les API restent protégées
    app.get('/admin-login', (req, res) => {
        res.sendFile(node_path_1.default.join(__dirname, '../public/admin-login.html'));
    });
    app.get(['/status', '/admin-home'], (req, res) => {
        res.sendFile(node_path_1.default.join(__dirname, '../public/admin-home.html'));
    });
    app.get('/admin', (req, res) => {
        res.sendFile(node_path_1.default.join(__dirname, '../public/admin.html'));
    });
    app.get('/bot-stats', (req, res) => {
        res.sendFile(node_path_1.default.join(__dirname, '../public/bot-stats.html'));
    });
    app.get('/bot-dashboard', (req, res) => {
        res.sendFile(node_path_1.default.join(__dirname, '../public/bot-dashboard.html'));
    });
    app.get('/shuffle-analysis', (req, res) => {
        res.sendFile(node_path_1.default.join(__dirname, '../public/shuffle-analysis.html'));
    });
    app.get('/player-profile', (req, res) => {
        res.sendFile('player-profile.html', { root: './public' });
    });
    const PORT = process.env.PORT || 3000;
    httpServer.listen(PORT, () => {
        console.log(`🚀 Dutch Server running on port ${PORT}`);
        console.log(`📡 Socket.IO ready for connections`);
    });
    return { app, io, httpServer, roomManager };
}
//# sourceMappingURL=server.js.map