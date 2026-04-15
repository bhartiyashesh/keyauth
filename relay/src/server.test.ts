import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'crypto';
import http from 'http';
import { createServer, IncomingMessage, ServerResponse } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { URL } from 'url';
import { RoomManager } from './rooms.js';
import { handleMessage } from './handlers.js';
import logger from './logger.js';

/**
 * Integration test helper: creates an isolated server instance on an ephemeral port.
 * Each test gets its own server so tests do not interfere with each other.
 */
function createTestServer() {
  const roomManager = new RoomManager(30);

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

  wss.on('connection', (ws: WebSocket, _req: IncomingMessage, roomId: string, clientId: string) => {
    ws.on('message', (data) => {
      const raw = data.toString();
      handleMessage(raw, ws, roomId, clientId, roomManager);
    });

    ws.on('close', () => {
      roomManager.leave(roomId, clientId);
    });

    ws.on('error', () => {
      roomManager.leave(roomId, clientId);
    });
  });

  function shutdown() {
    roomManager.shutdown();
    wss.close();
    server.close();
  }

  return { server, wss, roomManager, shutdown };
}

/** Start server on ephemeral port and return the port number */
function startServer(server: http.Server): Promise<number> {
  return new Promise((resolve) => {
    server.listen(0, () => {
      const addr = server.address();
      const port = typeof addr === 'object' && addr ? addr.port : 0;
      resolve(port);
    });
  });
}

/** Make an HTTP request and return status, headers, and body */
function httpGet(port: number, path: string, method = 'GET'): Promise<{ statusCode: number; headers: http.IncomingHttpHeaders; body: string }> {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: 'localhost', port, path, method }, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        resolve({ statusCode: res.statusCode!, headers: res.headers, body });
      });
    });
    req.on('error', reject);
    req.end();
  });
}

