import { x25519 } from '@noble/curves/ed25519.js';
import { chacha20poly1305 } from '@noble/ciphers/chacha.js';
import { randomBytes } from '@noble/ciphers/utils.js';
import { hkdf } from '@noble/hashes/hkdf.js';
import { sha256 } from '@noble/hashes/sha2.js';

const HKDF_SALT = new Uint8Array(0);                         // matches CryptoKit Data()
const HKDF_INFO = new TextEncoder().encode('KeyAuth-E2E');    // matches Data("KeyAuth-E2E".utf8)

/**
 * Generate an X25519 keypair for pairing.
 * Returns { privateKey: Uint8Array(32), publicKey: Uint8Array(32) }.
 */
export function generateKeyPair(): { privateKey: Uint8Array; publicKey: Uint8Array } {
  const privateKey = x25519.utils.randomSecretKey();
  const publicKey = x25519.getPublicKey(privateKey);
  return { privateKey, publicKey };
}

/**
 * Derive a shared symmetric key via X25519 key agreement + HKDF-SHA256.
 * Must match iOS CryptoBoxManager.deriveSharedKey exactly:
 *   salt = Data()  (empty)
 *   sharedInfo = Data("KeyAuth-E2E".utf8)
 *   outputByteCount = 32
 */
export function deriveSharedKey(privateKey: Uint8Array, peerPublicKey: Uint8Array): Uint8Array {
  const sharedSecret = x25519.getSharedSecret(privateKey, peerPublicKey);
  return hkdf(sha256, sharedSecret, HKDF_SALT, HKDF_INFO, 32);
}

/**
 * Encrypt plaintext using ChaCha20-Poly1305.
 * Returns CryptoKit-compatible combined format: nonce(12) || ciphertext || tag(16).
 *
 * Noble-ciphers encrypt() returns ciphertext||tag WITHOUT the nonce,
 * so we manually prepend the 12-byte nonce to match CryptoKit SealedBox.combined.
 */
export function seal(plaintext: Uint8Array, sharedKey: Uint8Array): Uint8Array {
  const nonce = randomBytes(12);
  const cipher = chacha20poly1305(sharedKey, nonce);
  const ciphertextWithTag = cipher.encrypt(plaintext);
  // Prepend nonce to match CryptoKit SealedBox.combined: nonce(12) || ciphertext || tag(16)
  const combined = new Uint8Array(12 + ciphertextWithTag.length);
  combined.set(nonce, 0);
  combined.set(ciphertextWithTag, 12);
  return combined;
}

/**
 * Decrypt CryptoKit-compatible combined format: nonce(12) || ciphertext || tag(16).
 * Strips the first 12 bytes as nonce, passes rest to ChaCha20-Poly1305 decrypt.
 */
export function open(combined: Uint8Array, sharedKey: Uint8Array): Uint8Array {
  const nonce = combined.slice(0, 12);
  const ciphertextWithTag = combined.slice(12);
  const cipher = chacha20poly1305(sharedKey, nonce);
  return cipher.decrypt(ciphertextWithTag);
}

/**
 * Convert Uint8Array to base64 string.
 * Used for encoding public keys and encrypted payloads in relay messages.
 */
export function uint8ArrayToBase64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}

/**
 * Convert base64 string back to Uint8Array.
 * Used for decoding public keys and encrypted payloads from relay messages.
 */
export function base64ToUint8Array(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}
