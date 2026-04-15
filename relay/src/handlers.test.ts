import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import type { WebSocket } from 'ws';
import type { RoomManager } from './rooms.js';

// Import after setting up -- handlers.ts is the module under test
const { parseMessage, handleMessage } = await import('./handlers.js');

// Helper: create a mock WebSocket
function createMockWs(): WebSocket & { _sent: string[] } {
  const sent: string[] = [];
  return {
    readyState: 1,
    send: mock.fn((data: string) => { sent.push(data); }),
    _sent: sent,
  } as unknown as WebSocket & { _sent: string[] };
}

// Helper: create a mock RoomManager
function createMockRoomManager(overrides: Partial<Record<keyof RoomManager, unknown>> = {}) {
  const mockClients = new Map();
  mockClients.set('client-1', { ws: createMockWs(), deviceToken: undefined });

  return {
    join: mock.fn(() => ({ id: 'room-1', clients: new Map(), lastActivity: Date.now() })),
    leave: mock.fn(),
    forward: mock.fn(),
    getRoom: mock.fn(() => ({
      id: 'room-1',
      clients: mockClients,
      deviceToken: 'token-123',
      lastActivity: Date.now(),
    })),
    clientCount: mock.fn(() => 1),
    hasIosClient: mock.fn(() => false),
    evict: mock.fn(),
    shutdown: mock.fn(),
    get roomCount() { return 1; },
    ...overrides,
  } as unknown as RoomManager;
}

describe('parseMessage', () => {
  it('Test 1: returns MessageEnvelope for valid { v: 1, type: "join", id: "uuid", payload: {} }', () => {
    const result = parseMessage(JSON.stringify({
      v: 1,
      type: 'join',
      id: '550e8400-e29b-41d4-a716-446655440000',
      payload: {},
    }));
    assert.ok(result);
    assert.equal(result!.v, 1);
    assert.equal(result!.type, 'join');
    assert.equal(result!.id, '550e8400-e29b-41d4-a716-446655440000');
    assert.deepEqual(result!.payload, {});
  });

  it('Test 2: returns null for missing v field', () => {
    const result = parseMessage(JSON.stringify({
      type: 'join',
      id: 'uuid-1',
      payload: {},
    }));
    assert.equal(result, null);
  });

  it('Test 3: returns null for v !== 1', () => {
    const result = parseMessage(JSON.stringify({
      v: 2,
      type: 'join',
      id: 'uuid-1',
      payload: {},
    }));
    assert.equal(result, null);
  });

  it('Test 4: returns null for missing type field', () => {
    const result = parseMessage(JSON.stringify({
      v: 1,
      id: 'uuid-1',
      payload: {},
    }));
    assert.equal(result, null);
  });

  it('Test 5: returns null for missing id field', () => {
    const result = parseMessage(JSON.stringify({
      v: 1,
      type: 'join',
      payload: {},
    }));
    assert.equal(result, null);
  });

  it('Test 6: returns null for non-JSON string', () => {
    const result = parseMessage('this is not json');
    assert.equal(result, null);
  });
});

