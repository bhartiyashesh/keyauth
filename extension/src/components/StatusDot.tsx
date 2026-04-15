interface StatusDotProps {
  state: 'connected' | 'disconnected' | 'connecting';
}

const COLORS: Record<StatusDotProps['state'], string> = {
  connected: '#22c55e',
  disconnected: '#ef4444',
  connecting: '#f59e0b',
};

export default function StatusDot({ state }: StatusDotProps) {
  return (
    <span
      className={`status-dot ${state === 'connecting' ? 'status-dot--pulse' : ''}`}
      style={{
        display: 'inline-block',
        width: 8,
        height: 8,
        borderRadius: '50%',
        backgroundColor: COLORS[state],
      }}
    />
  );
}
