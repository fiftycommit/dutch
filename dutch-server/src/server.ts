import express from 'express';
import { createServer } from 'node:http';
import { Server } from 'socket.io';
import cors from 'cors';
import path from 'node:path';
import { RoomManager } from './services/RoomManager';
import { setupConnectionHandler } from './handlers/connectionHandler';
import { setupRoomHandler } from './handlers/roomHandler';
import { setupGameHandler } from './handlers/gameHandler';
import { SecurityService } from './services/SecurityService';
import { setupPublicRoomHandlers } from './handlers/publicRoomHandlers';
import { publicRoomService } from './services/publicRoomService';
import botLearningRoutes from './routes/botLearningRoutes';
import playerLearningRoutes from './routes/playerLearningRoutes';
import sbmmRoutes from './routes/sbmmRoutes';
import authRoutes from './routes/authRoutes';
import friendsRoutes, { setFriendsIo } from './routes/friendsRoutes';
import roomRoutes from './routes/roomRoutes';
import adminRoutes from './routes/adminRoutes';
import chatKeyRoutes, { setChatIo } from './routes/chatKeyRoutes';
import { socketAuthMiddleware, handleSocketDisconnect, onlineUsers, userFocused } from './middleware/socketAuthMiddleware';
import { FriendsService } from './services/FriendsService';
import { roomRegistryService } from './services/RoomRegistryService';

const startedAt = new Date().toISOString();

function renderHomePage(roomCount: number) {
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
            📊 Centre d'entraînement — Stats des bots
          </a>
        </div>
        <p style="text-align: center; opacity: 0.8; margin-top: 10px;">
          Consulte les performances des bots par niveau de difficulté et l'équilibrage du SBMM !
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

export function startServer() {
  const app = express();
  const httpServer = createServer(app);

  const allowedOrigins = process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',')
    : ['https://dutch-game.me', 'http://localhost:3000', 'http://localhost:8080'];

  app.use(cors({ origin: allowedOrigins }));
  app.use(express.json());
  app.use(SecurityService.apiLimiter); // API Rate Limiting

  const io = new Server(httpServer, {
    cors: {
      origin: allowedOrigins,
      methods: ['GET', 'POST'],
    },
    pingTimeout: 60000,
    pingInterval: 25000,
  });

  // Injecter les références de présence pour le service d'amis
  FriendsService.setOnlineUsersRef(onlineUsers);
  FriendsService.setUserFocusedRef(userFocused);

  // Socket Auth Middleware (Firebase token verification)
  io.use(socketAuthMiddleware);

  // Socket Connection Rate Limiting
  io.use(async (socket, next) => {
    try {
      const ip = socket.handshake.address;
      await SecurityService.checkConnectionLimit(ip);
      next();
    } catch {
      next(new Error('Rate limit exceeded'));
    }
  });

  const roomManager = new RoomManager(io);
  roomRegistryService.startPeriodicSync(roomManager);

  io.on('connection', (socket) => {
    const user = socket.data.user;
    const userInfo = user ? ` (user: ${user.username})` : ' (guest)';
    console.log(`Client connected: ${socket.id}${userInfo}`);

    setupConnectionHandler(socket, roomManager);
    setupRoomHandler(socket, roomManager, io);
    setupGameHandler(socket, roomManager);
    setupPublicRoomHandlers(socket, new Map());

    socket.on('disconnect', () => {
      handleSocketDisconnect(socket);
    });
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

  app.get('/rooms/debug', (req, res) => {
    const secret = req.headers['x-admin-secret'] as string | undefined;
    if (!process.env.ADMIN_SECRET || secret !== process.env.ADMIN_SECRET) {
      res.status(403).json({ error: 'Accès refusé' });
      return;
    }
    res.json(roomManager.listRoomsDebug());
  });

  app.get('/rooms/public', (req, res) => {
    const publicRooms = publicRoomService.getAvailableRooms();
    res.json({ success: true, rooms: publicRooms });
  });

  app.get('/rooms/stats', (req, res) => {
    const stats = publicRoomService.getStats();
    res.json({ success: true, stats });
  });

  // Routes pour l'apprentissage des bots
  app.use('/api/bot-learning', botLearningRoutes);

  // Routes pour l'apprentissage des joueurs (profil SBMM)
  app.use('/api/player-learning', playerLearningRoutes);

  // Routes SBMM (nouveau système de matchmaking)
  app.use('/api/sbmm', sbmmRoutes);

  // Routes Auth (inscription, connexion, profil)
  app.use('/api/auth', authRoutes);

  // Routes Friends (amis, demandes, blocage)
  setFriendsIo(io, roomManager);
  app.use('/api/friends', friendsRoutes);

  // Routes Rooms (salons sauvegardés)
  app.use('/api/rooms', roomRoutes);

  // Routes Admin (gestion des utilisateurs)
  app.use('/api/admin', adminRoutes);

  // Routes Chat keys (chiffrement E2E)
  setChatIo(io);
  app.use('/api/chats', chatKeyRoutes);

  // Dashboard admin
  app.get('/admin', (req, res) => {
    res.sendFile(path.join(__dirname, '../public/admin.html'));
  });

  // Dashboard des stats des bots
  app.get('/bot-stats', (req, res) => {
    res.sendFile(path.join(__dirname, '../public/bot-stats.html'));
  });

  app.get('/shuffle-analysis', (req, res) => {
    res.sendFile(path.join(__dirname, '../public/shuffle-analysis.html'));
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
