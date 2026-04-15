import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import type { WebSocket } from 'ws';
import { RoomManager } from './rooms.js';

function mockWs(readyState = 1): WebSocket {
  return { readyState, send: mock.fn() } as unknown as WebSocket;
}

describe('RoomManager', () => {
  let manager: RoomManager;

  beforeEach(() => {
    manager = new RoomManager(30);
  });

  afterEach(() => {
    manager.shutdown();
  });

  // Test 1: join() creates a new room when roomId does not exist
  it('creates a new room on first join', () => {
    const ws = mockWs();
    const room = manager.join('room-1', 'client-1', ws);
    assert.equal(room.id, 'room-1');
    assert.equal(room.clients.size, 1);
    assert.ok(room.clients.has('client-1'));
  });

  // Test 2: join() adds second client to existing room
  it('adds second client to existing room', () => {
    const ws1 = mockWs();
    const ws2 = mockWs();
    manager.join('room-1', 'client-1', ws1);
    const room = manager.join('room-1', 'client-2', ws2);
    assert.equal(room.clients.size, 2);
    assert.ok(room.clients.has('client-1'));
    assert.ok(room.clients.has('client-2'));
  });

  // Test 3: join() stores deviceToken on room when provided
  it('stores deviceToken on room when provided in join', () => {
    const ws = mockWs();
    const room = manager.join('room-1', 'client-1', ws, 'token-abc');
    assert.equal(room.deviceToken, 'token-abc');
    const client = room.clients.get('client-1');
    assert.equal(client?.deviceToken, 'token-abc');
  });

  // Test 4: getRoom() returns undefined for non-existent roomId
  it('returns undefined for non-existent room', () => {
    const room = manager.getRoom('nonexistent');
    assert.equal(room, undefined);
  });

  // Test 5: getRoom() returns Room for existing roomId
  it('returns room for existing roomId', () => {
    const ws = mockWs();
    manager.join('room-1', 'client-1', ws);
    const room = manager.getRoom('room-1');
    assert.ok(room);
    assert.equal(room.id, 'room-1');
  });

  // Test 6: leave() removes client from room, room still exists (D-06)
  it('removes client from room but room persists', () => {
    const ws = mockWs();
    manager.join('room-1', 'client-1', ws);
    manager.leave('room-1', 'client-1');
    const room = manager.getRoom('room-1');
    assert.ok(room, 'room should still exist after client leaves');
    assert.equal(room.clients.size, 0);
  });

  // Test 7: leave() on non-existent room does not throw
  it('leave on non-existent room does not throw', () => {
    assert.doesNotThrow(() => {
      manager.leave('nonexistent', 'client-1');
    });
  });

  // Test 8: forward() sends data to all other clients in room
  it('forwards data to other clients in room', () => {
    const ws1 = mockWs();
    const ws2 = mockWs();
    manager.join('room-1', 'client-1', ws1);
    manager.join('room-1', 'client-2', ws2);

    manager.forward('room-1', 'client-1', '{"test":"data"}');

    const sendFn = (ws2 as any).send as ReturnType<typeof mock.fn>;
    assert.equal(sendFn.mock.calls.length, 1);
    assert.equal(sendFn.mock.calls[0].arguments[0], '{"test":"data"}');

    // sender should NOT receive the message
    const senderSend = (ws1 as any).send as ReturnType<typeof mock.fn>;
    assert.equal(senderSend.mock.calls.length, 0);
  });

  // Test 9: forward() skips clients with ws.readyState !== OPEN
  it('skips clients with closed WebSocket', () => {
    const ws1 = mockWs();
    const ws2 = mockWs(3); // readyState 3 = CLOSED
    manager.join('room-1', 'client-1', ws1);
    manager.join('room-1', 'client-2', ws2);

    manager.forward('room-1', 'client-1', '{"test":"data"}');

    const sendFn = (ws2 as any).send as ReturnType<typeof mock.fn>;
    assert.equal(sendFn.mock.calls.length, 0);
  });

  // Test 10: forward() on non-existent room does not throw
  it('forward on non-existent room does not throw', () => {
    assert.doesNotThrow(() => {
      manager.forward('nonexistent', 'client-1', '{"test":"data"}');
    });
  });

  // Test 11: evict() removes rooms with 0 clients and lastActivity older than TTL
  it('evicts rooms with no clients past TTL', () => {
    const ws = mockWs();
    manager.join('room-1', 'client-1', ws);
    manager.leave('room-1', 'client-1');

    // Manually set lastActivity far in the past
    const room = manager.getRoom('room-1')!;
    room.lastActivity = Date.now() - 31 * 60 * 1000; // 31 minutes ago

    manager.evict();
    assert.equal(manager.getRoom('room-1'), undefined);
  });

  // Test 12: evict() keeps rooms with 0 clients but recent lastActivity
  it('keeps empty rooms with recent activity', () => {
    const ws = mockWs();
    manager.join('room-1', 'client-1', ws);
    manager.leave('room-1', 'client-1');

    // lastActivity is recent (just set by leave())
    manager.evict();
    assert.ok(manager.getRoom('room-1'), 'room should survive eviction');
  });

  // Test 13: evict() keeps rooms with active clients regardless of lastActivity
  it('keeps rooms with active clients regardless of age', () => {
    const ws = mockWs();
    manager.join('room-1', 'client-1', ws);

    // Manually set lastActivity far in the past
    const room = manager.getRoom('room-1')!;
    room.lastActivity = Date.now() - 60 * 60 * 1000; // 1 hour ago

    manager.evict();
    assert.ok(manager.getRoom('room-1'), 'room with clients should survive eviction');
  });

  // Test 14: clientCount() returns correct count
  it('returns correct client count for room', () => {
    assert.equal(manager.clientCount('nonexistent'), 0);

    const ws1 = mockWs();
    manager.join('room-1', 'client-1', ws1);
    assert.equal(manager.clientCount('room-1'), 1);

    const ws2 = mockWs();
    manager.join('room-1', 'client-2', ws2);
    assert.equal(manager.clientCount('room-1'), 2);
  });

  // Test 15: hasIosClient() returns true when at least one client has deviceToken
  it('detects iOS client by deviceToken', () => {
    assert.equal(manager.hasIosClient('nonexistent'), false);

    const ws1 = mockWs();
    manager.join('room-1', 'client-1', ws1); // no deviceToken
    assert.equal(manager.hasIosClient('room-1'), false);

    const ws2 = mockWs();
    manager.join('room-1', 'client-2', ws2, 'apns-token-123');
    assert.equal(manager.hasIosClient('room-1'), true);
  });
});
