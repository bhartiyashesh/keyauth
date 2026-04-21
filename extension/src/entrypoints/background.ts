import {
  deriveSharedKey,
  seal,
  open,
  base64ToUint8Array,
  uint8ArrayToBase64,
} from '../lib/crypto';
import { createEnvelope } from '../lib/types';
import type { MessageEnvelope, PairingData, AccountMetadata } from '../lib/types';
import {
  savePairingData,
  loadPairingData,
  clearPairingData,
  saveAccounts,
  loadAccounts,
  clearAccounts,
  setSessionState,
  getSessionState,
} from '../lib/storage';

const RELAY_URL = 'wss://cooperative-respect-production-29f8.up.railway.app';
const KEEPALIVE_MS = 20_000;
const RECONNECT_BASE_MS = 1_000;
const RECONNECT_MAX_MS = 30_000;

let ws: WebSocket | null = null;
let keepaliveInterval: ReturnType<typeof setInterval> | null = null;
let reconnectTimeout: ReturnType<typeof setTimeout> | null = null;
let reconnectAttempts = 0;
let lastPongAt = 0;
let healthCheckInterval: ReturnType<typeof setInterval> | null = null;
let intentionalDisconnect = false;
const PROACTIVE_RECONNECT_MS = 13 * 60 * 1000; // 13 minutes (D-08: 2-min buffer before Railway's 15-min timeout)
let proactiveReconnectTimeout: ReturnType<typeof setTimeout> | null = null;

interface ActiveCode {
  code: string;
  issuer: string;
  label: string;
  receivedAt: number;
  requestId: string;
}

// ---------- Connection State ----------

type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'code_received' | 'unpaired';

async function setConnectionState(state: ConnectionState): Promise<void> {
  await setSessionState({ connectionState: state });
}

// ---------- WebSocket Management ----------

function connect(roomId: string, relayURL: string): void {
  // Clean up any existing connection
  cleanup();
  intentionalDisconnect = false;

  setConnectionState('connecting');
  console.log(`[BetterAuth] Connecting to room ${roomId.substring(0, 8)}...`);

  const url = `${relayURL}?roomId=${encodeURIComponent(roomId)}`;
  ws = new WebSocket(url);

  ws.onopen = () => {
    console.log('[BetterAuth] WebSocket connected');
    reconnectAttempts = 0; // Reset backoff on successful connect

    // Send join envelope
    const joinMsg = createEnvelope('join');
    ws?.send(JSON.stringify(joinMsg));

    // Start 20-second keepalive pings
    keepaliveInterval = setInterval(() => {
      if (ws?.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(createEnvelope('ping')));
      }
    }, KEEPALIVE_MS);

    // Start health check -- detect stale connections
    lastPongAt = Date.now();
    healthCheckInterval = setInterval(() => {
      const silentMs = Date.now() - lastPongAt;
      if (silentMs > KEEPALIVE_MS * 3) {
        // No pong for 3 keepalive cycles -- connection is stale
        console.warn('[BetterAuth] Connection stale (no pong for', Math.round(silentMs / 1000), 's), reconnecting');
        ws?.close();
      }
    }, KEEPALIVE_MS * 2);

    setConnectionState('connected');

    // D-09: Mark that we should be connected for service worker wake recovery
    setSessionState({ shouldBeConnected: true });

    // Proactive reconnect at 13 minutes (D-08: before Railway's 15-min timeout)
    proactiveReconnectTimeout = setTimeout(async () => {
      console.log('[BetterAuth] Proactive reconnect (13min timer)');
      ws?.close(1000, 'proactive');
      // onclose will trigger scheduleReconnect with delay since intentionalDisconnect is false
    }, PROACTIVE_RECONNECT_MS);
  };

  ws.onmessage = (event: MessageEvent) => {
    handleRelayMessage(event.data as string);
  };

  ws.onclose = (event: CloseEvent) => {
    console.log('[BetterAuth] WebSocket closed, code:', event.code, 'reason:', event.reason || '(none)');
    stopTimers();

    // D-01: accounts only shown while connected; clear on disconnect
    clearAccounts();

    if (intentionalDisconnect) {
      // User-initiated disconnect (unpair) -- don't reconnect
      return;
    }

    setConnectionState('disconnected');
    scheduleReconnect();
  };

  ws.onerror = (event: Event) => {
    console.error('[BetterAuth] WebSocket error:', event);
  };
}

