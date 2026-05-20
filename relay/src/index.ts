import crypto from 'crypto';
import { createServer, IncomingMessage, ServerResponse } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { URL } from 'url';
import { readFileSync, existsSync, statSync } from 'fs';
import { resolve, dirname, join, extname, normalize } from 'path';
import { fileURLToPath } from 'url';
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

// Resolve the landing dist directory. The relay/ directory ships next to landing/
// in the repo, so candidate paths cover the relevant deploy layouts:
//   1. relay/src/../../landing/dist (running via tsx from relay/)
//   2. process.cwd()/../landing/dist (cwd === relay/)
//   3. process.cwd()/landing/dist (cwd === KeyAuth/ repo root)
const __dirname = dirname(fileURLToPath(import.meta.url));
const landingDirCandidates = [
  resolve(__dirname, '..', '..', 'landing', 'dist'),
  resolve(process.cwd(), '..', 'landing', 'dist'),
  resolve(process.cwd(), 'landing', 'dist'),
];
const landingDir = landingDirCandidates.find((p) => existsSync(p)) ?? null;
if (landingDir) {
  logger.info({ landingDir }, 'Serving landing from built dist');
} else {
  logger.warn({ candidates: landingDirCandidates }, 'landing/dist not found -- root URL will return 503');
}

const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.json': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
};

function contentTypeFor(filePath: string): string {
  return MIME_TYPES[extname(filePath).toLowerCase()] ?? 'application/octet-stream';
}

// Vite emits hashed asset filenames like `popup-TNyvvao.js` -- those are safe to
// cache forever. index.html and unhashed files get a short cache for fast updates.
const HASHED_ASSET_RE = /[-.][a-zA-Z0-9]{8,}\.[a-zA-Z0-9]+$/;
function cacheHeaderFor(filePath: string): string {
  return HASHED_ASSET_RE.test(filePath)
    ? 'public, max-age=31536000, immutable'
    : 'public, max-age=300';
}

function serveLandingFile(req: IncomingMessage, res: ServerResponse): boolean {
  if (req.method !== 'GET' || !landingDir) return false;
  const rawPath = (req.url ?? '/').split('?')[0];
  const requestedPath = rawPath === '/' || rawPath === '' ? '/index.html' : rawPath;
  // Defense in depth against path traversal: normalize then verify the resolved
  // absolute path still lives under landingDir.
  const normalizedRel = normalize(decodeURIComponent(requestedPath)).replace(/^[/\\]+/, '');
  const absolute = resolve(landingDir, normalizedRel);
  if (!absolute.startsWith(landingDir + '/') && absolute !== landingDir) return false;
  try {
    const stat = statSync(absolute);
    if (!stat.isFile()) return false;
    const data = readFileSync(absolute);
    res.writeHead(200, {
      'Content-Type': contentTypeFor(absolute),
      'Cache-Control': cacheHeaderFor(absolute),
      'Content-Length': data.length,
    });
    res.end(data);
    return true;
  } catch {
    return false;
  }
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
  if (serveLandingFile(req, res)) return;
  if ((req.url === '/' || req.url === '') && req.method === 'GET' && !landingDir) {
    // Landing not built yet: surface this loudly rather than hand back an empty 404.
    res.writeHead(503, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Landing site not built. Run `npm run build` in the relay directory.');
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
  logger.info({ port, roomTtlMinutes }, 'Much Better Authenticator relay server listening');
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
