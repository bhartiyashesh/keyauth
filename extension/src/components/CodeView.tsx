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
        strokeWidth={3}
      />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={radius}
        fill="none"
        stroke={secondsRemaining <= 5 ? '#ef4444' : '#22c55e'}
        strokeWidth={3}
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
        style={{ transform: 'rotate(90deg)', transformOrigin: 'center', fontSize: 14, fill: 'currentColor' }}
      >
        {secondsRemaining}s
      </text>
    </svg>
  );
}

export default function CodeView({ code, issuer, label, receivedAt, onDismiss }: CodeViewProps) {
  const [secondsRemaining, setSecondsRemaining] = useState(() => {
    return 30 - (Math.floor(Date.now() / 1000) % 30);
  });
  const [copied, setCopied] = useState(false);
  const [stale, setStale] = useState(false);
  const copiedTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastCodeRef = useRef(code);
  const autoRequestedRef = useRef(false);

  // Format code with space separator: "482 937"
  const formattedCode = code.length === 6
    ? code.slice(0, 3) + ' ' + code.slice(3)
    : code;

  // Detect when code updates (phone sent a fresh one)
  useEffect(() => {
    if (code !== lastCodeRef.current) {
      lastCodeRef.current = code;
      setStale(false);
      autoRequestedRef.current = false;
    }
  }, [code]);

  // Countdown timer + staleness detection
  useEffect(() => {
    const interval = setInterval(() => {
      const remaining = 30 - (Math.floor(Date.now() / 1000) % 30);
      setSecondsRemaining(remaining);

      // Code is stale if it's been more than 35 seconds since received
      const age = Date.now() - receivedAt;
      if (age > 35_000 && !autoRequestedRef.current) {
        setStale(true);
        // Auto-request a fresh code from the phone
        autoRequestedRef.current = true;
        chrome.runtime.sendMessage({ type: 'request_code' });
      }
    }, 1_000);

    return () => clearInterval(interval);
  }, [receivedAt]);

  // Cleanup
  useEffect(() => {
    return () => {
      if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current);
    };
  }, []);

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current);
      copiedTimeoutRef.current = setTimeout(() => setCopied(false), 2_000);

      // Auto-clear clipboard after 30 seconds
      setTimeout(async () => {
        try { await navigator.clipboard.writeText(''); } catch {}
      }, 30_000);
    } catch (err) {
      console.error('[KeyAuth] Clipboard write failed:', err);
    }
  }, [code]);

  const handleRequestAnother = useCallback(() => {
    chrome.runtime.sendMessage({ type: 'request_code' });
  }, []);

  // Generate initial letter + color for the account badge
  const initial = (issuer || '?')[0].toUpperCase();
  const badgeColor = issuer
    ? `hsl(${[...issuer].reduce((a, c) => a + c.charCodeAt(0), 0) % 360}, 55%, 50%)`
    : '#888';

  return (
    <div className="code-view">
      {issuer ? (
        <div className="code-account">
          <div className="code-account-badge" style={{ backgroundColor: badgeColor }}>
            {initial}
          </div>
          <div className="code-account-info">
            <span className="code-account-issuer">{issuer}</span>
            {label && <span className="code-account-label">{label}</span>}
          </div>
        </div>
      ) : (
        <p className="code-label">Code received</p>
      )}

      <div className="code-row">
        <div className="code-display" style={{ opacity: stale ? 0.4 : 1 }}>
          {formattedCode}
        </div>
        <div className="countdown-ring">
          <CountdownRing secondsRemaining={secondsRemaining} size={40} />
        </div>
      </div>

      {stale && (
        <p className="refreshing-text">Refreshing...</p>
      )}

      {!stale && (
        <button type="button" className="btn-primary copy-btn" onClick={handleCopy}>
          {copied ? 'Copied!' : 'Copy Code'}
        </button>
      )}

      {copied && !stale && (
        <p className="toast">Copied to clipboard</p>
      )}

      <button type="button" className="btn-link request-another" onClick={handleRequestAnother}>
        Request Another
      </button>
    </div>
  );
}
