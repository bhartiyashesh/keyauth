import crypto from 'crypto';
import { createServer, IncomingMessage, ServerResponse } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { URL } from 'url';
import { RoomManager } from './rooms.js';
import { handleMessage } from './handlers.js';
import { createApnsClient } from './apns.js';
import logger from './logger.js';

const port = parseInt(process.env.PORT || '3000', 10);
const roomTtlMinutes = parseInt(process.env.ROOM_TTL_MINUTES || '30', 10);
const roomManager = new RoomManager(roomTtlMinutes);

// Initialize APNs client (optional -- relay works without push for local testing)
try {
  createApnsClient();
} catch (err) {
  logger.warn({ err }, 'APNs client not initialized -- push notifications disabled');
}

const server = createServer((req: IncomingMessage, res: ServerResponse) => {
  if (req.url === '/health' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
    }));
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url!, `http://${req.headers.host}`);
  const roomId = url.searchParams.get('roomId');

  if (!roomId) {
    socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
    socket.destroy();
    return;
  }

  // RELAY-06: Enforce max 2 clients per room
  if (roomManager.clientCount(roomId) >= 2) {
    socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
    socket.destroy();
    return;
  }

  wss.handleUpgrade(req, socket, head, (ws) => {
    const clientId = crypto.randomUUID();
    wss.emit('connection', ws, req, roomId, clientId);
  });
});

wss.on('connection', (ws: WebSocket, req: IncomingMessage, roomId: string, clientId: string) => {
  const log = logger.child({ roomId, clientId });
  log.info('WebSocket connection established');

  ws.on('message', (data) => {
    const raw = data.toString();
    handleMessage(raw, ws, roomId, clientId, roomManager);
  });

  ws.on('close', () => {
    roomManager.leave(roomId, clientId);
    log.info('WebSocket connection closed');
  });

  ws.on('error', (err) => {
    log.error({ err }, 'WebSocket error');
    roomManager.leave(roomId, clientId);
  });
});

server.listen(port, () => {
  logger.info({ port, roomTtlMinutes }, 'Better Authenticator relay server listening');
});

// Graceful shutdown
function shutdown() {
  logger.info('Shutting down relay server');
  roomManager.shutdown();
  wss.close();
  server.close();
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

export { server, wss, roomManager, shutdown };
