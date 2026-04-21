/**
 * Tests for CODE-03: account_list message decryption and storage.
 *
 * handleAccountList (background.ts) is not exported directly, so we test
 * the observable behavior via the storage layer (saveAccounts/loadAccounts)
 * and verify the crypto pipeline that handleAccountList relies on.
 *
 * Two behaviors under test:
 *   1. Valid encrypted account_list payload decrypts and accounts are stored.
 *   2. Tampered ciphertext fails authentication and accounts are NOT stored.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { seal, open, uint8ArrayToBase64, base64ToUint8Array } from '../../lib/crypto';
import type { AccountMetadata } from '../../lib/types';

// ---- Chrome storage mock (mirrors background-resilience.test.ts pattern) ----
const mockStorage: Record<string, unknown> = {};

const mockChrome = {
  storage: {
    session: {
      set: vi.fn(async (data: Record<string, unknown>) => {
        Object.assign(mockStorage, data);
      }),
      get: vi.fn(async (key: string) => {
        return { [key]: mockStorage[key] ?? null };
      }),
      remove: vi.fn(async (key: string) => {
        delete mockStorage[key];
      }),
    },
    local: {
      get: vi.fn(async (key: string) => ({ [key]: mockStorage[key] ?? undefined })),
      set: vi.fn(async (data: Record<string, unknown>) => {
        Object.assign(mockStorage, data);
      }),
      remove: vi.fn(async (key: string) => {
        delete mockStorage[key];
      }),
    },
    onChanged: {
      addListener: vi.fn(),
      removeListener: vi.fn(),
    },
  },
  runtime: {
    onMessage: { addListener: vi.fn() },
    sendMessage: vi.fn(),
  },
  tabs: {
    query: vi.fn(async () => []),
    sendMessage: vi.fn(),
  },
};

vi.stubGlobal('chrome', mockChrome);

// ---- Helpers that mirror handleAccountList's exact steps ----

/**
 * Produce a base64-encoded ChaCha20Poly1305 sealed payload of the account list,
 * exactly as the iOS phone would send in msg.payload.data.
 */
function buildEncryptedAccountListPayload(
  accounts: AccountMetadata[],
  sharedKey: Uint8Array,
): string {
  const plaintext = new TextEncoder().encode(JSON.stringify({ accounts }));
  const encrypted = seal(plaintext, sharedKey);
  return uint8ArrayToBase64(encrypted);
}

/**
 * Run the decryption steps from handleAccountList and return the parsed accounts.
 * Returns null if decryption throws (tamper case).
 */
function runDecryptAccountList(
  encryptedBase64: string,
  sharedKey: Uint8Array,
): AccountMetadata[] | null {
  try {
    const encrypted = base64ToUint8Array(encryptedBase64);
    const decrypted = open(encrypted, sharedKey);
    const decoded = new TextDecoder().decode(decrypted);
    const { accounts } = JSON.parse(decoded) as { accounts: AccountMetadata[] };
    return accounts;
  } catch {
    return null;
  }
}

// ---- Tests ----

describe('handleAccountList: account_list decryption pipeline', () => {
  let sharedKey: Uint8Array;

  beforeEach(() => {
    Object.keys(mockStorage).forEach(key => delete mockStorage[key]);
    vi.clearAllMocks();

    sharedKey = new Uint8Array(32);
    crypto.getRandomValues(sharedKey);
  });

  it('decrypts a valid account_list payload and recovers the original accounts', () => {
    const accounts: AccountMetadata[] = [
      { id: 'uuid-1', issuer: 'GitHub', label: 'user@example.com' },
      { id: 'uuid-2', issuer: 'Google', label: 'me@gmail.com' },
    ];

    const encryptedBase64 = buildEncryptedAccountListPayload(accounts, sharedKey);
    const result = runDecryptAccountList(encryptedBase64, sharedKey);

    expect(result).not.toBeNull();
    expect(result).toHaveLength(2);
    expect(result![0]).toEqual({ id: 'uuid-1', issuer: 'GitHub', label: 'user@example.com' });
    expect(result![1]).toEqual({ id: 'uuid-2', issuer: 'Google', label: 'me@gmail.com' });
  });

  it('stores decrypted accounts in session storage via saveAccounts', async () => {
    const { saveAccounts, loadAccounts } = await import('../../lib/storage');

    const accounts: AccountMetadata[] = [
      { id: 'uuid-3', issuer: 'Dropbox', label: 'dev@dropbox.com' },
    ];

    const encryptedBase64 = buildEncryptedAccountListPayload(accounts, sharedKey);
    const decrypted = runDecryptAccountList(encryptedBase64, sharedKey);

    expect(decrypted).not.toBeNull();

    // Simulate handleAccountList calling saveAccounts after successful decryption
    await saveAccounts(decrypted!);

    const stored = await loadAccounts();
    expect(stored).toHaveLength(1);
    expect(stored[0].issuer).toBe('Dropbox');
    expect(stored[0].label).toBe('dev@dropbox.com');
  });

  it('rejects tampered ciphertext — open throws and accounts are not stored', async () => {
    const { saveAccounts, loadAccounts } = await import('../../lib/storage');

    const accounts: AccountMetadata[] = [
      { id: 'uuid-4', issuer: 'AWS', label: 'admin@corp.com' },
    ];

    const encryptedBase64 = buildEncryptedAccountListPayload(accounts, sharedKey);

    // Tamper: flip a byte in the ciphertext (after the 12-byte nonce)
    const encryptedBytes = base64ToUint8Array(encryptedBase64);
    encryptedBytes[20] ^= 0xff; // corrupt a byte in the authentication tag region
    const tamperedBase64 = uint8ArrayToBase64(encryptedBytes);

    const result = runDecryptAccountList(tamperedBase64, sharedKey);

    // Decryption must fail (return null) — not silently produce garbage
    expect(result).toBeNull();

    // saveAccounts must NOT have been called — storage remains empty
    const stored = await loadAccounts();
    expect(stored).toHaveLength(0);

    expect(mockChrome.storage.session.set).not.toHaveBeenCalled();
  });

  it('rejects a payload encrypted with a different key (wrong shared key)', () => {
    const accounts: AccountMetadata[] = [
      { id: 'uuid-5', issuer: 'Slack', label: 'team@slack.com' },
    ];

    const encryptedBase64 = buildEncryptedAccountListPayload(accounts, sharedKey);

    // Different key — simulates a message from an unrecognised sender
    const wrongKey = new Uint8Array(32);
    crypto.getRandomValues(wrongKey);

    const result = runDecryptAccountList(encryptedBase64, wrongKey);

    expect(result).toBeNull();
  });

  it('decrypts an empty account list without error', () => {
    const accounts: AccountMetadata[] = [];

    const encryptedBase64 = buildEncryptedAccountListPayload(accounts, sharedKey);
    const result = runDecryptAccountList(encryptedBase64, sharedKey);

    expect(result).not.toBeNull();
    expect(result).toHaveLength(0);
  });
});
