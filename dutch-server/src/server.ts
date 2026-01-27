import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import { RoomManager } from './services/RoomManager';
import { setupConnectionHandler } from './handlers/connectionHandler';
import { setupRoomHandler } from './handlers/roomHandler';
import { setupGameHandler } from './handlers/gameHandler';

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

  app.use(cors());
  app.use(express.json());

  const io = new Server(httpServer, {
    cors: {
      origin: '*',
      methods: ['GET', 'POST'],
    },
    pingTimeout: 60000,
    pingInterval: 25000,
  });

  const roomManager = new RoomManager(io);

  io.on('connection', (socket) => {
    console.log(`Client connected: ${socket.id}`);
    setupConnectionHandler(socket, roomManager);
    setupRoomHandler(socket, roomManager);
    setupGameHandler(socket, roomManager);
  });

  app.get('/', (req, res) => {
    res.send(renderHomePage(roomManager.getRoomCount()));
  });

  app.get('/health', (req, res) => {
    res.json({ status: 'ok', rooms: roomManager.getRoomCount() });
  });

  app.get('/rooms', (req, res) => {
    res.json(roomManager.listRooms());
  });

  const PORT = process.env.PORT || 3000;

  httpServer.listen(PORT, () => {
    console.log(`🚀 Dutch Server running on port ${PORT}`);
    console.log(`📡 Socket.IO ready for connections`);
  });

  return { app, io, httpServer, roomManager };
}
