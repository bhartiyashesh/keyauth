import {
  deriveSharedKey,
  seal,
  open,
  base64ToUint8Array,
  uint8ArrayToBase64,
} from '../lib/crypto';
import { createEnvelope } from '../lib/types';
import type { MessageEnvelope, PairingData } from '../lib/types';
import {
  savePairingData,
  loadPairingData,
  clearPairingData,
  setSessionState,
  getSessionState,
} from '../lib/storage';

const RELAY_URL = 'wss://cooperative-respect-production-29f8.up.railway.app';
const KEEPALIVE_MS = 20_000;
const RECONNECT_DELAY_MS = 3_000;

let ws: WebSocket | null = null;
let keepaliveInterval: ReturnType<typeof setInterval> | null = null;
let reconnectTimeout: ReturnType<typeof setTimeout> | null = null;

// ---------- Connection State ----------

type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'code_received' | 'unpaired';

async function setConnectionState(state: ConnectionState): Promise<void> {
  await setSessionState({ connectionState: state });
}

// ---------- WebSocket Management ----------

function connect(roomId: string, relayURL: string): void {
  // Clean up any existing connection
  disconnect();

  setConnectionState('connecting');

  const url = `${relayURL}?roomId=${encodeURIComponent(roomId)}`;
  ws = new WebSocket(url);

  ws.onopen = () => {
    // Send join envelope
    const joinMsg = createEnvelope('join');
    ws?.send(JSON.stringify(joinMsg));

    // Start 20-second keepalive pings
    keepaliveInterval = setInterval(() => {
      if (ws?.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(createEnvelope('ping')));
      }
    }, KEEPALIVE_MS);

    setConnectionState('connected');
  };

  ws.onmessage = (event: MessageEvent) => {
    handleRelayMessage(event.data as string);
  };

  ws.onclose = () => {
    stopKeepalive();
    setConnectionState('disconnected');
    scheduleReconnect();
  };

  ws.onerror = (event: Event) => {
    console.error('[KeyAuth] WebSocket error:', event);
    // onclose will fire after onerror and handle cleanup
  };
}

function disconnect(): void {
  clearReconnect();
  stopKeepalive();
  if (ws) {
    ws.onclose = null; // Prevent reconnect on intentional disconnect
    ws.close();
    ws = null;
  }
}

function stopKeepalive(): void {
  if (keepaliveInterval !== null) {
    clearInterval(keepaliveInterval);
    keepaliveInterval = null;
  }
}

function clearReconnect(): void {
  if (reconnectTimeout !== null) {
    clearTimeout(reconnectTimeout);
    reconnectTimeout = null;
  }
}

async function scheduleReconnect(): Promise<void> {
  clearReconnect();
  const pairing = await loadPairingData();
  if (pairing) {
    reconnectTimeout = setTimeout(() => {
      connect(pairing.roomId, pairing.relayURL);
    }, RECONNECT_DELAY_MS);
    return;
  }
  // Also reconnect during active pairing (before pairing is saved to local storage)
  const pending = await getSessionState<{ roomId: string; privateKey: string }>('pendingPairing');
  if (pending) {
    console.log('[KeyAuth] Reconnecting for pending pairing, room:', pending.roomId);
    reconnectTimeout = setTimeout(() => {
      connect(pending.roomId, RELAY_URL);
    }, RECONNECT_DELAY_MS);
  }
}

// ---------- Message Routing ----------

async function handleRelayMessage(raw: string): Promise<void> {
  console.log('[KeyAuth] Relay message received:', raw.substring(0, 200));
  let msg: MessageEnvelope;
  try {
    msg = JSON.parse(raw);
  } catch {
    console.warn('[KeyAuth] Received non-JSON message from relay');
    return;
  }

  console.log('[KeyAuth] Parsed message type:', msg.type);

  if (msg.v !== 1) {
    console.warn('[KeyAuth] Unknown protocol version:', msg.v);
    return;
  }

  switch (msg.type) {
    case 'joined':
      console.log('[KeyAuth] Joined room successfully');
      break;

    case 'pong':
      // Keepalive response -- no-op
      break;

    case 'error':
      console.error('[KeyAuth] Relay error:', msg.payload.code, msg.payload.message);
      break;

    case 'pairing_ack':
      await handlePairingAck(msg);
      break;

    case 'code_response':
      await handleCodeResponse(msg);
      break;

    default:
      // Opaque forwarded message from iOS
      await handleForwardedMessage(msg);
      break;
  }
}

