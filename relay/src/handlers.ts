import crypto from 'crypto';
import type { WebSocket } from 'ws';
import type { MessageEnvelope } from './types.js';
import { RoomManager } from './rooms.js';
import { sendWakeupPush } from './apns.js';
import logger from './logger.js';

export function parseMessage(raw: string): MessageEnvelope | null {
  try {
    const msg = JSON.parse(raw);
    if (msg.v !== 1 || !msg.type || !msg.id) return null;
    return msg as MessageEnvelope;
  } catch {
    return null;
  }
}

function sendError(ws: WebSocket, code: string, message: string): void {
  ws.send(JSON.stringify({
    v: 1,
    type: 'error',
    id: crypto.randomUUID(),
    payload: { code, message },
  }));
}

function sendResponse(ws: WebSocket, type: string, id: string, payload: Record<string, unknown> = {}): void {
  ws.send(JSON.stringify({ v: 1, type, id, payload }));
}

export function handleMessage(
  raw: string,
  ws: WebSocket,
  roomId: string,
  clientId: string,
  roomManager: RoomManager
): void {
  const msg = parseMessage(raw);
  const log = logger.child({ roomId, clientId });

  if (!msg) {
    sendError(ws, 'invalid_message', 'Malformed message envelope');
    log.warn('Received malformed message');
    return;
  }

  switch (msg.type) {
    case 'join': {
      const deviceToken = msg.payload.deviceToken as string | undefined;
      roomManager.join(roomId, clientId, ws, deviceToken);
      sendResponse(ws, 'joined', msg.id, { roomId });
      break;
    }

    case 'register_token': {
      const deviceToken = msg.payload.deviceToken as string | undefined;
      if (deviceToken) {
        const room = roomManager.getRoom(roomId);
        if (room) {
          const client = room.clients.get(clientId);
          if (client) {
            client.deviceToken = deviceToken;
            room.deviceToken = deviceToken;
            log.info('Device token registered');
          }
        }
        sendResponse(ws, 'token_registered', msg.id);
      } else {
        sendError(ws, 'invalid_message', 'register_token requires deviceToken in payload');
      }
      break;
    }

    case 'ping': {
      sendResponse(ws, 'pong', msg.id);
      break;
    }

    default: {
      // Opaque forward -- relay does NOT inspect payload (D-03)
      roomManager.forward(roomId, clientId, raw);
      log.debug({ type: msg.type }, 'Message forwarded');

      // If no iOS client is connected, send APNs push (D-10)
      if (!roomManager.hasIosClient(roomId)) {
        const room = roomManager.getRoom(roomId);
        if (room?.deviceToken) {
          const requestId = msg.id;
          sendWakeupPush(room.deviceToken, roomId, requestId).catch((err) => {
            log.error({ err }, 'Failed to send wakeup push');
          });
        }
      }
      break;
    }
  }
}
