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

export default function CodeView({ code, issuer, label, receivedAt: _receivedAt, onDismiss }: CodeViewProps) {
  const [secondsRemaining, setSecondsRemaining] = useState(() => {
    return 30 - (Math.floor(Date.now() / 1000) % 30);
  });
  const [copied, setCopied] = useState(false);
  const copiedTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Format code with space separator: "482 937"
  const formattedCode = code.length === 6
    ? code.slice(0, 3) + ' ' + code.slice(3)
    : code;

  // Countdown timer with 1-second updates
  useEffect(() => {
    const interval = setInterval(() => {
      const remaining = 30 - (Math.floor(Date.now() / 1000) % 30);
      setSecondsRemaining(remaining);

      if (remaining <= 0) {
        onDismiss();
      }
    }, 1_000);

    return () => clearInterval(interval);
  }, [onDismiss]);

  // Cleanup copied toast timeout on unmount
  useEffect(() => {
    return () => {
      if (copiedTimeoutRef.current) {
        clearTimeout(copiedTimeoutRef.current);
      }
    };
  }, []);

  const handleCopy = useCallback(async () => {
    try {
      // Copy raw 6-digit code (no spaces)
      await navigator.clipboard.writeText(code);

      // Show "Copied!" toast
      setCopied(true);
      if (copiedTimeoutRef.current) {
        clearTimeout(copiedTimeoutRef.current);
      }
      copiedTimeoutRef.current = setTimeout(() => {
        setCopied(false);
      }, 2_000);

      // Auto-clear clipboard after 30 seconds
      setTimeout(async () => {
        try {
          await navigator.clipboard.writeText('');
        } catch {
          // Popup may be closed; best-effort clear
        }
      }, 30_000);
    } catch (err) {
      console.error('[KeyAuth] Clipboard write failed:', err);
    }
  }, [code]);

  const handleRequestAnother = useCallback(() => {
    chrome.runtime.sendMessage({ type: 'request_code' });
  }, []);

  return (
    <div className="code-view">
      <p className="code-label">
        {issuer ? `${issuer}${label ? ` (${label})` : ''}` : 'Code received'}
      </p>

      <div className="countdown-ring">
        <CountdownRing secondsRemaining={secondsRemaining} size={48} />
      </div>

      <div className="code-display">
        {formattedCode}
      </div>

      <button type="button" className="btn-primary copy-btn" onClick={handleCopy}>
        {copied ? 'Copied!' : 'Copy Code'}
      </button>

      {copied && (
        <p className="toast">Copied to clipboard</p>
      )}

      <button type="button" className="btn-link request-another" onClick={handleRequestAnother}>
        Request Another
      </button>
    </div>
  );
}