function disconnect(): void {
  intentionalDisconnect = true;
  clearReconnect();
  stopTimers();
  if (ws) {
    ws.close();
    ws = null;
  }
  // Clear shouldBeConnected so wake doesn't auto-reconnect after unpair
  setSessionState({ shouldBeConnected: false });
}

function stopTimers(): void {
  if (keepaliveInterval !== null) {
    clearInterval(keepaliveInterval);
    keepaliveInterval = null;
  }
  if (healthCheckInterval !== null) {
    clearInterval(healthCheckInterval);
    healthCheckInterval = null;
  }
  if (proactiveReconnectTimeout !== null) {
    clearTimeout(proactiveReconnectTimeout);
    proactiveReconnectTimeout = null;
  }
}

function cleanup(): void {
  clearReconnect();
  stopTimers();
  if (ws) {
    ws.onclose = null;
    ws.close();
    ws = null;
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

  // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (capped)
  const delay = Math.min(RECONNECT_BASE_MS * Math.pow(2, reconnectAttempts), RECONNECT_MAX_MS);
  reconnectAttempts++;

  console.log(`[BetterAuth] Scheduling reconnect in ${delay}ms (attempt ${reconnectAttempts})`);

  // Find room to reconnect to: completed pairing first, then pending pairing
  const pairing = await loadPairingData();
  if (pairing) {
    reconnectTimeout = setTimeout(() => connect(pairing.roomId, pairing.relayURL), delay);
    return;
  }

  const pending = await getSessionState<{ roomId: string; privateKey: string }>('pendingPairing');
  if (pending) {
    reconnectTimeout = setTimeout(() => connect(pending.roomId, RELAY_URL), delay);
  }
}

// ---------- Message Routing ----------

async function handleRelayMessage(raw: string): Promise<void> {
  let msg: MessageEnvelope;
  try {
    msg = JSON.parse(raw);
  } catch {
    return;
  }

  if (msg.v !== 1) return;

  switch (msg.type) {
    case 'joined':
      console.log('[BetterAuth] Joined room');
      break;

    case 'pong':
      lastPongAt = Date.now(); // Track for health check
      break;

    case 'error': {
      const code = msg.payload.code ?? '';
      const message = msg.payload.message ?? '';
      console.error('[BetterAuth] Relay error:', code, message);

      // Room-level errors may mean we need to re-pair
      if (code === 'room_full' || code === 'room_not_found') {
        console.warn('[BetterAuth] Room error -- pairing may be stale');
        await setSessionState({ roomError: code });
      }
      break;
    }

    case 'pairing_ack':
      await handlePairingAck(msg);
      break;

    case 'code_response':
      await handleCodeResponse(msg);
      break;

    case 'account_list':
      await handleAccountList(msg);
      break;

    default:
      await handleForwardedMessage(msg);
      break;
  }
}

async function handlePairingAck(msg: MessageEnvelope): Promise<void> {
  const peerPublicKeyBase64 = msg.payload.publicKey as string | undefined;
  if (peerPublicKeyBase64) {
    console.log('[BetterAuth] Received pairing_ack, completing key exchange...');
    await completePairing(peerPublicKeyBase64);
  }
}

async function handleCodeResponse(msg: MessageEnvelope): Promise<void> {
  const pairing = await loadPairingData();
  if (!pairing) return;

  const encryptedBase64 = msg.payload.data as string | undefined;
  if (!encryptedBase64) return;

  try {
    const encrypted = base64ToUint8Array(encryptedBase64);
    const sharedKey = base64ToUint8Array(pairing.sharedKey);
    const decrypted = open(encrypted, sharedKey);
    const decoded = new TextDecoder().decode(decrypted);
    const { code, requestId, issuer, label } = JSON.parse(decoded);

    console.log('[BetterAuth] Code received for', issuer || '(unknown)', ':', code);

    // Store as array of active codes, keyed by issuer to allow updates
    const activeCodes = (await getSessionState<ActiveCode[]>('activeCodes')) || [];
    const entry: ActiveCode = { code, issuer: issuer || '', label: label || '', receivedAt: Date.now(), requestId };
    const existingIdx = activeCodes.findIndex(c => c.issuer === entry.issuer && c.label === entry.label);
    if (existingIdx >= 0) {
      activeCodes[existingIdx] = entry; // Update existing
    } else {
      activeCodes.push(entry); // Add new
    }
    // Remove codes older than 5 minutes
    const fresh = activeCodes.filter(c => Date.now() - c.receivedAt < 5 * 60 * 1000);
    await setSessionState({ activeCodes: fresh });
    await setConnectionState('code_received');

    // Attempt auto-fill on active tab (D-05: immediate fill, no confirmation)
    try {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tab?.id && tab.url?.startsWith('http')) {
        chrome.tabs.sendMessage(tab.id, { type: 'fill_code', code }, (response) => {
          if (chrome.runtime.lastError) {
            // Content script not injected on this page -- fallback to popup display
            console.log('[BetterAuth] Content script not available, popup-only display');
          } else if (response?.filled) {
            console.log('[BetterAuth] Auto-filled TOTP field on page');
          }
        });
      }
    } catch {
      // chrome.tabs.query may fail -- popup display is the fallback
    }
  } catch (err) {
    console.error('[BetterAuth] Failed to decrypt code_response:', err);
  }
}