async function handlePairingAck(msg: MessageEnvelope): Promise<void> {
  console.log('[KeyAuth] handlePairingAck called, payload:', JSON.stringify(msg.payload));
  const peerPublicKeyBase64 = msg.payload.publicKey as string | undefined;
  if (peerPublicKeyBase64) {
    console.log('[KeyAuth] Got peer public key, completing pairing...');
    await completePairing(peerPublicKeyBase64);
  } else {
    console.warn('[KeyAuth] pairing_ack missing publicKey in payload');
  }
}

async function handleCodeResponse(msg: MessageEnvelope): Promise<void> {
  const pairing = await loadPairingData();
  if (!pairing) {
    console.warn('[KeyAuth] Received code_response but no pairing data');
    return;
  }

  const encryptedBase64 = msg.payload.data as string | undefined;
  if (!encryptedBase64) {
    console.warn('[KeyAuth] code_response missing payload.data');
    return;
  }

  try {
    const encrypted = base64ToUint8Array(encryptedBase64);
    const sharedKey = base64ToUint8Array(pairing.sharedKey);
    const decrypted = open(encrypted, sharedKey);
    const decoded = new TextDecoder().decode(decrypted);
    const { code, requestId } = JSON.parse(decoded);

    await setSessionState({
      lastCode: code,
      lastRequestId: requestId,
      codeReceivedAt: Date.now(),
    });
    await setConnectionState('code_received');
  } catch (err) {
    console.error('[KeyAuth] Failed to decrypt code_response:', err);
  }
}

async function handleForwardedMessage(msg: MessageEnvelope): Promise<void> {
  // Check if this is a message with encrypted data (potential pairing ack from iOS)
  if (msg.payload.data && typeof msg.payload.data === 'string') {
    // If we have a pending pairing, this is likely iOS acknowledging the pairing
    const pending = await getSessionState<{ roomId: string; privateKey: string }>('pendingPairing');
    if (pending) {
      // iOS sends its public key in the pairing_ack message
      // If payload has publicKey, use that for pairing
      const peerPublicKeyBase64 = msg.payload.publicKey as string | undefined;
      if (peerPublicKeyBase64) {
        await completePairing(peerPublicKeyBase64);
      }
    }
  }
}

// ---------- Pairing Flow ----------

async function completePairing(peerPublicKeyBase64: string): Promise<void> {
  const pending = await getSessionState<{ roomId: string; privateKey: string }>('pendingPairing');
  if (!pending) {
    console.warn('[KeyAuth] No pending pairing to complete');
    return;
  }

  try {
    const privateKey = base64ToUint8Array(pending.privateKey);
    const peerPublicKey = base64ToUint8Array(peerPublicKeyBase64);
    const sharedKey = deriveSharedKey(privateKey, peerPublicKey);

    const pairingData: PairingData = {
      roomId: pending.roomId,
      relayURL: RELAY_URL,
      sharedKey: uint8ArrayToBase64(sharedKey),
      pairedAt: Date.now(),
    };

    await savePairingData(pairingData);

    // Clear pending pairing (privateKey no longer needed)
    await chrome.storage.session.remove('pendingPairing');

    await setConnectionState('connected');
    console.log('[KeyAuth] Pairing completed successfully');
  } catch (err) {
    console.error('[KeyAuth] Pairing completion failed:', err);
  }
}

// ---------- Message Handlers from Popup ----------

