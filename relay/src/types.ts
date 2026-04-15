import type { WebSocket } from 'ws';

export interface MessageEnvelope {
  v: number;
  type: string;
  id: string;
  payload: Record<string, unknown>;
}

export interface Client {
  ws: WebSocket;
  deviceToken?: string;
}

export interface Room {
  id: string;
  clients: Map<string, Client>;
  deviceToken?: string;
  lastActivity: number;
}

export type ErrorCode = 'room_full' | 'invalid_message' | 'room_not_found';
