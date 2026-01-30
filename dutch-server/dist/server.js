"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.startServer = startServer;
const express_1 = __importDefault(require("express"));
const http_1 = require("http");
const socket_io_1 = require("socket.io");
const cors_1 = __importDefault(require("cors"));
const path_1 = __importDefault(require("path"));
const RoomManager_1 = require("./services/RoomManager");
const connectionHandler_1 = require("./handlers/connectionHandler");
const roomHandler_1 = require("./handlers/roomHandler");
const gameHandler_1 = require("./handlers/gameHandler");
const SecurityService_1 = require("./services/SecurityService");
const publicRoomHandlers_1 = require("./handlers/publicRoomHandlers");
const publicRoomService_1 = require("./services/publicRoomService");
const botLearningRoutes_1 = __importDefault(require("./routes/botLearningRoutes"));
const playerLearningRoutes_1 = __importDefault(require("./routes/playerLearningRoutes"));
const startedAt = new Date().toISOString();
function renderHomePage(roomCount) {
    return `
    <!DOCTYPE html>
    <html lang="fr">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Dutch Game Server</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          max-width: 800px;
          margin: 50px auto;
          padding: 20px;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
        }
        .container {
          background: rgba(255,255,255,0.1);
          backdrop-filter: blur(10px);
          border-radius: 20px;
          padding: 40px;
          box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 { margin-top: 0; font-size: 3em; text-align: center; }
        .status {
          background: rgba(255,255,255,0.2);
          padding: 15px;
          border-radius: 10px;
          margin: 20px 0;
        }
        .status-item {
          display: flex;
          justify-content: space-between;
          margin: 10px 0;
          font-size: 1.1em;
        }
        .badge {
          background: #48bb78;
          padding: 5px 15px;
          border-radius: 20px;
          font-weight: bold;
        }
        .endpoint {
          background: rgba(0,0,0,0.3);
          padding: 10px;
          border-radius: 5px;
          margin: 5px 0;
          font-family: monospace;
        }
        a { color: #90cdf4; text-decoration: none; }
        a:hover { text-decoration: underline; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>🎮 Dutch Game Server</h1>
        <div class="status">
          <div class="status-item">
            <span>Status</span>
            <span class="badge">🟢 ONLINE</span>
          </div>
          <div class="status-item">
            <span>Rooms actives</span>
            <span><strong>${roomCount}</strong></span>
          </div>
          <div class="status-item">
            <span>Version</span>
            <span>1.0.0</span>
          </div>
        </div>

        <h2>🤖 Intelligence Artificielle</h2>
        <div style="text-align: center; margin: 20px 0;">
          <a href="/bot-stats" style="display: inline-block; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 15px 30px; border-radius: 8px; text-decoration: none; font-weight: bold; box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4); transition: transform 0.2s;">
            📊 Voir l'évolution des bots
          </a>
        </div>
        <p style="text-align: center; opacity: 0.8; margin-top: 10px;">
          Suis en temps réel l'apprentissage automatique des bots, leurs statistiques et leurs personnalités !
        </p>

        <h2>📡 Endpoints</h2>
        <div class="endpoint">GET <a href="/health">/health</a> - Health check</div>
        <div class="endpoint">GET <a href="/rooms">/rooms</a> - Liste des rooms</div>
        <div class="endpoint">WebSocket /socket.io - Connexion multijoueur</div>

        <h2>🎯 Comment jouer ?</h2>
        <p>Télécharge l'application mobile Dutch Game pour jouer en ligne avec tes amis !</p>

        <p style="text-align: center; margin-top: 40px; opacity: 0.7;">
          Propulsé par Socket.IO • Node.js • TypeScript
        </p>
      </div>
    </body>
    </html>
  `;
}
function startServer() {
    const app = (0, express_1.default)();
    const httpServer = (0, http_1.createServer)(app);
    app.use((0, cors_1.default)());
    app.use(express_1.default.json());
    app.use(SecurityService_1.SecurityService.apiLimiter); // API Rate Limiting
    const io = new socket_io_1.Server(httpServer, {
        cors: {
            origin: '*',
            methods: ['GET', 'POST'],
        },
        pingTimeout: 60000,
        pingInterval: 25000,
    });
    // Socket Connection Rate Limiting
    io.use(async (socket, next) => {
        try {
            const ip = socket.handshake.address;
            await SecurityService_1.SecurityService.checkConnectionLimit(ip);
            next();
        }
        catch (e) {
            next(new Error('Rate limit exceeded'));
        }
    });
    const roomManager = new RoomManager_1.RoomManager(io);
    io.on('connection', (socket) => {
        console.log(`Client connected: ${socket.id}`);
        (0, connectionHandler_1.setupConnectionHandler)(socket, roomManager);
        (0, roomHandler_1.setupRoomHandler)(socket, roomManager);
        (0, gameHandler_1.setupGameHandler)(socket, roomManager);
        // Les handlers publics gèrent leur propre état via publicRoomService
        (0, publicRoomHandlers_1.setupPublicRoomHandlers)(socket, new Map());
    });
    app.get('/status', (req, res) => {
        // Authentification basique optionnelle (décommente pour activer)
        // const auth = req.headers.authorization;
        // const token = process.env.STATUS_TOKEN || 'your-secret-token';
        // if (auth !== `Bearer ${token}`) {
        //   return res.status(401).json({ error: 'Unauthorized' });
        // }
        res.send(renderHomePage(roomManager.getRoomCount()));
    });
    app.get('/health', (req, res) => {
        res.json({ status: 'ok', rooms: roomManager.getRoomCount() });
    });
    app.get('/version', (req, res) => {
        res.json({
            sha: process.env.GIT_SHA || null,
            buildTime: process.env.BUILD_TIME || null,
            startedAt,
            nodeEnv: process.env.NODE_ENV || null,
        });
    });
    app.get('/rooms', (req, res) => {
        res.json(roomManager.listRooms());
    });
    app.get('/rooms/debug', (req, res) => {
        res.json(roomManager.listRoomsDebug());
    });
    app.get('/rooms/public', (req, res) => {
        const publicRooms = publicRoomService_1.publicRoomService.getAvailableRooms();
        res.json({ success: true, rooms: publicRooms });
    });
    app.get('/rooms/stats', (req, res) => {
        const stats = publicRoomService_1.publicRoomService.getStats();
        res.json({ success: true, stats });
    });
    // Routes pour l'apprentissage des bots
    app.use('/api/bot-learning', botLearningRoutes_1.default);
    // Routes pour l'apprentissage des joueurs (profil SBMM)
    app.use('/api/player-learning', playerLearningRoutes_1.default);
    // Dashboard des stats des bots
    app.get('/bot-stats', (req, res) => {
        res.sendFile(path_1.default.join(__dirname, '../public/bot-stats.html'));
    });
    app.get('/shuffle-analysis', (req, res) => {
        res.sendFile(path_1.default.join(__dirname, '../public/shuffle-analysis.html'));
    });
    // Dashboard profil joueur (SBMM)
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
