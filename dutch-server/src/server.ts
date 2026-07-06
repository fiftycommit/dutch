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
import authRoutes from './routes/authRoutes';
import friendsRoutes, { setFriendsIo } from './routes/friendsRoutes';
import roomRoutes from './routes/roomRoutes';
import adminRoutes from './routes/adminRoutes';
import chatKeyRoutes, { setChatIo } from './routes/chatKeyRoutes';
import { socketAuthMiddleware, handleSocketDisconnect, onlineUsers, userFocused } from './middleware/socketAuthMiddleware';
import { requireAdmin, requireAdminPage, adminLimiter } from './middleware/adminAuthMiddleware';
import { requireAppCheck } from './middleware/appCheckMiddleware';
import { FriendsService } from './services/FriendsService';
import { roomRegistryService } from './services/RoomRegistryService';
import { RedisService } from './services/RedisService';
import {
  analyticsAdminContentSecurityPolicy,
  publicHtmlContentSecurityPolicy,
  strictAdminContentSecurityPolicy,
} from './security/contentSecurityPolicy';

const startedAt = new Date().toISOString();

export async function startServer() {
  const app = express();
  const httpServer = createServer(app);
  const publicDir = path.join(__dirname, '../public');

  const allowedOrigins = process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',')
    : ['https://dutch-game.me', 'http://localhost:3000', 'http://localhost:8080'];

  // Hors production (dev/test local), on accepte n'importe quel origine localhost
  // pour ne pas dépendre du port sur lequel le build web est servi. La prod garde
  // l'allowlist stricte.
  const isDev = process.env.NODE_ENV !== 'production';
  const localhostOrigin = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;
  const corsOrigin: cors.CorsOptions['origin'] = isDev
    ? (origin, cb) =>
        cb(
          null,
          !origin || localhostOrigin.test(origin) || allowedOrigins.includes(origin),
        )
    : allowedOrigins;

  app.disable('x-powered-by');
  app.set('trust proxy', 1);
  app.use(cors({ origin: corsOrigin }));
  app.use(express.json());
  app.use(SecurityService.apiLimiter); // API Rate Limiting

  const io = new Server(httpServer, {
    cors: {
      origin: corsOrigin,
      methods: ['GET', 'POST'],
    },
    pingTimeout: 60000,
    pingInterval: 25000,
  });

  const redisRuntime = await RedisService.initialize();
  const redisAdapter = RedisService.getAdapterFactory();
  if (redisAdapter) {
    io.adapter(redisAdapter);
  }

  // Injecter les références de présence pour le service d'amis
  FriendsService.setOnlineUsersRef(onlineUsers);
  FriendsService.setUserFocusedRef(userFocused);
  FriendsService.setIo(io);

  // Socket Auth Middleware (Firebase token verification)
  io.use(socketAuthMiddleware);

  // Socket Connection Rate Limiting
  io.use(async (socket, next) => {
    try {
      await SecurityService.checkConnectionLimit(socket);
      next();
    } catch {
      next(new Error('Rate limit exceeded'));
    }
  });

  const roomManager = new RoomManager(io, {
    sharedRoomStore: redisRuntime.roomStore,
  });
  await roomManager.hydrateFromSharedStore();
  roomRegistryService.startPeriodicSync(roomManager);

  io.on('connection', (socket) => {
    const user = socket.data.user;
    const userInfo = user ? ` (user: ${user.username})` : ' (guest)';
    console.log(`Client connected: ${socket.id}${userInfo}`);

    if (user?.uid) {
      socket.join(FriendsService.getUserRoom(user.uid));
    }

    setupConnectionHandler(socket, roomManager);
    setupRoomHandler(socket, roomManager, io);
    setupGameHandler(socket, roomManager);
    setupPublicRoomHandlers(socket, new Map());

    socket.on('disconnect', () => {
      handleSocketDisconnect(socket);
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

  const withContentSecurityPolicy = (policy: string) => (
    req: express.Request,
    res: express.Response,
    next: express.NextFunction,
  ) => {
    res.setHeader('Content-Security-Policy', policy);
    next();
  };

  app.get('/rooms/debug', adminLimiter, requireAdmin, (req, res) => {
    res.json(roomManager.listRoomsDebug());
  });

  app.get('/rooms/public', requireAppCheck, SecurityService.publicEndpointLimiter, (req, res) => {
    const publicRooms = publicRoomService.getAvailableRooms();
    res.json({ success: true, rooms: publicRooms });
  });

  app.get('/rooms/stats', adminLimiter, requireAdmin, (req, res) => {
    const stats = publicRoomService.getStats();
    res.json({ success: true, stats });
  });

  // Routes pour l'apprentissage des bots
  app.use('/api/bot-learning', botLearningRoutes);

  // Routes pour l'apprentissage des joueurs (profil SBMM)
  app.use('/api/player-learning', playerLearningRoutes);

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

  // Fichier JS partagé pour l'auth admin (accessible publiquement)
  app.get('/admin-auth.js', (req, res) => {
    res.sendFile(path.join(publicDir, 'admin-auth.js'));
  });

  app.use('/admin-assets', express.static(path.join(publicDir, 'admin-assets'), {
    index: false,
    fallthrough: true,
    setHeaders(res) {
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    },
  }));

  // Login admin public ; les autres pages admin sont protégées par une session httpOnly.
  app.get('/admin-login', withContentSecurityPolicy(strictAdminContentSecurityPolicy), (req, res) => {
    res.sendFile(path.join(publicDir, 'admin-login.html'));
  });

  app.get(
    ['/status', '/admin-home'],
    adminLimiter,
    requireAdminPage,
    withContentSecurityPolicy(strictAdminContentSecurityPolicy),
    (req, res) => {
      res.sendFile(path.join(publicDir, 'admin-home.html'));
    },
  );

  app.get('/admin', adminLimiter, requireAdminPage, withContentSecurityPolicy(strictAdminContentSecurityPolicy), (req, res) => {
    res.sendFile(path.join(publicDir, 'admin.html'));
  });

  app.get('/bot-stats', adminLimiter, requireAdminPage, withContentSecurityPolicy(analyticsAdminContentSecurityPolicy), (req, res) => {
    res.sendFile(path.join(publicDir, 'bot-stats.html'));
  });

  app.get('/bot-dashboard', adminLimiter, requireAdminPage, withContentSecurityPolicy(analyticsAdminContentSecurityPolicy), (req, res) => {
    res.sendFile(path.join(publicDir, 'bot-dashboard.html'));
  });

  app.get('/shuffle-analysis', adminLimiter, requireAdminPage, withContentSecurityPolicy(analyticsAdminContentSecurityPolicy), (req, res) => {
    res.sendFile(path.join(publicDir, 'shuffle-analysis.html'));
  });

  app.get('/player-profile', adminLimiter, requireAdminPage, withContentSecurityPolicy(analyticsAdminContentSecurityPolicy), (req, res) => {
    res.sendFile(path.join(publicDir, 'player-profile.html'));
  });

  app.get('/rules', withContentSecurityPolicy(publicHtmlContentSecurityPolicy), (req, res) => {
    res.sendFile(path.join(publicDir, 'rules.html'));
  });

  app.get('/about', withContentSecurityPolicy(publicHtmlContentSecurityPolicy), (req, res) => {
    res.sendFile(path.join(publicDir, 'about.html'));
  });

  app.get('/strategies', withContentSecurityPolicy(publicHtmlContentSecurityPolicy), (req, res) => {
    res.sendFile(path.join(publicDir, 'strategies.html'));
  });

  app.get('/faq', withContentSecurityPolicy(publicHtmlContentSecurityPolicy), (req, res) => {
    res.sendFile(path.join(publicDir, 'faq.html'));
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
