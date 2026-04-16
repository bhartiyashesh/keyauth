import { useCallback, useEffect, useRef, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { generateKeyPair, uint8ArrayToBase64 } from '../lib/crypto';

const RELAY_URL = 'wss://cooperative-respect-production-29f8.up.railway.app';
const QR_TTL_MS = 5 * 60 * 1000; // 5 minutes

export default function PairingView() {
  const [qrData, setQrData] = useState<string | null>(null);
  const [secondsLeft, setSecondsLeft] = useState(0);
  const ttlTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const refreshTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const expiresAtRef = useRef<number>(0);

  const generateQR = useCallback(async () => {
    // Clear existing timers
    if (ttlTimerRef.current) clearInterval(ttlTimerRef.current);
    if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current);

    let privateKey: Uint8Array;
    let publicKey: Uint8Array;
    try {
      const kp = generateKeyPair();
      privateKey = kp.privateKey;
      publicKey = kp.publicKey;
    } catch (err) {
      console.error('[PairingView] generateKeyPair failed:', err);
      return;
    }
    const roomId = crypto.randomUUID();

    const payload = JSON.stringify({
      roomId,
      relayURL: RELAY_URL,
      publicKey: uint8ArrayToBase64(publicKey),
    });

    setQrData(payload);

    // Store privateKey in session for pairing completion
    await chrome.storage.session.set({
      pendingPairing: {
        roomId,
        privateKey: uint8ArrayToBase64(privateKey),
      },
    });

    // Notify service worker to connect to the room
    chrome.runtime.sendMessage({
      type: 'start_pairing',
      roomId,
      relayURL: RELAY_URL,
    });

    // Start TTL countdown
    const expiresAt = Date.now() + QR_TTL_MS;
    expiresAtRef.current = expiresAt;
    setSecondsLeft(Math.ceil(QR_TTL_MS / 1000));

    ttlTimerRef.current = setInterval(() => {
      const remaining = Math.max(0, Math.ceil((expiresAtRef.current - Date.now()) / 1000));
      setSecondsLeft(remaining);
      if (remaining <= 0 && ttlTimerRef.current) {
        clearInterval(ttlTimerRef.current);
      }
    }, 1000);

    // Auto-refresh on expiry
    refreshTimerRef.current = setTimeout(() => {
      generateQR();
    }, QR_TTL_MS);
  }, []);

  useEffect(() => {
    generateQR();

    return () => {
      if (ttlTimerRef.current) clearInterval(ttlTimerRef.current);
      if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current);
    };
  }, [generateQR]);

  const minutes = Math.floor(secondsLeft / 60);
  const seconds = secondsLeft % 60;

  return (
    <div className="pairing-view">
      <p className="pairing-label">Scan with Better Authenticator on your phone</p>
      <div className="qr-container">
        {qrData && (
          <QRCodeSVG value={qrData} size={200} level="M" />
        )}
      </div>
      <p className="ttl-countdown">
        Expires in {minutes}:{seconds.toString().padStart(2, '0')}
      </p>
    </div>
  );
}
