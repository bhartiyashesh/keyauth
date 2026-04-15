import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import os from 'os';
import path from 'path';

// We will test createApnsClient config validation directly,
// and sendWakeupPush via dependency injection (_setApnsClientForTesting).
// The module exposes _setApnsClientForTesting and _resetForTesting for test hooks.

// Dynamic import to get fresh module per describe block
let apnsModule: typeof import('./apns.js');

describe('APNs Client', () => {
  let tmpKeyFile: string;

  beforeEach(async () => {
    process.env.APNS_TEAM_ID = 'TESTTEAM';
    process.env.APNS_KEY_ID = 'TESTKEY';
    process.env.APNS_KEY = Buffer.from('fake-key-content').toString('base64');

    // Create a temp p8 file for APNS_KEY_PATH tests
    tmpKeyFile = path.join(os.tmpdir(), `test-apns-key-${Date.now()}.p8`);
    fs.writeFileSync(tmpKeyFile, 'fake-key-from-file');

    apnsModule = await import('./apns.js');
    apnsModule._resetForTesting();
  });

  afterEach(() => {
    delete process.env.APNS_TEAM_ID;
    delete process.env.APNS_KEY_ID;
    delete process.env.APNS_KEY;
    delete process.env.APNS_KEY_PATH;
    delete process.env.APNS_ENVIRONMENT;
    apnsModule._resetForTesting();
    try { fs.unlinkSync(tmpKeyFile); } catch {}
  });

  it('Test 1: createApnsClient() with valid config returns an ApnsClient instance', () => {
    const client = apnsModule.createApnsClient();
    assert.ok(client, 'createApnsClient should return a truthy value');
    assert.equal(typeof client.send, 'function', 'Client should have a send method');
  });

  it('Test 2: createApnsClient() throws descriptive error when APNS_TEAM_ID is missing', () => {
    delete process.env.APNS_TEAM_ID;
    assert.throws(
      () => apnsModule.createApnsClient(),
      (err: Error) => err.message.includes('APNS_TEAM_ID'),
      'Error should mention APNS_TEAM_ID'
    );
  });

  it('Test 3: createApnsClient() throws descriptive error when APNS_KEY_ID is missing', () => {
    delete process.env.APNS_KEY_ID;
    assert.throws(
      () => apnsModule.createApnsClient(),
      (err: Error) => err.message.includes('APNS_KEY_ID'),
      'Error should mention APNS_KEY_ID'
    );
  });

  it('Test 4: createApnsClient() throws descriptive error when neither APNS_KEY nor APNS_KEY_PATH is set', () => {
    delete process.env.APNS_KEY;
    delete process.env.APNS_KEY_PATH;
    assert.throws(
      () => apnsModule.createApnsClient(),
      (err: Error) => err.message.includes('APNS_KEY') && err.message.includes('APNS_KEY_PATH'),
      'Error should mention both APNS_KEY and APNS_KEY_PATH'
    );
  });

  it('Test 5: createApnsClient() prefers APNS_KEY (base64) over APNS_KEY_PATH when both are set', () => {
    process.env.APNS_KEY_PATH = tmpKeyFile;
    // If APNS_KEY is set, it should be preferred -- the client should init without reading the file
    const client = apnsModule.createApnsClient();
    assert.ok(client, 'Should create client when both APNS_KEY and APNS_KEY_PATH are set');
    // Verify it used the base64 key by checking the client's signingKey is a Buffer
    assert.ok(
      Buffer.isBuffer(client.signingKey),
      'signingKey should be a Buffer when APNS_KEY (base64) is used'
    );
  });

  it('Test 6: createApnsClient() uses sandbox host when APNS_ENVIRONMENT=sandbox', () => {
    process.env.APNS_ENVIRONMENT = 'sandbox';
    const client = apnsModule.createApnsClient();
    assert.equal(client.host, 'api.sandbox.push.apple.com');
  });

  it('Test 7: createApnsClient() uses production host when APNS_ENVIRONMENT is unset (default production)', () => {
    delete process.env.APNS_ENVIRONMENT;
    const client = apnsModule.createApnsClient();
    assert.equal(client.host, 'api.push.apple.com');
  });

  it('Test 8: sendWakeupPush() creates Notification with correct alert title "KeyAuth", body "Approve 2FA request", sound "default", and data containing roomId and requestId', async () => {
    const sentNotifications: Array<{ deviceToken: string; options: Record<string, unknown> }> = [];
    const mockClient = {
      send: mock.fn(async (notification: { deviceToken: string; options: Record<string, unknown> }) => {
        sentNotifications.push(notification);
        return notification;
      }),
    };

    apnsModule._setApnsClientForTesting(mockClient as any);

    await apnsModule.sendWakeupPush('device-token-abc', 'room-42', 'req-uuid-1');

    assert.equal(sentNotifications.length, 1);
    const notification = sentNotifications[0];
    assert.equal(notification.deviceToken, 'device-token-abc');
    assert.deepEqual(notification.options.alert, {
      title: 'KeyAuth',
      body: 'Approve 2FA request',
    });
    assert.deepEqual(notification.options.data, {
      roomId: 'room-42',
      requestId: 'req-uuid-1',
    });
    assert.equal(notification.options.sound, 'default');
  });

  it('Test 9: sendWakeupPush() returns without error on successful send (mock ApnsClient)', async () => {
    const mockClient = {
      send: mock.fn(async () => ({})),
    };
    apnsModule._setApnsClientForTesting(mockClient as any);

    // Should not throw
    await assert.doesNotReject(
      () => apnsModule.sendWakeupPush('device-token-abc', 'room-42', 'req-uuid-1')
    );
    assert.equal(mockClient.send.mock.callCount(), 1);
  });

  it('Test 10: sendWakeupPush() logs warning and does not throw on BadDeviceToken error', async () => {
    const badTokenError = Object.assign(new Error('BadDeviceToken'), { reason: 'BadDeviceToken' });
    const mockClient = {
      send: mock.fn(async () => { throw badTokenError; }),
    };
    apnsModule._setApnsClientForTesting(mockClient as any);

    // Should NOT throw -- push errors are caught internally
    await assert.doesNotReject(
      () => apnsModule.sendWakeupPush('device-token-abc', 'room-42', 'req-uuid-1')
    );
  });
});