async function handlePopupMessage(
  message: { type: string; [key: string]: unknown },
  sendResponse: (response?: unknown) => void,
): Promise<void> {
    switch (message.type) {
        case 'start_pairing': {
          const { roomId, relayURL } = message as { type: string; roomId: string; relayURL: string };
          connect(roomId, relayURL);
          sendResponse({ ok: true });
          break;
        }

        case 'complete_pairing': {
          const { peerPublicKeyBase64 } = message as { type: string; peerPublicKeyBase64: string };
          await completePairing(peerPublicKeyBase64);
          sendResponse({ ok: true });
          break;
        }

        case 'request_code': {
          const pairing = await loadPairingData();
          if (!pairing) {
            sendResponse({ ok: false, error: 'Not paired' });
            break;
          }

          if (!ws || ws.readyState !== WebSocket.OPEN) {
            sendResponse({ ok: false, error: 'Not connected' });
            break;
          }

          // Get current tab domain for account matching on the phone
          let domain = '';
          try {
            const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
            if (tab?.url) {
              domain = new URL(tab.url).hostname.replace(/^www\./, '');
            }
          } catch {
            // Tabs API may fail on chrome:// pages -- proceed without domain
          }

          const codeRequest = {
            id: crypto.randomUUID(),
            issuer: '',
            label: '',
            domain,
          };

          try {
            const sharedKey = base64ToUint8Array(pairing.sharedKey);
            const plaintext = new TextEncoder().encode(JSON.stringify(codeRequest));
            const encrypted = seal(plaintext, sharedKey);
            const envelope = createEnvelope('code_request', {
              data: uint8ArrayToBase64(encrypted),
            });
            ws.send(JSON.stringify(envelope));
            sendResponse({ ok: true, requestId: codeRequest.id });
          } catch (err) {
            console.error('[KeyAuth] Failed to send code request:', err);
            sendResponse({ ok: false, error: 'Encryption failed' });
          }
          break;
        }

        case 'unpair': {
          disconnect();
          await clearPairingData();
          await chrome.storage.session.remove('pendingPairing');
          await setConnectionState('unpaired');
          sendResponse({ ok: true });
          break;
        }

        case 'get_state': {
          const pairing = await loadPairingData();
          const connectionState = await getSessionState<ConnectionState>('connectionState');
          const lastCode = await getSessionState<string>('lastCode');
          const codeReceivedAt = await getSessionState<number>('codeReceivedAt');
          sendResponse({
            paired: !!pairing,
            connectionState: connectionState ?? (pairing ? 'disconnected' : 'unpaired'),
            lastCode,
            codeReceivedAt,
          });
          break;
        }

        default:
          sendResponse({ ok: false, error: 'Unknown message type' });
      }
}

// ---------- Service Worker Startup ----------

export default defineBackground(() => {
  console.log('[KeyAuth] Service worker started');

  // Register message listener inside defineBackground so WXT picks it up
  chrome.runtime.onMessage.addListener(
    (
      message: { type: string; [key: string]: unknown },
      _sender: chrome.runtime.MessageSender,
      sendResponse: (response?: unknown) => void,
    ) => {
      handlePopupMessage(message, sendResponse).catch((err) => {
        console.error('[KeyAuth] Message handler error:', err);
        sendResponse({ ok: false, error: String(err) });
      });
      return true; // async response
    },
  );

  // Auto-reconnect if already paired or mid-pairing
  loadPairingData().then(async (pairing) => {
    if (pairing) {
      console.log('[KeyAuth] Found existing pairing, reconnecting...');
      connect(pairing.roomId, pairing.relayURL);
    } else {
      // Check for in-progress pairing (service worker restarted mid-pairing)
      const pending = await getSessionState<{ roomId: string; privateKey: string }>('pendingPairing');
      if (pending) {
        console.log('[KeyAuth] Found pending pairing, reconnecting to room:', pending.roomId);
        connect(pending.roomId, RELAY_URL);
      } else {
        setConnectionState('unpaired');
      }
    }
  });
});