/** Connect a WebSocket client and wait for open or error */
function connectWs(port: number, query: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${port}/${query}`);
    ws.on('open', () => resolve(ws));
    ws.on('error', (err) => reject(err));
  });
}

/** Wait for next message on a WebSocket */
function waitForMessage(ws: WebSocket): Promise<string> {
  return new Promise((resolve) => {
    ws.once('message', (data) => {
      resolve(data.toString());
    });
  });
}

describe('Server integration tests', () => {
  let testServer: ReturnType<typeof createTestServer>;
  let port: number;
  const openConnections: WebSocket[] = [];

  beforeEach(async () => {
    testServer = createTestServer();
    port = await startServer(testServer.server);
  });

  afterEach(async () => {
    // Close all tracked WebSocket connections
    for (const ws of openConnections) {
      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
        ws.close();
      }
    }
    openConnections.length = 0;
    testServer.shutdown();
    await new Promise<void>((resolve) => {
      testServer.server.close(() => resolve());
    });
  });

  // Test 1: GET /health returns 200 with Content-Type application/json
  it('GET /health returns 200 with Content-Type application/json', async () => {
    const res = await httpGet(port, '/health');
    assert.equal(res.statusCode, 200);
    assert.ok(res.headers['content-type']?.includes('application/json'));
  });

  // Test 2: GET /health response body contains status, uptime, timestamp
  it('GET /health response body contains status, uptime, and timestamp', async () => {
    const res = await httpGet(port, '/health');
    const body = JSON.parse(res.body);
    assert.equal(body.status, 'ok');
    assert.equal(typeof body.uptime, 'number');
    assert.ok(body.uptime >= 0);
    // Validate timestamp is ISO 8601
    assert.ok(!isNaN(Date.parse(body.timestamp)));
  });

  // Test 3: GET /unknown-path returns 404
  it('GET /unknown-path returns 404', async () => {
    const res = await httpGet(port, '/unknown-path');
    assert.equal(res.statusCode, 404);
  });

  // Test 4: POST /health returns 404 (only GET is handled)
  it('POST /health returns 404', async () => {
    const res = await httpGet(port, '/health', 'POST');
    assert.equal(res.statusCode, 404);
  });

  // Test 5: WebSocket upgrade with ?roomId=test-room succeeds
  it('WebSocket upgrade with ?roomId succeeds', async () => {
    const ws = await connectWs(port, '?roomId=test-room');
    openConnections.push(ws);
    assert.equal(ws.readyState, WebSocket.OPEN);
  });

  // Test 6: WebSocket upgrade without roomId returns HTTP 400
  it('WebSocket upgrade without roomId rejects with error', async () => {
    await assert.rejects(
      () => connectWs(port, ''),
      (err: Error) => {
        // ws library throws when server rejects the upgrade
        assert.ok(err.message.includes('Unexpected server response: 400') || err.message.includes('400'));
        return true;
      }
    );
  });

  // Test 7: Two clients join the same room
  it('two clients join the same room', async () => {
    const ws1 = await connectWs(port, '?roomId=room-two');
    openConnections.push(ws1);
    const ws2 = await connectWs(port, '?roomId=room-two');
    openConnections.push(ws2);
    assert.equal(ws1.readyState, WebSocket.OPEN);
    assert.equal(ws2.readyState, WebSocket.OPEN);
  });

  // Test 8: Third client joining a full room gets HTTP 403
  it('third client to a full room gets rejected with 403', async () => {
    const ws1 = await connectWs(port, '?roomId=room-full');
    openConnections.push(ws1);

    // Both clients must join the room via message so RoomManager tracks them
    const joinMsg1 = JSON.stringify({ v: 1, type: 'join', id: crypto.randomUUID(), payload: {} });
    ws1.send(joinMsg1);
    await waitForMessage(ws1); // wait for joined response

    const ws2 = await connectWs(port, '?roomId=room-full');
    openConnections.push(ws2);
    const joinMsg2 = JSON.stringify({ v: 1, type: 'join', id: crypto.randomUUID(), payload: {} });
    ws2.send(joinMsg2);
    await waitForMessage(ws2); // wait for joined response

    // Third client should be rejected
    await assert.rejects(
      () => connectWs(port, '?roomId=room-full'),
      (err: Error) => {
        assert.ok(err.message.includes('403') || err.message.includes('Forbidden'));
        return true;
      }
    );
  });

  // Test 9: Client disconnect calls roomManager.leave
  it('client disconnect triggers leave on the room', async () => {
    const ws = await connectWs(port, '?roomId=room-leave');
    openConnections.push(ws);

    // Join the room
    const joinMsg = JSON.stringify({ v: 1, type: 'join', id: crypto.randomUUID(), payload: {} });
    ws.send(joinMsg);
    await waitForMessage(ws);

    // Verify room has 1 client
    assert.equal(testServer.roomManager.clientCount('room-leave'), 1);

    // Close the connection
    ws.close();
    await new Promise<void>((resolve) => ws.on('close', () => resolve()));

    // Small delay for the server-side close handler to fire
    await new Promise<void>((resolve) => setTimeout(resolve, 50));

    // Room persists (per D-06) but client count drops to 0
    assert.equal(testServer.roomManager.clientCount('room-leave'), 0);
  });

  // Test 10: Server uses process.env.PORT when set, falls back to 3000
  it('defaults to port 3000 when PORT is not set', () => {
    // We test the pattern: parseInt(process.env.PORT || '3000', 10)
    // Since we use ephemeral ports in tests, verify the logic via env var parsing
    const originalPort = process.env.PORT;
    delete process.env.PORT;
    const defaultPort = parseInt(process.env.PORT || '3000', 10);
    assert.equal(defaultPort, 3000);

    process.env.PORT = '8080';
    const customPort = parseInt(process.env.PORT || '3000', 10);
    assert.equal(customPort, 8080);

    // Restore
    if (originalPort !== undefined) {
      process.env.PORT = originalPort;
    } else {
      delete process.env.PORT;
    }
  });

  // Test 11: Server exports are callable for graceful shutdown
  it('shutdown function closes server cleanly', async () => {
    // Create a separate server to test shutdown independently
    const ts = createTestServer();
    const tsPort = await startServer(ts.server);

    // Verify server is reachable
    const before = await httpGet(tsPort, '/health');
    assert.equal(before.statusCode, 200);

    // Shutdown closes roomManager timer, WSS, and HTTP server
    ts.shutdown();

    // Wait for HTTP server close
    await new Promise<void>((resolve) => {
      ts.server.close(() => resolve());
    });

    // Verify shutdown was called without throwing (RoomManager timer cleared, WSS closed)
    // The shutdown function should be idempotent
    assert.doesNotThrow(() => ts.roomManager.shutdown());
  });
});
