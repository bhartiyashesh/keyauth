import { ApnsClient, Notification } from 'apns2';
import fs from 'fs';
import logger from './logger.js';

let apnsClient: ApnsClient | null = null;

export function createApnsClient(): ApnsClient {
  const teamId = process.env.APNS_TEAM_ID;
  const keyId = process.env.APNS_KEY_ID;

  if (!teamId) throw new Error('APNS_TEAM_ID environment variable is required');
  if (!keyId) throw new Error('APNS_KEY_ID environment variable is required');

  // Support both base64 env var and file path (Railway uses env var, local dev uses file)
  let signingKey: string | Buffer;
  if (process.env.APNS_KEY) {
    signingKey = Buffer.from(process.env.APNS_KEY, 'base64');
  } else if (process.env.APNS_KEY_PATH) {
    signingKey = fs.readFileSync(process.env.APNS_KEY_PATH);
  } else {
    throw new Error('Either APNS_KEY (base64) or APNS_KEY_PATH environment variable is required');
  }

  const host = process.env.APNS_ENVIRONMENT === 'sandbox'
    ? 'api.sandbox.push.apple.com'
    : 'api.push.apple.com';

  apnsClient = new ApnsClient({
    team: teamId,
    keyId: keyId,
    signingKey: signingKey,
    defaultTopic: 'com.keyauth.app',
    host: host,
  });

  logger.info({ keyId, host }, 'APNs client initialized');
  return apnsClient;
}

export async function sendWakeupPush(
  deviceToken: string,
  roomId: string,
  requestId: string
): Promise<void> {
  if (!apnsClient) {
    logger.warn('APNs client not initialized -- skipping push');
    return;
  }

  const notification = new Notification(deviceToken, {
    alert: {
      title: 'KeyAuth',
      body: 'Approve 2FA request',
    },
    data: { roomId, requestId },
    sound: 'default',
  });

  try {
    await apnsClient.send(notification);
    logger.info({ roomId, requestId }, 'APNs wakeup push sent');
  } catch (err: unknown) {
    const error = err as Error & { reason?: string };
    if (error.reason === 'BadDeviceToken' || error.reason === 'Unregistered') {
      logger.warn({ deviceToken: deviceToken.slice(0, 8) + '...', reason: error.reason }, 'Device token invalid -- client must re-register');
    } else {
      logger.error({ err, roomId }, 'APNs push failed');
    }
    // Do NOT throw -- push failure should not crash the relay or block message forwarding
  }
}

export function getApnsClient(): ApnsClient | null {
  return apnsClient;
}

/** Test-only: inject a mock client */
export function _setApnsClientForTesting(client: ApnsClient): void {
  apnsClient = client;
}

/** Test-only: reset module state */
export function _resetForTesting(): void {
  apnsClient = null;
}
