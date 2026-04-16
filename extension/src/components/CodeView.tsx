import { useEffect, useState, useRef, useCallback } from 'react';

interface CodeViewProps {
  code: string;
  issuer: string;
  label: string;
  receivedAt: number;
  onDismiss: () => void;
}

function CountdownRing({ secondsRemaining, size }: { secondsRemaining: number; size: number }) {
  const radius = (size - 4) / 2;
  const circumference = 2 * Math.PI * radius;
  const progress = secondsRemaining / 30;
  const dashOffset = circumference * (1 - progress);

  return (
    <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }}>
      <circle
        cx={size / 2}
        cy={size / 2}
        r={radius}
        fill="none"
        stroke="#e0e0e0"
        strokeWidth={2.5}
      />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={radius}
        fill="none"
        stroke={secondsRemaining <= 5 ? '#ef4444' : '#22c55e'}
        strokeWidth={2.5}
        strokeDasharray={circumference}
        strokeDashoffset={dashOffset}
        strokeLinecap="round"
        style={{ transition: 'stroke-dashoffset 1s linear' }}
      />
      <text
        x={size / 2}
        y={size / 2}
        textAnchor="middle"
        dominantBaseline="central"
        style={{ transform: 'rotate(90deg)', transformOrigin: 'center', fontSize: 11, fill: 'currentColor' }}
      >
        {secondsRemaining}s
      </text>
    </svg>
  );
}

export default function CodeView({ code, issuer, label, receivedAt: _receivedAt, onDismiss }: CodeViewProps) {
  const [secondsRemaining, setSecondsRemaining] = useState(() => {
    return 30 - (Math.floor(Date.now() / 1000) % 30);
  });
  const [copied, setCopied] = useState(false);
  const copiedTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const formattedCode = code.length === 6
    ? code.slice(0, 3) + ' ' + code.slice(3)
    : code;

  const initial = (issuer && issuer !== 'Unknown' ? issuer : label || '?')[0].toUpperCase();
  const displayName = issuer && issuer !== 'Unknown' ? issuer : label || 'Unknown';
  const badgeColor = `hsl(${[...displayName].reduce((a, c) => a + c.charCodeAt(0), 0) % 360}, 55%, 50%)`;

  // Countdown timer -- dismiss when period ends
  useEffect(() => {
    const interval = setInterval(() => {
      const remaining = 30 - (Math.floor(Date.now() / 1000) % 30);
      setSecondsRemaining(remaining);
      if (remaining === 30) {
        // New TOTP period started -- old code is expired
        onDismiss();
      }
    }, 1_000);
    return () => clearInterval(interval);
  }, [onDismiss]);

  useEffect(() => {
    return () => { if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current); };
  }, []);

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current);
      copiedTimeoutRef.current = setTimeout(() => setCopied(false), 2_000);
      setTimeout(async () => {
        try { await navigator.clipboard.writeText(''); } catch {}
      }, 30_000);
    } catch (err) {
      console.error('[KeyAuth] Clipboard write failed:', err);
    }
  }, [code]);

  return (
    <div className="code-card">
      <div className="code-card-header">
        <div className="code-account-badge" style={{ backgroundColor: badgeColor }}>
          {initial}
        </div>
        <div className="code-card-info">
          <span className="code-card-issuer">{displayName}</span>
          {issuer && label && <span className="code-card-label">{label}</span>}
        </div>
        <button type="button" className="code-card-dismiss" onClick={onDismiss} title="Dismiss">
          &times;
        </button>
      </div>

      <div className="code-card-body">
        <button
          type="button"
          className={`code-card-code ${copied ? 'code-card-code--copied' : ''}`}
          onClick={handleCopy}
          title="Click to copy"
        >
          {formattedCode}
        </button>
        <CountdownRing secondsRemaining={secondsRemaining} size={34} />
      </div>

      {copied && <p className="code-card-status code-card-status--copied">Copied!</p>}
    </div>
  );
}
