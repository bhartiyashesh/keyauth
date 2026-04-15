import { describe, it, expect } from 'vitest';
import {
  generateKeyPair,
  deriveSharedKey,
  seal,
  open,
  uint8ArrayToBase64,
  base64ToUint8Array,
} from './crypto';
import { createEnvelope } from './types';

describe('CryptoBox', () => {
  describe('generateKeyPair', () => {
    it('returns privateKey and publicKey as 32-byte Uint8Arrays', () => {
      const { privateKey, publicKey } = generateKeyPair();
      expect(privateKey).toBeInstanceOf(Uint8Array);
      expect(publicKey).toBeInstanceOf(Uint8Array);
      expect(privateKey.length).toBe(32);
      expect(publicKey.length).toBe(32);
    });
  });

  describe('seal and open round-trip', () => {
    it('returns original plaintext after seal then open', () => {
      const sharedKey = new Uint8Array(32);
      crypto.getRandomValues(sharedKey);

      const plaintext = new TextEncoder().encode('Hello, KeyAuth!');
      const combined = seal(plaintext, sharedKey);
      const decrypted = open(combined, sharedKey);

      expect(decrypted).toEqual(plaintext);
    });

    it('round-trips arbitrary binary data', () => {
      const sharedKey = new Uint8Array(32);
      crypto.getRandomValues(sharedKey);

      const plaintext = new Uint8Array(256);
      crypto.getRandomValues(plaintext);

      const combined = seal(plaintext, sharedKey);
      const decrypted = open(combined, sharedKey);

      expect(decrypted).toEqual(plaintext);
    });
  });

  describe('seal wire format', () => {
    it('output length equals 12 + plaintext.length + 16 (nonce + ciphertext + tag)', () => {
      const sharedKey = new Uint8Array(32);
      crypto.getRandomValues(sharedKey);

      const plaintext = new TextEncoder().encode('test payload');
      const combined = seal(plaintext, sharedKey);

      expect(combined.length).toBe(12 + plaintext.length + 16);
    });

    it('first 12 bytes differ between two calls (random nonce)', () => {
      const sharedKey = new Uint8Array(32);
      crypto.getRandomValues(sharedKey);

      const plaintext = new TextEncoder().encode('same input');
      const combined1 = seal(plaintext, sharedKey);
      const combined2 = seal(plaintext, sharedKey);

      const nonce1 = combined1.slice(0, 12);
      const nonce2 = combined2.slice(0, 12);

      // Nonces should differ (random 12 bytes)
      const same = nonce1.every((byte, i) => byte === nonce2[i]);
      expect(same).toBe(false);
    });
  });

  describe('deriveSharedKey', () => {
    it('produces a 32-byte key from known keypair', () => {
      const alice = generateKeyPair();
      const bob = generateKeyPair();

      const sharedKeyAlice = deriveSharedKey(alice.privateKey, bob.publicKey);
      const sharedKeyBob = deriveSharedKey(bob.privateKey, alice.publicKey);

      expect(sharedKeyAlice).toBeInstanceOf(Uint8Array);
      expect(sharedKeyAlice.length).toBe(32);
      // Both sides derive the same shared key
      expect(sharedKeyAlice).toEqual(sharedKeyBob);
    });
  });

  describe('base64 round-trip', () => {
    it('uint8ArrayToBase64 and base64ToUint8Array round-trip correctly', () => {
      const original = new Uint8Array([0, 1, 127, 128, 255, 42, 99]);
      const base64 = uint8ArrayToBase64(original);
      const restored = base64ToUint8Array(base64);

      expect(restored).toEqual(original);
    });

    it('handles empty array', () => {
      const original = new Uint8Array(0);
      const base64 = uint8ArrayToBase64(original);
      const restored = base64ToUint8Array(base64);

      expect(restored).toEqual(original);
    });

    it('handles 32-byte key', () => {
      const key = new Uint8Array(32);
      crypto.getRandomValues(key);
      const base64 = uint8ArrayToBase64(key);
      const restored = base64ToUint8Array(base64);

      expect(restored).toEqual(key);
    });
  });
});

describe('createEnvelope', () => {
  it('produces { v: 1, type, id: string, payload }', () => {
    const envelope = createEnvelope('code_request', { data: 'test' });

    expect(envelope.v).toBe(1);
    expect(envelope.type).toBe('code_request');
    expect(typeof envelope.id).toBe('string');
    expect(envelope.id.length).toBeGreaterThan(0);
    expect(envelope.payload).toEqual({ data: 'test' });
  });

  it('generates unique ids', () => {
    const e1 = createEnvelope('test');
    const e2 = createEnvelope('test');
    expect(e1.id).not.toBe(e2.id);
  });

  it('defaults to empty payload', () => {
    const envelope = createEnvelope('ping');
    expect(envelope.payload).toEqual({});
  });
});