async function handleAccountList(msg: MessageEnvelope): Promise<void> {
  const pairing = await loadPairingData();
  if (!pairing) return;

  const encryptedBase64 = msg.payload.data as string | undefined;
  if (!encryptedBase64) return;

  try {
    const encrypted = base64ToUint8Array(encryptedBase64);
    const sharedKey = base64ToUint8Array(pairing.sharedKey);
    const decrypted = open(encrypted, sharedKey);
    const decoded = new TextDecoder().decode(decrypted);
    const { accounts } = JSON.parse(decoded) as { accounts: AccountMetadata[] };

    console.log('[BetterAuth] Received account list:', accounts.length, 'accounts');
    await saveAccounts(accounts);
  } catch (err) {
    console.error('[BetterAuth] Failed to decrypt account_list:', err);
  }
}

async function handleForwardedMessage(msg: MessageEnvelope): Promise<void> {
  // During pairing, any forwarded message with publicKey completes the pairing
  const peerPublicKeyBase64 = msg.payload.publicKey as string | undefined;
  if (peerPublicKeyBase64) {
    const pending = await getSessionState<{ roomId: string; privateKey: string }>('pendingPairing');
    if (pending) {
      await completePairing(peerPublicKeyBase64);
      return;
    }
  }

  // During pairing, any forwarded message with encrypted data may be a code response
  const encryptedBase64 = msg.payload.data as string | undefined;
  if (encryptedBase64) {
    const pairing = await loadPairingData();
    if (pairing) {
      await handleCodeResponse(msg);
    }
  }
}

// ---------- Pairing Flow ----------

