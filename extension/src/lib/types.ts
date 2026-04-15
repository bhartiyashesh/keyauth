/** Must match relay/src/types.ts MessageEnvelope */
export interface MessageEnvelope {
  v: 1;
  type: string;
  id: string;
  payload: Record<string, unknown>;
}

/** Stored in chrome.storage.local after successful pairing */
export interface PairingData {
  roomId: string;
  relayURL: string;
  sharedKey: string;    // base64-encoded 32-byte derived symmetric key
  pairedAt: number;     // timestamp
}

/** Encrypted request sent to iOS (inside payload.data as base64) */
export interface CodeRequest {
  id: string;           // correlation ID echoed in response
  issuer: string;       // e.g., "GitHub" -- shown on iOS approval sheet
  label: string;        // e.g., "user@email.com"
}

/** Encrypted response from iOS (inside payload.data as base64) */
export interface CodeResponse {
  code: string;         // 6-digit TOTP code
  requestId: string;    // correlation ID from request
}

/**
 * Create a relay message envelope.
 * Matches the relay protocol: { v: 1, type, id: UUID, payload }.
 */
export function createEnvelope(type: string, payload: Record<string, unknown> = {}): MessageEnvelope {
  return { v: 1, type, id: crypto.randomUUID(), payload };
}
