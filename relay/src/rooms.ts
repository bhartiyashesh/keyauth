import { WebSocket } from 'ws';
import type { Room, Client } from './types.js';
import logger from './logger.js';

export class RoomManager {
  private rooms = new Map<string, Room>();
  private ttlMs: number;
  private timer: NodeJS.Timeout;

  constructor(ttlMinutes: number = 30) {
    this.ttlMs = ttlMinutes * 60 * 1000;
    this.timer = setInterval(() => this.evict(), 5 * 60 * 1000);
  }

  join(roomId: string, clientId: string, ws: WebSocket, deviceToken?: string): Room {
    let room = this.rooms.get(roomId);
    if (!room) {
      room = { id: roomId, clients: new Map(), lastActivity: Date.now() };
      this.rooms.set(roomId, room);
      logger.info({ roomId }, 'Room created');
    }
    room.clients.set(clientId, { ws, deviceToken });
    if (deviceToken) room.deviceToken = deviceToken;
    room.lastActivity = Date.now();
    logger.info({ roomId, clientId, clientCount: room.clients.size }, 'Client joined room');
    return room;
  }

  leave(roomId: string, clientId: string): void {
    const room = this.rooms.get(roomId);
    if (!room) return;
    room.clients.delete(clientId);
    room.lastActivity = Date.now();
    logger.info({ roomId, clientId, clientCount: room.clients.size }, 'Client left room');
    // Do NOT delete room -- TTL handles cleanup per D-06
  }

  forward(roomId: string, senderClientId: string, data: string): void {
    const room = this.rooms.get(roomId);
    if (!room) return;
    room.lastActivity = Date.now();
    for (const [id, client] of room.clients) {
      if (id !== senderClientId && client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(data);
      }
    }
  }

  getRoom(roomId: string): Room | undefined {
    return this.rooms.get(roomId);
  }

  clientCount(roomId: string): number {
    return this.rooms.get(roomId)?.clients.size ?? 0;
  }

  hasIosClient(roomId: string): boolean {
    const room = this.rooms.get(roomId);
    if (!room) return false;
    for (const client of room.clients.values()) {
      if (client.deviceToken) return true;
    }
    return false;
  }

  evict(): void {
    const now = Date.now();
    for (const [id, room] of this.rooms) {
      if (room.clients.size === 0 && now - room.lastActivity > this.ttlMs) {
        this.rooms.delete(id);
        logger.info({ roomId: id }, 'Room evicted (TTL expired)');
      }
    }
  }

  get roomCount(): number {
    return this.rooms.size;
  }

  shutdown(): void {
    clearInterval(this.timer);
  }
}