async function completePairing(peerPublicKeyBase64: string): Promise<void> {
  const pending = await getSessionState<{ roomId: string; privateKey: string }>('pendingPairing');
  if (!pending) {
    console.warn('[BetterAuth] No pending pairing to complete');
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
    await chrome.storage.session.remove('pendingPairing');
    await setConnectionState('connected');
    console.log('[BetterAuth] Pairing completed successfully');
  } catch (err) {
    console.error('[BetterAuth] Pairing completion failed:', err);
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
        console.log('[BetterAuth] WebSocket not open for code request, reconnecting...');
        connect(pairing.roomId, pairing.relayURL);
        sendResponse({ ok: false, error: 'Reconnecting -- try again in a moment' });
        break;
      }

      // Get accountId and domain from popup (D-02)
      const accountId = (message.accountId as string) || '';
      const requestDomain = (message.domain as string) || '';

      // If domain not provided by popup, detect from active tab
      let domain = requestDomain;
      if (!domain) {
        try {
          const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
          if (tab?.url) {
            domain = new URL(tab.url).hostname.replace(/^www\./, '');
          }
        } catch {
          // Tabs API may fail on chrome:// pages
        }
      }

      // Find account metadata to include issuer/label for iOS display
      const accounts = await loadAccounts();
      const account = accounts.find(a => a.id === accountId);

      const codeRequest = {
        id: crypto.randomUUID(),
        issuer: account?.issuer || '',
        label: account?.label || '',
        domain,
        accountId,
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
        console.error('[BetterAuth] Failed to send code request:', err);
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
      const activeCodes = (await getSessionState<ActiveCode[]>('activeCodes')) || [];
      const fresh = activeCodes.filter(c => Date.now() - c.receivedAt < 5 * 60 * 1000);
      const roomError = await getSessionState<string>('roomError');
      const accounts = await loadAccounts();

      // Get current tab domain for account sorting
      let domain = '';
      try {
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (tab?.url?.startsWith('http')) {
          domain = new URL(tab.url).hostname.replace(/^www\./, '');
        }
      } catch {
        // May fail on restricted pages
      }

      sendResponse({
        paired: !!pairing,
        connectionState: connectionState ?? (pairing ? 'disconnected' : 'unpaired'),
        activeCodes: fresh,
        accounts,
        domain,
        roomError,
      });
      break;
    }

    default:
      sendResponse({ ok: false, error: 'Unknown message type' });
  }
}

// ---------- Service Worker Startup ----------

export default defineBackground(() => {
  console.log('[BetterAuth] Service worker started');

  // Register message listener
  chrome.runtime.onMessage.addListener(
    (
      message: { type: string; [key: string]: unknown },
      _sender: chrome.runtime.MessageSender,
      sendResponse: (response?: unknown) => void,
    ) => {
      handlePopupMessage(message, sendResponse).catch((err) => {
        console.error('[BetterAuth] Message handler error:', err);
        sendResponse({ ok: false, error: String(err) });
      });
      return true;
    },
  );

  // D-09: Service worker wake recovery
  // Read pairing from chrome.storage.local and shouldBeConnected from session
  // If shouldBeConnected is true, reconnect immediately (zero-delay)
  // This handles: service worker kill + restart, Chrome update restart, system wake
  Promise.all([
    loadPairingData(),
    getSessionState<boolean>('shouldBeConnected'),
    getSessionState<{ roomId: string; privateKey: string }>('pendingPairing'),
  ]).then(async ([pairing, shouldBeConnected, pending]) => {
    if (pairing && shouldBeConnected) {
      console.log('[BetterAuth] Service worker wake: reconnecting (shouldBeConnected=true)');
      connect(pairing.roomId, pairing.relayURL);
    } else if (pairing && shouldBeConnected === null) {
      // Session storage was cleared (browser restart) but pairing exists
      // Conservative: attempt reconnect since user hasn't explicitly unpaired
      console.log('[BetterAuth] Service worker wake: session cleared, attempting reconnect');
      connect(pairing.roomId, pairing.relayURL);
    } else if (pending) {
      console.log('[BetterAuth] Found pending pairing, reconnecting to room:', pending.roomId);
      connect(pending.roomId, RELAY_URL);
    } else if (pairing) {
      // Paired but shouldBeConnected=false (user unpaired then re-paired?)
      // Set state but don't connect -- user will trigger from popup
      setConnectionState('disconnected');
    } else {
      setConnectionState('unpaired');
    }
  });
});