describe('handleMessage', () => {
  let ws: WebSocket & { _sent: string[] };
  let roomManager: RoomManager;

  beforeEach(() => {
    ws = createMockWs();
    roomManager = createMockRoomManager();
  });

  it('Test 7: type "join" calls roomManager.join with roomId, clientId, ws, and deviceToken from payload', () => {
    const raw = JSON.stringify({
      v: 1,
      type: 'join',
      id: 'msg-1',
      payload: { deviceToken: 'ios-token-abc' },
    });

    handleMessage(raw, ws, 'room-1', 'client-1', roomManager);

    const joinMock = (roomManager.join as ReturnType<typeof mock.fn>);
    assert.equal(joinMock.mock.callCount(), 1);
    const args = joinMock.mock.calls[0].arguments;
    assert.equal(args[0], 'room-1');
    assert.equal(args[1], 'client-1');
    assert.equal(args[2], ws);
    assert.equal(args[3], 'ios-token-abc');
  });

  it('Test 8: type "join" sends back a joined confirmation with the message id', () => {
    const raw = JSON.stringify({
      v: 1,
      type: 'join',
      id: 'msg-join-1',
      payload: {},
    });

    handleMessage(raw, ws, 'room-1', 'client-1', roomManager);

    assert.equal(ws._sent.length, 1);
    const response = JSON.parse(ws._sent[0]);
    assert.equal(response.v, 1);
    assert.equal(response.type, 'joined');
    assert.equal(response.id, 'msg-join-1');
    assert.deepEqual(response.payload, { roomId: 'room-1' });
  });

  it('Test 9: type "register_token" updates room deviceToken via roomManager', () => {
    // Set up a mock room with a client
    const mockClient = { ws, deviceToken: undefined as string | undefined };
    const mockClients = new Map();
    mockClients.set('client-1', mockClient);
    const mockRoom = {
      id: 'room-1',
      clients: mockClients,
      deviceToken: undefined as string | undefined,
      lastActivity: Date.now(),
    };
    roomManager = createMockRoomManager({
      getRoom: mock.fn(() => mockRoom),
    });

    const raw = JSON.stringify({
      v: 1,
      type: 'register_token',
      id: 'msg-reg-1',
      payload: { deviceToken: 'new-ios-token' },
    });

    handleMessage(raw, ws, 'room-1', 'client-1', roomManager);

    assert.equal(mockClient.deviceToken, 'new-ios-token');
    assert.equal(mockRoom.deviceToken, 'new-ios-token');

    // Should send back token_registered
    assert.equal(ws._sent.length, 1);
    const response = JSON.parse(ws._sent[0]);
    assert.equal(response.type, 'token_registered');
    assert.equal(response.id, 'msg-reg-1');
  });

  it('Test 10: type "ping" sends back { v: 1, type: "pong", id: <same id>, payload: {} }', () => {
    const raw = JSON.stringify({
      v: 1,
      type: 'ping',
      id: 'ping-id-42',
      payload: {},
    });

    handleMessage(raw, ws, 'room-1', 'client-1', roomManager);

    assert.equal(ws._sent.length, 1);
    const response = JSON.parse(ws._sent[0]);
    assert.equal(response.v, 1);
    assert.equal(response.type, 'pong');
    assert.equal(response.id, 'ping-id-42');
    assert.deepEqual(response.payload, {});
  });

  it('Test 11: unknown type calls roomManager.forward with raw string', () => {
    // hasIosClient returns true so no push is triggered
    roomManager = createMockRoomManager({
      hasIosClient: mock.fn(() => true),
    });

    const raw = JSON.stringify({
      v: 1,
      type: 'code_request',
      id: 'msg-fwd-1',
      payload: { encrypted: 'blob-data' },
    });

    handleMessage(raw, ws, 'room-1', 'client-1', roomManager);

    const forwardMock = (roomManager.forward as ReturnType<typeof mock.fn>);
    assert.equal(forwardMock.mock.callCount(), 1);
    const args = forwardMock.mock.calls[0].arguments;
    assert.equal(args[0], 'room-1');
    assert.equal(args[1], 'client-1');
    assert.equal(args[2], raw);
  });

  it('Test 12: unknown type with no iOS client in room calls sendWakeupPush', async () => {
    // hasIosClient returns false, room has deviceToken
    roomManager = createMockRoomManager({
      hasIosClient: mock.fn(() => false),
      getRoom: mock.fn(() => ({
        id: 'room-1',
        clients: new Map(),
        deviceToken: 'push-token-xyz',
        lastActivity: Date.now(),
      })),
    });

    // Import apns module to set up mock
    const apnsModule = await import('./apns.js');
    const pushCalls: Array<{ deviceToken: string; roomId: string; requestId: string }> = [];
    apnsModule._setApnsClientForTesting({
      send: mock.fn(async (notification: { deviceToken: string }) => {
        pushCalls.push({
          deviceToken: notification.deviceToken,
          roomId: 'room-1',
          requestId: 'msg-push-1',
        });
        return notification;
      }),
    } as any);

    const raw = JSON.stringify({
      v: 1,
      type: 'code_request',
      id: 'msg-push-1',
      payload: { encrypted: 'blob' },
    });

    handleMessage(raw, ws, 'room-1', 'client-1', roomManager);

    // Give the async push call time to resolve
    await new Promise((resolve) => setTimeout(resolve, 50));

    // Verify sendWakeupPush was called (via the mock client's send)
    const sendMock = (apnsModule.getApnsClient() as any)?.send as ReturnType<typeof mock.fn>;
    assert.ok(sendMock, 'APNs client should have been set for testing');
    assert.equal(sendMock.mock.callCount(), 1);

    apnsModule._resetForTesting();
  });

  it('Test 13: unknown type with iOS client present does NOT call sendWakeupPush', async () => {
    // hasIosClient returns true -- no push should be sent
    roomManager = createMockRoomManager({
      hasIosClient: mock.fn(() => true),
    });

    const apnsModule = await import('./apns.js');
    apnsModule._setApnsClientForTesting({
      send: mock.fn(async () => ({})),
    } as any);

    const raw = JSON.stringify({
      v: 1,
      type: 'code_request',
      id: 'msg-no-push',
      payload: { encrypted: 'blob' },
    });

    handleMessage(raw, ws, 'room-1', 'client-1', roomManager);

    await new Promise((resolve) => setTimeout(resolve, 50));

    // sendWakeupPush should NOT have been called because iOS client is present
    const sendMock = (apnsModule.getApnsClient() as any)?.send as ReturnType<typeof mock.fn>;
    assert.equal(sendMock.mock.callCount(), 0, 'Should not call sendWakeupPush when iOS client is present');

    apnsModule._resetForTesting();
  });

  it('Test 14: null parseMessage result sends error with code "invalid_message"', () => {
    handleMessage('not valid json', ws, 'room-1', 'client-1', roomManager);

    assert.equal(ws._sent.length, 1);
    const response = JSON.parse(ws._sent[0]);
    assert.equal(response.v, 1);
    assert.equal(response.type, 'error');
    assert.equal(response.payload.code, 'invalid_message');
    assert.ok(response.payload.message, 'Error should have a message string');
  });

  it('Test 15: error response follows D-02 format: { v: 1, type: "error", id: <uuid>, payload: { code, message } }', () => {
    handleMessage('}{garbage', ws, 'room-1', 'client-1', roomManager);

    assert.equal(ws._sent.length, 1);
    const response = JSON.parse(ws._sent[0]);
    assert.equal(response.v, 1);
    assert.equal(response.type, 'error');
    assert.ok(response.id, 'Error should have an id field');
    assert.ok(typeof response.id === 'string' && response.id.length > 0, 'id should be a non-empty string');
    assert.equal(typeof response.payload, 'object');
    assert.equal(response.payload.code, 'invalid_message');
    assert.equal(typeof response.payload.message, 'string');
  });
});
